-- 05_features.sql: model features, built so a day-ahead forecast never sees the future.
--
-- LEAKAGE RULE: every load-based feature uses only rows at least 24 hours before ts.
-- (clean.load_hourly is a regular hourly grid, so ROWS frames = hours.)
-- Known weakness: temp_c / humidity / wind are OBSERVED values standing in for a
-- weather forecast, which makes accuracy look better than a real day-ahead system.

DROP TABLE IF EXISTS mart.features_hourly;
CREATE TABLE mart.features_hourly AS
WITH base AS (
    SELECT c.ts, c.load_mw, c.is_imputed, c.is_outlier,
           c.temp_c, c.humidity_pct, c.wind_kmh,
           LAG(c.load_mw, 24)  OVER w AS load_lag_24h,
           LAG(c.load_mw, 48)  OVER w AS load_lag_48h,
           LAG(c.load_mw, 168) OVER w AS load_lag_168h,
           AVG(c.load_mw) OVER (w ROWS BETWEEN 47 PRECEDING AND 24 PRECEDING)  AS load_roll_24h,
           MAX(c.load_mw) OVER (w ROWS BETWEEN 47 PRECEDING AND 24 PRECEDING)  AS load_max_24h,
           AVG(c.load_mw) OVER (w ROWS BETWEEN 191 PRECEDING AND 24 PRECEDING) AS load_roll_7d,
           STDDEV_SAMP(c.load_mw) OVER (w ROWS BETWEEN 191 PRECEDING AND 24 PRECEDING) AS load_std_7d,
           COUNT(c.load_mw) OVER (w ROWS BETWEEN 191 PRECEDING AND 24 PRECEDING) AS n_window
    FROM clean.load_hourly c
    WINDOW w AS (ORDER BY c.ts)
)
SELECT b.ts,
       b.load_mw,                                   -- target
       b.is_imputed,
       b.is_outlier,
       b.load_lag_24h,
       b.load_lag_48h,
       b.load_lag_168h,
       b.load_roll_24h::numeric(12,2) AS load_roll_24h,
       b.load_max_24h,
       b.load_roll_7d::numeric(12,2)  AS load_roll_7d,
       b.load_std_7d::numeric(12,2)   AS load_std_7d,
       EXTRACT(HOUR   FROM b.ts)::int AS hour_of_day,
       EXTRACT(ISODOW FROM b.ts)::int AS day_of_week,   -- 1 = Monday
       EXTRACT(MONTH  FROM b.ts)::int AS month,
       EXTRACT(DOY    FROM b.ts)::int AS day_of_year,
       EXTRACT(WEEK   FROM b.ts)::int AS week_of_year,
       (EXTRACT(ISODOW FROM b.ts) >= 6) AS is_weekend,
       (h.holiday_date IS NOT NULL)     AS is_holiday,
       b.temp_c, b.humidity_pct, b.wind_kmh,
       GREATEST(18.3 - b.temp_c, 0)::numeric(6,2) AS hdd,   -- heating degree (base 18.3 C = 65 F)
       GREATEST(b.temp_c - 18.3, 0)::numeric(6,2) AS cdd    -- cooling degree
FROM base b
LEFT JOIN staging.holidays h ON h.holiday_date = b.ts::date
WHERE b.n_window = 168;          -- drop the first 8 days, which lack a full window

ALTER TABLE mart.features_hourly ADD PRIMARY KEY (ts);

SELECT count(*) AS feature_rows, min(ts) AS first_ts, max(ts) AS last_ts
FROM mart.features_hourly;
