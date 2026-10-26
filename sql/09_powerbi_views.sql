-- 09_powerbi_views.sql: views that keep the Power BI model and DAX simple.
-- Power BI imports these (renamed in Power Query) instead of the raw forecast tables.
-- Imputed hours are excluded so Power BI accuracy matches the Python metrics.

DROP VIEW IF EXISTS mart.v_daily_peak_forecast;
DROP VIEW IF EXISTS mart.v_fact_forecast_scenario;
DROP VIEW IF EXISTS mart.v_fact_forecast;

-- One row per (hour, model, split) with error columns ready to SUM / AVERAGE.
CREATE VIEW mart.v_fact_forecast AS
SELECT f.ts,
       f.ts::date                              AS date_key,
       EXTRACT(HOUR FROM f.ts)::int            AS hour_of_day,
       f.model_key,
       f.split,
       f.forecast_mw,
       f.actual_mw,
       f.forecast_mw - f.actual_mw             AS error_mw,           -- + = over-forecast
       abs(f.forecast_mw - f.actual_mw)        AS abs_error_mw,
       GREATEST(f.actual_mw - f.forecast_mw, 0) AS under_forecast_mw, -- MW short (each row = 1 hour = MWh)
       GREATEST(f.forecast_mw - f.actual_mw, 0) AS over_forecast_mw,  -- MW surplus
       l.temp_c
FROM mart.fact_forecast f
JOIN mart.fact_load_hourly l ON l.ts = f.ts
WHERE NOT l.is_imputed;

-- Temperature what-if forecasts (LightGBM scored at -5..+5 C).
CREATE VIEW mart.v_fact_forecast_scenario AS
SELECT s.ts,
       s.ts::date                   AS date_key,
       EXTRACT(HOUR FROM s.ts)::int AS hour_of_day,
       s.model_key,
       s.temp_offset_c,
       s.forecast_mw
FROM mart.fact_forecast_scenario s;

-- One row per (day, model, split): actual vs forecast daily peak and peak hour.
-- Only complete 24-hour days with no imputed hours.
CREATE VIEW mart.v_daily_peak_forecast AS
WITH hourly AS (
    SELECT f.ts::date AS date_key, EXTRACT(HOUR FROM f.ts)::int AS hr,
           f.model_key, f.split, f.forecast_mw, f.actual_mw, l.is_imputed
    FROM mart.fact_forecast f
    JOIN mart.fact_load_hourly l ON l.ts = f.ts
),
good_days AS (
    SELECT date_key, model_key, split
    FROM hourly
    GROUP BY date_key, model_key, split
    HAVING count(*) = 24 AND NOT bool_or(is_imputed)
),
ranked AS (
    SELECT h.*,
           row_number() OVER (PARTITION BY h.date_key, h.model_key, h.split ORDER BY h.actual_mw   DESC, h.hr) AS rn_actual,
           row_number() OVER (PARTITION BY h.date_key, h.model_key, h.split ORDER BY h.forecast_mw DESC, h.hr) AS rn_forecast
    FROM hourly h
    JOIN good_days g USING (date_key, model_key, split)
)
SELECT date_key, model_key, split,
       max(actual_mw)                                  AS actual_peak_mw,
       max(forecast_mw)                                AS forecast_peak_mw,
       max(forecast_mw) - max(actual_mw)               AS peak_error_mw,      -- + = over-forecast
       abs(max(forecast_mw) - max(actual_mw))          AS abs_peak_error_mw,
       max(hr) FILTER (WHERE rn_actual = 1)            AS actual_peak_hour,
       max(hr) FILTER (WHERE rn_forecast = 1)          AS forecast_peak_hour,
       abs(max(hr) FILTER (WHERE rn_actual = 1) - max(hr) FILTER (WHERE rn_forecast = 1)) <= 1 AS peak_hour_hit
FROM ranked
GROUP BY date_key, model_key, split;

SELECT 'v_fact_forecast' AS view_name, count(*) AS row_count FROM mart.v_fact_forecast
UNION ALL SELECT 'v_fact_forecast_scenario', count(*) FROM mart.v_fact_forecast_scenario
UNION ALL SELECT 'v_daily_peak_forecast', count(*) FROM mart.v_daily_peak_forecast;
