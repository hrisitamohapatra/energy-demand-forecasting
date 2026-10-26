-- 02_load_raw.sql: loads the CSVs untouched.
-- \copy is a psql command, so run this through psql from the PROJECT ROOT
-- (run_pipeline.py does this). Paths are relative to the project root.

TRUNCATE raw.pjme_hourly, raw.weather_hourly;

\copy raw.pjme_hourly (datetime, pjme_mw) FROM 'data/PJME_hourly.csv' WITH (FORMAT csv, HEADER true)

\copy raw.weather_hourly (time, temperature_2m, relative_humidity_2m, wind_speed_10m) FROM 'data/weather_philly.csv' WITH (FORMAT csv, HEADER true)

SELECT 'raw.pjme_hourly'    AS table_name, count(*) AS row_count FROM raw.pjme_hourly
UNION ALL
SELECT 'raw.weather_hourly', count(*) FROM raw.weather_hourly;
