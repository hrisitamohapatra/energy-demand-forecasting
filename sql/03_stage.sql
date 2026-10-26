-- 03_stage.sql: casts types, parses timestamps and tags the source file.
-- No rows are removed here. Duplicates and gaps are fixed in 04_clean.sql.

TRUNCATE staging.load_hourly, staging.weather_hourly;

INSERT INTO staging.load_hourly (ts, load_mw, source_file)
SELECT
    NULLIF(btrim(datetime), '')::timestamp,
    NULLIF(btrim(pjme_mw), '')::numeric,
    'PJME_hourly.csv'
FROM raw.pjme_hourly
WHERE NULLIF(btrim(datetime), '') IS NOT NULL;

INSERT INTO staging.weather_hourly (ts, temp_c, humidity_pct, wind_kmh, source_file)
SELECT
    NULLIF(btrim(time), '')::timestamp,            -- Open-Meteo gives e.g. 2002-01-01T00:00
    NULLIF(btrim(temperature_2m), '')::numeric,
    NULLIF(btrim(relative_humidity_2m), '')::numeric,
    NULLIF(btrim(wind_speed_10m), '')::numeric,
    'open-meteo philly_2002_2018'
FROM raw.weather_hourly
WHERE NULLIF(btrim(time), '') IS NOT NULL;

-- Sanity summary: compare with the source file row counts.
SELECT 'staging.load_hourly' AS table_name,
       count(*)              AS row_count,
       count(DISTINCT ts)    AS distinct_ts,
       count(*) - count(DISTINCT ts) AS duplicate_ts,
       min(ts) AS first_ts, max(ts) AS last_ts
FROM staging.load_hourly
UNION ALL
SELECT 'staging.weather_hourly', count(*), count(DISTINCT ts),
       count(*) - count(DISTINCT ts), min(ts), max(ts)
FROM staging.weather_hourly;
