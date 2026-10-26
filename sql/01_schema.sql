-- 01_schema.sql: (re)creates the four layers from scratch.
-- WARNING: drops and rebuilds every schema, so the whole pipeline is rerunnable.

DROP SCHEMA IF EXISTS raw     CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS clean   CASCADE;
DROP SCHEMA IF EXISTS mart    CASCADE;

CREATE SCHEMA raw;
CREATE SCHEMA staging;
CREATE SCHEMA clean;
CREATE SCHEMA mart;

-- RAW: everything is text so a bad value can never block a load.
CREATE TABLE raw.pjme_hourly (
    datetime text,
    pjme_mw  text
);

CREATE TABLE raw.weather_hourly (
    time                  text,
    temperature_2m        text,
    relative_humidity_2m  text,
    wind_speed_10m        text
);

-- STAGING: typed columns, still one row per source row (duplicates kept on purpose).
CREATE TABLE staging.load_hourly (
    ts           timestamp NOT NULL,   -- local (America/New_York) wall-clock time
    load_mw      numeric,
    source_file  text NOT NULL
);

CREATE TABLE staging.weather_hourly (
    ts            timestamp NOT NULL,  -- local (America/New_York) wall-clock time
    temp_c        numeric,
    humidity_pct  numeric,
    wind_kmh      numeric,
    source_file   text NOT NULL
);
-- US federal holidays, filled by src/load_holidays.py (pipeline step 03b).
CREATE TABLE staging.holidays (
    holiday_date  date PRIMARY KEY,
    holiday_name  text NOT NULL
);

-- clean and mart tables are created by 04_clean.sql to 06_star_schema.sql.
