-- 10_export_tableau.sql: writes flat CSV files for Tableau into the tableau/ folder.
-- Runs after 09_powerbi_views.sql (it reuses those views, so numbers match Power BI
-- and Python: imputed hours are excluded).
-- Run from the project root (run_pipeline.py does this) so the relative paths resolve.
-- \copy must stay on one line each.

-- 1) One row per (hour, model, split): the main Tableau data source.
\copy (SELECT f.ts, f.date_key, f.hour_of_day, h.hour_label, h.is_peak_period::int AS is_peak_period, m.model_name, f.split, f.actual_mw, f.forecast_mw, f.error_mw, f.abs_error_mw, f.under_forecast_mw, f.over_forecast_mw, f.temp_c, CASE WHEN f.temp_c < 0 THEN '1: below 0' WHEN f.temp_c < 10 THEN '2: 0 to 10' WHEN f.temp_c < 20 THEN '3: 10 to 20' WHEN f.temp_c < 30 THEN '4: 20 to 30' ELSE '5: 30 and above' END AS temp_band, d.year, d.month, d.month_name, d.day_name, d.season, d.is_weekend::int AS is_weekend, d.is_holiday::int AS is_holiday, d.holiday_name, CASE WHEN d.is_holiday THEN 'Holiday' WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type FROM mart.v_fact_forecast f JOIN mart.dim_model m ON m.model_key = f.model_key JOIN mart.dim_date d ON d.date_key = f.date_key JOIN mart.dim_hour h ON h.hour_of_day = f.hour_of_day ORDER BY f.ts, m.model_name, f.split) TO 'tableau/tableau_hourly.csv' WITH (FORMAT csv, HEADER true)

-- 2) One row per (day, model, split): actual vs forecast daily peak.
\copy (SELECT p.date_key, m.model_name, p.split, p.actual_peak_mw, p.forecast_peak_mw, p.peak_error_mw, p.abs_peak_error_mw, p.actual_peak_hour, p.forecast_peak_hour, p.peak_hour_hit::int AS peak_hour_hit, d.year, d.month, d.month_name, d.day_name, d.season, d.is_weekend::int AS is_weekend, d.is_holiday::int AS is_holiday FROM mart.v_daily_peak_forecast p JOIN mart.dim_model m ON m.model_key = p.model_key JOIN mart.dim_date d ON d.date_key = p.date_key ORDER BY p.date_key, m.model_name, p.split) TO 'tableau/tableau_daily_peak.csv' WITH (FORMAT csv, HEADER true)

-- 3) Temperature what-if, rolled up to one row per (day, temperature shift).
\copy (SELECT s.date_key, m.model_name, s.temp_offset_c, avg(s.forecast_mw) AS avg_forecast_mw, max(s.forecast_mw) AS peak_forecast_mw, count(*) AS hours FROM mart.v_fact_forecast_scenario s JOIN mart.dim_model m ON m.model_key = s.model_key GROUP BY s.date_key, m.model_name, s.temp_offset_c ORDER BY s.date_key, s.temp_offset_c) TO 'tableau/tableau_scenarios.csv' WITH (FORMAT csv, HEADER true)

SELECT 'tableau export finished: see tableau/tableau_hourly.csv, tableau_daily_peak.csv, tableau_scenarios.csv' AS message;
