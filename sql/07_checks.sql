-- 07_checks.sql: data quality assertions. Prints every check, then fails the
-- pipeline (non-zero exit) if any check failed.

CREATE TEMP TABLE check_results (
    id         serial,
    check_name text,
    passed     boolean,
    detail     text
);

-- 1. Clean layer is a complete hourly grid (no gaps, no duplicates)
INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: no gaps in hourly grid',
       count(*) = (EXTRACT(EPOCH FROM (max(ts) - min(ts))) / 3600)::bigint + 1,
       count(*) || ' rows, expected ' || ((EXTRACT(EPOCH FROM (max(ts) - min(ts))) / 3600)::bigint + 1)
FROM clean.load_hourly;

INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: no duplicate timestamps', count(*) = count(DISTINCT ts), (count(*) - count(DISTINCT ts)) || ' duplicates'
FROM clean.load_hourly;

-- 2. No nulls
INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: no null load_mw', count(*) = 0, count(*) || ' null rows'
FROM clean.load_hourly WHERE load_mw IS NULL;

INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: no null weather', count(*) = 0, count(*) || ' rows without weather'
FROM clean.load_hourly WHERE temp_c IS NULL OR humidity_pct IS NULL OR wind_kmh IS NULL;

-- 3. Plausible MW range for non-outlier rows (PJM East is roughly 14,000-62,000 MW)
INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: load within 10,000-70,000 MW (non-outliers)',
       count(*) = 0, count(*) || ' rows out of range'
FROM clean.load_hourly
WHERE NOT is_outlier AND (load_mw < 10000 OR load_mw > 70000);

-- 4. Cleaning stayed modest
INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: outliers under 1% of rows',
       count(*) FILTER (WHERE is_outlier) < 0.01 * count(*),
       count(*) FILTER (WHERE is_outlier) || ' outliers of ' || count(*)
FROM clean.load_hourly;

INSERT INTO check_results (check_name, passed, detail)
SELECT 'clean: imputed rows under 1% of rows',
       count(*) FILTER (WHERE is_imputed) < 0.01 * count(*),
       count(*) FILTER (WHERE is_imputed) || ' imputed of ' || count(*)
FROM clean.load_hourly;

-- 5. Features: no nulls in model inputs
INSERT INTO check_results (check_name, passed, detail)
SELECT 'features: no nulls in lag / rolling / weather columns', count(*) = 0, count(*) || ' rows with nulls'
FROM mart.features_hourly
WHERE load_lag_24h IS NULL OR load_lag_48h IS NULL OR load_lag_168h IS NULL
   OR load_roll_24h IS NULL OR load_roll_7d IS NULL OR load_std_7d IS NULL
   OR temp_c IS NULL OR humidity_pct IS NULL OR wind_kmh IS NULL;

-- 6. LEAKAGE TESTS: each lag must equal the load exactly N hours earlier
INSERT INTO check_results (check_name, passed, detail)
SELECT 'leakage: load_lag_24h = load 24h earlier', count(*) = 0, count(*) || ' mismatches'
FROM mart.features_hourly f
JOIN clean.load_hourly c ON c.ts = f.ts - interval '24 hours'
WHERE c.load_mw IS DISTINCT FROM f.load_lag_24h;

INSERT INTO check_results (check_name, passed, detail)
SELECT 'leakage: load_lag_168h = load 168h earlier', count(*) = 0, count(*) || ' mismatches'
FROM mart.features_hourly f
JOIN clean.load_hourly c ON c.ts = f.ts - interval '168 hours'
WHERE c.load_mw IS DISTINCT FROM f.load_lag_168h;

-- load_roll_7d must equal the average of the 168 hours ending 24h before ts
-- (checked on every 500th feature row; the join recomputes it independently)
INSERT INTO check_results (check_name, passed, detail)
WITH sample AS (
    SELECT ts, load_roll_7d, row_number() OVER (ORDER BY ts) AS rn FROM mart.features_hourly
),
recomputed AS (
    SELECT s.ts, s.load_roll_7d, avg(c.load_mw) AS expected
    FROM sample s
    JOIN clean.load_hourly c
      ON c.ts BETWEEN s.ts - interval '191 hours' AND s.ts - interval '24 hours'
    WHERE s.rn % 500 = 0
    GROUP BY s.ts, s.load_roll_7d
)
SELECT 'leakage: load_roll_7d window ends 24h before ts',
       count(*) FILTER (WHERE abs(load_roll_7d - expected) > 0.01) = 0,
       count(*) FILTER (WHERE abs(load_roll_7d - expected) > 0.01) || ' mismatches in ' || count(*) || ' sampled rows'
FROM recomputed;

-- 7. Star schema integrity
INSERT INTO check_results (check_name, passed, detail)
SELECT 'star: fact_load_hourly row count = clean row count',
       (SELECT count(*) FROM mart.fact_load_hourly) = (SELECT count(*) FROM clean.load_hourly),
       (SELECT count(*) FROM mart.fact_load_hourly) || ' vs ' || (SELECT count(*) FROM clean.load_hourly);

INSERT INTO check_results (check_name, passed, detail)
SELECT 'star: dim_date covers every day without gaps',
       count(*) = (max(date_key) - min(date_key)) + 1, count(*) || ' days'
FROM mart.dim_date;

INSERT INTO check_results (check_name, passed, detail)
SELECT 'star: dim_hour has 24 rows and dim_model has 4',
       (SELECT count(*) FROM mart.dim_hour) = 24 AND (SELECT count(*) FROM mart.dim_model) = 4,
       (SELECT count(*) FROM mart.dim_hour) || ' hours, ' || (SELECT count(*) FROM mart.dim_model) || ' models';

INSERT INTO check_results (check_name, passed, detail)
SELECT 'star: holidays loaded into dim_date (at least 8 per year)',
       count(*) FILTER (WHERE is_holiday) >= 8 * ((max(date_key) - min(date_key)) / 365),
       count(*) FILTER (WHERE is_holiday) || ' holiday days over ' || ((max(date_key) - min(date_key)) / 365) || ' years'
FROM mart.dim_date;

-- Report
SELECT id, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result, check_name, detail
FROM check_results ORDER BY id;

SELECT 'raw.pjme_hourly' AS layer_table, count(*) AS row_count FROM raw.pjme_hourly
UNION ALL SELECT 'staging.load_hourly', count(*) FROM staging.load_hourly
UNION ALL SELECT 'clean.load_hourly', count(*) FROM clean.load_hourly
UNION ALL SELECT 'mart.features_hourly', count(*) FROM mart.features_hourly
UNION ALL SELECT 'mart.fact_load_hourly', count(*) FROM mart.fact_load_hourly;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM check_results WHERE NOT passed) THEN
        RAISE EXCEPTION 'Data quality checks failed: see FAIL rows above';
    END IF;
END $$;
