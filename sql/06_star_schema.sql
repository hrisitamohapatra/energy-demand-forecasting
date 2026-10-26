-- 06_star_schema.sql: star schema for Power BI.
-- dim_date, dim_hour, dim_model, fact_load_hourly are filled here.
-- fact_forecast and fact_forecast_scenario are created empty; Python fills them in week 4.

DROP TABLE IF EXISTS mart.fact_forecast_scenario CASCADE;
DROP TABLE IF EXISTS mart.fact_forecast CASCADE;
DROP TABLE IF EXISTS mart.fact_load_hourly CASCADE;
DROP TABLE IF EXISTS mart.dim_model;
DROP TABLE IF EXISTS mart.dim_hour;
DROP TABLE IF EXISTS mart.dim_date;

-- Contiguous calendar covering every load date.
CREATE TABLE mart.dim_date AS
SELECT d::date                                   AS date_key,
       EXTRACT(YEAR    FROM d)::int              AS year,
       EXTRACT(QUARTER FROM d)::int              AS quarter,
       EXTRACT(MONTH   FROM d)::int              AS month,
       to_char(d, 'Mon')                         AS month_name,
       EXTRACT(DAY     FROM d)::int              AS day_of_month,
       EXTRACT(ISODOW  FROM d)::int              AS day_of_week,   -- 1 = Monday
       to_char(d, 'Dy')                          AS day_name,
       (EXTRACT(ISODOW FROM d) >= 6)             AS is_weekend,
       CASE WHEN EXTRACT(MONTH FROM d) IN (12, 1, 2)  THEN 'Winter'
            WHEN EXTRACT(MONTH FROM d) IN (3, 4, 5)   THEN 'Spring'
            WHEN EXTRACT(MONTH FROM d) IN (6, 7, 8)   THEN 'Summer'
            ELSE 'Fall' END                      AS season,
       (h.holiday_date IS NOT NULL)              AS is_holiday,
       h.holiday_name
FROM generate_series(
         (SELECT min(ts)::date FROM clean.load_hourly),
         (SELECT max(ts)::date FROM clean.load_hourly),
         interval '1 day') AS g(d)
LEFT JOIN staging.holidays h ON h.holiday_date = g.d::date;
ALTER TABLE mart.dim_date ADD PRIMARY KEY (date_key);

-- is_peak_period is an ASSUMPTION (15:00-20:59). Change the range here if you prefer another.
CREATE TABLE mart.dim_hour AS
SELECT h                                         AS hour_of_day,
       to_char(h, 'FM00') || ':00'               AS hour_label,
       (h BETWEEN 15 AND 20)                     AS is_peak_period
FROM generate_series(0, 23) AS g(h);
ALTER TABLE mart.dim_hour ADD PRIMARY KEY (hour_of_day);

CREATE TABLE mart.dim_model (
    model_key    serial PRIMARY KEY,
    model_name   text UNIQUE NOT NULL,
    model_family text NOT NULL,
    description  text
);
INSERT INTO mart.dim_model (model_name, model_family, description) VALUES
    ('seasonal_naive', 'baseline',    'Same hour, same weekday, last week'),
    ('prophet',        'statistical', 'Prophet with temperature regressor and holidays'),
    ('sarima',         'statistical', 'SARIMA on daily peak load'),
    ('lightgbm',       'machine_learning', 'LightGBM on lag, rolling, calendar and temperature features');

CREATE TABLE mart.fact_load_hourly AS
SELECT ts,
       ts::date                      AS date_key,
       EXTRACT(HOUR FROM ts)::int    AS hour_of_day,
       load_mw, temp_c, humidity_pct, wind_kmh,
       is_outlier, is_imputed
FROM clean.load_hourly;
ALTER TABLE mart.fact_load_hourly ADD PRIMARY KEY (ts);
ALTER TABLE mart.fact_load_hourly ADD FOREIGN KEY (date_key)    REFERENCES mart.dim_date (date_key);
ALTER TABLE mart.fact_load_hourly ADD FOREIGN KEY (hour_of_day) REFERENCES mart.dim_hour (hour_of_day);

CREATE TABLE mart.fact_forecast (
    ts           timestamp NOT NULL REFERENCES mart.fact_load_hourly (ts),
    model_key    int       NOT NULL REFERENCES mart.dim_model (model_key),
    split        text      NOT NULL CHECK (split IN ('train', 'validation', 'test', 'backtest')),
    forecast_mw  numeric(12,2) NOT NULL,
    actual_mw    numeric(12,2) NOT NULL,
    PRIMARY KEY (ts, model_key, split)
);

CREATE TABLE mart.fact_forecast_scenario (
    ts            timestamp NOT NULL REFERENCES mart.fact_load_hourly (ts),
    model_key     int       NOT NULL REFERENCES mart.dim_model (model_key),
    temp_offset_c numeric(4,1) NOT NULL,
    forecast_mw   numeric(12,2) NOT NULL,
    PRIMARY KEY (ts, model_key, temp_offset_c)
);

SELECT 'dim_date' AS table_name, count(*) AS row_count FROM mart.dim_date
UNION ALL SELECT 'dim_hour', count(*) FROM mart.dim_hour
UNION ALL SELECT 'dim_model', count(*) FROM mart.dim_model
UNION ALL SELECT 'fact_load_hourly', count(*) FROM mart.fact_load_hourly;
