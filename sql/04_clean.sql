-- 04_clean.sql: one clean, gap-free hourly table with weather attached.
--
-- Timestamps are local wall-clock time (America/New_York) in both sources.
-- DST handling, chosen so that every day has exactly 24 rows and
-- LAG(24) always means "same clock hour yesterday":
--   * fall-back hour (appears twice)       -> the two readings are averaged
--   * spring-forward / other missing hours -> linearly interpolated, is_imputed = true
-- Outliers are FLAGGED, never deleted.

-- Weather: one row per timestamp.
DROP TABLE IF EXISTS clean.weather_hourly;
CREATE TABLE clean.weather_hourly AS
SELECT ts,
       avg(temp_c)::numeric(6,2)       AS temp_c,
       avg(humidity_pct)::numeric(6,2) AS humidity_pct,
       avg(wind_kmh)::numeric(6,2)     AS wind_kmh
FROM staging.weather_hourly
GROUP BY ts;
ALTER TABLE clean.weather_hourly ADD PRIMARY KEY (ts);

-- Load: dedup -> full hourly grid -> interpolate gaps -> flag outliers -> join weather.
DROP TABLE IF EXISTS clean.load_hourly;
CREATE TABLE clean.load_hourly AS
WITH dedup AS (
    SELECT ts, avg(load_mw) AS load_mw, count(*) AS source_row_count
    FROM staging.load_hourly
    GROUP BY ts
    HAVING avg(load_mw) IS NOT NULL
),
bounds AS (
    SELECT min(ts) AS t0, max(ts) AS t1 FROM dedup
),
grid AS (
    SELECT g.ts
    FROM bounds b, generate_series(b.t0, b.t1, interval '1 hour') AS g(ts)
),
joined AS (
    SELECT g.ts, d.load_mw, COALESCE(d.source_row_count, 0) AS source_row_count
    FROM grid g
    LEFT JOIN dedup d ON d.ts = g.ts
),
marked AS (
    -- count(load_mw) only increases on rows with a value, so each run of missing
    -- rows shares a group with the known row before it (fwd) or after it (bwd).
    SELECT *,
           count(load_mw) OVER (ORDER BY ts)      AS grp_fwd,
           count(load_mw) OVER (ORDER BY ts DESC) AS grp_bwd
    FROM joined
),
neighbours AS (
    SELECT ts, load_mw, source_row_count,
           max(load_mw) OVER (PARTITION BY grp_fwd) AS prev_val,
           min(ts)      OVER (PARTITION BY grp_fwd) AS prev_ts,
           max(load_mw) OVER (PARTITION BY grp_bwd) AS next_val,
           max(ts)      OVER (PARTITION BY grp_bwd) AS next_ts
    FROM marked
),
gapfilled AS (
    SELECT ts,
           CASE WHEN load_mw IS NOT NULL THEN load_mw
                ELSE prev_val + (next_val - prev_val)
                     * EXTRACT(EPOCH FROM (ts - prev_ts))
                     / EXTRACT(EPOCH FROM (next_ts - prev_ts))
           END AS load_mw,
           (load_mw IS NULL) AS is_imputed,
           source_row_count
    FROM neighbours
),
with_nb AS (
    SELECT *,
           LAG(load_mw)  OVER (ORDER BY ts) AS prev_mw,
           LEAD(load_mw) OVER (ORDER BY ts) AS next_mw
    FROM gapfilled
)
SELECT n.ts,
       n.load_mw::numeric(12,2) AS load_mw,
       n.is_imputed,
       n.source_row_count,
       -- outlier = non-positive, or a local spike/dip: more than 25% away from BOTH
       -- neighbouring hours, in the same direction (so a spike's neighbours are not flagged)
       CASE
           WHEN n.is_imputed THEN false
           WHEN n.load_mw <= 0 THEN true
           WHEN n.prev_mw IS NOT NULL AND n.next_mw IS NOT NULL
                AND abs(n.load_mw - n.prev_mw) > 0.25 * n.prev_mw
                AND abs(n.load_mw - n.next_mw) > 0.25 * n.next_mw
                AND sign(n.load_mw - n.prev_mw) = sign(n.load_mw - n.next_mw) THEN true
           ELSE false
       END AS is_outlier,
       w.temp_c, w.humidity_pct, w.wind_kmh
FROM with_nb n
LEFT JOIN clean.weather_hourly w ON w.ts = n.ts;

ALTER TABLE clean.load_hourly ADD PRIMARY KEY (ts);

SELECT count(*)                                  AS clean_rows,
       count(*) FILTER (WHERE is_imputed)        AS imputed_rows,
       count(*) FILTER (WHERE source_row_count > 1) AS duplicate_rows_averaged,
       count(*) FILTER (WHERE is_outlier)        AS outlier_rows,
       count(*) FILTER (WHERE temp_c IS NULL)    AS rows_without_weather,
       min(ts) AS first_ts, max(ts) AS last_ts
FROM clean.load_hourly;
