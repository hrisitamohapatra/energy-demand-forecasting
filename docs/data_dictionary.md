# Data dictionary

All timestamps are local wall-clock time (America/New_York) in both sources. Load is in megawatts
(MW), temperature in degrees Celsius, wind in km/h.

## Sources

| Source | What | Rows | Notes |
| --- | --- | --- | --- |
| `data/PJME_hourly.csv` | PJM East hourly load (Kaggle, "Hourly Energy Consumption") | 145,366 | 2002-01-01 01:00 to 2018-08-03 00:00; 4 duplicated timestamps, 30 missing hours |
| `data/weather_philly.csv` | Hourly temperature, humidity, wind for Philadelphia (39.95, -75.17) from the Open-Meteo archive API | 149,016 | one row per hour, 2002 to 2018 |
| `staging.holidays` | US federal holidays from the Python `holidays` package | one row per holiday date | loaded by `src/load_holidays.py` (step 03b) |

## Layers and tables

| Schema | Table | Grain | Purpose |
| --- | --- | --- | --- |
| raw | `pjme_hourly`, `weather_hourly` | one row per source row | untouched text copy of the CSV files |
| staging | `load_hourly`, `weather_hourly` | one row per source row | typed columns; duplicates kept; `source_file` tag |
| staging | `holidays` | one row per holiday date | holiday date and name |
| clean | `weather_hourly` | one row per hour | weather averaged per timestamp |
| clean | `load_hourly` | one row per hour | gap-free 24-row-per-day grid with weather attached |
| mart | `features_hourly` | one row per hour | model features (lags, rolling windows, calendar, weather) |
| mart | `dim_date`, `dim_hour`, `dim_model` | one row per day, hour, model | dimensions |
| mart | `fact_load_hourly` | one row per hour | actual load, weather, flags |
| mart | `fact_forecast` | one row per hour, model, split | forecasts written by Python |
| mart | `fact_forecast_scenario` | one row per hour, model, temperature offset | temperature what-if forecasts |
| mart | `v_fact_forecast`, `v_fact_forecast_scenario`, `v_daily_peak_forecast` | views | feed Power BI and the Tableau export |

## `clean.load_hourly` and `mart.fact_load_hourly`

| Column | Meaning |
| --- | --- |
| `ts` | hour (primary key) |
| `date_key`, `hour_of_day` | date and hour 0 to 23 (in `fact_load_hourly`) |
| `load_mw` | hourly load; duplicated hours averaged, missing hours linearly interpolated |
| `is_imputed` | true if the hour was missing in the source and filled by interpolation |
| `source_row_count` | source rows behind the hour (2 for a duplicated daylight-saving hour, 0 if imputed) |
| `is_outlier` | true if the load is non-positive or a spike or dip more than 25% away from both neighbours in the same direction (flagged, never deleted) |
| `temp_c`, `humidity_pct`, `wind_kmh` | observed weather at the hour (Philadelphia) |

## `mart.features_hourly`

First 8 days are dropped because they lack a full 7-day window. Every load-based feature uses only
rows at least 24 hours before `ts`, so there is no leakage.

| Column | Meaning |
| --- | --- |
| `load_mw` | target |
| `load_lag_24h`, `load_lag_48h`, `load_lag_168h` | load 1, 2 and 7 days earlier at the same hour |
| `load_roll_24h`, `load_max_24h` | mean and maximum of the 24 hours ending 24 hours before `ts` |
| `load_roll_7d`, `load_std_7d` | mean and standard deviation of the 7 days ending 24 hours before `ts` |
| `hour_of_day`, `day_of_week` (1 = Monday), `month`, `day_of_year`, `week_of_year` | calendar |
| `is_weekend`, `is_holiday` | calendar flags |
| `temp_c`, `humidity_pct`, `wind_kmh` | observed weather (stands in for a forecast) |
| `hdd`, `cdd` | heating and cooling degrees: max(18.3 - temp, 0) and max(temp - 18.3, 0) |
| `is_imputed`, `is_outlier` | quality flags, used to exclude hours from metrics |

## Dimensions

**`dim_date`**: `date_key`, `year`, `quarter`, `month`, `month_name`, `day_of_month`,
`day_of_week` (1 = Monday), `day_name`, `is_weekend`, `season` (Winter = Dec to Feb, Spring = Mar to
May, Summer = Jun to Aug, Fall = Sep to Nov), `is_holiday`, `holiday_name`.

**`dim_hour`**: `hour_of_day`, `hour_label` (for example `17:00`), `is_peak_period` (assumed
15:00 to 20:59).

**`dim_model`**: `model_key`, `model_name` (`seasonal_naive`, `prophet`, `sarima`, `lightgbm`),
`model_family`, `description`.

## Forecast tables

**`mart.fact_forecast`**: `ts`, `model_key`, `split` (`train`, `validation`, `test`, `backtest`),
`forecast_mw`, `actual_mw`. SARIMA is not stored here because it forecasts only the daily peak;
its results are in `docs/results/daily_peak_comparison.csv`.

**`mart.fact_forecast_scenario`**: `ts`, `model_key`, `temp_offset_c` (-5 to +5), `forecast_mw`.
LightGBM scored with temperature (and heating and cooling degrees) shifted by the offset; lag
features are not changed.

## Views (used by Power BI and Tableau)

`v_fact_forecast` adds `date_key`, `hour_of_day`, `error_mw` (forecast minus actual; positive means
over-forecast), `abs_error_mw`, `under_forecast_mw` (MW short), `over_forecast_mw` (MW surplus) and
`temp_c`. Imputed hours are excluded. `v_daily_peak_forecast` has one row per complete day with
no imputed hours: `actual_peak_mw`, `forecast_peak_mw`, `peak_error_mw`, `abs_peak_error_mw`,
`actual_peak_hour`, `forecast_peak_hour`, `peak_hour_hit` (true if the hours are within 1 hour).

## Tableau CSV files (`tableau/`)

| File | One row per | Extra columns |
| --- | --- | --- |
| `tableau_hourly.csv` | hour, model, split | `hour_label`, `is_peak_period`, `temp_band` (below 0, 0 to 10, 10 to 20, 20 to 30, 30 and above), `season`, `day_type` (Weekday, Weekend, Holiday), `holiday_name`; flags as 1 or 0 |
| `tableau_daily_peak.csv` | day, model, split | calendar columns; `peak_hour_hit` as 1 or 0 |
| `tableau_scenarios.csv` | day, temperature offset | `avg_forecast_mw`, `peak_forecast_mw`, `hours` |

The Python notebooks use six temperature bands (below 0, 0 to 10, 10 to 20, 20 to 25, 25 to 30 and
above 30 °C), so the notebook and Tableau breakdowns are not directly comparable.

## Metrics

| Metric | Definition |
| --- | --- |
| WAPE | sum of absolute errors divided by sum of actual load |
| MAPE | mean of absolute error divided by actual load, per hour |
| MAE, RMSE | mean absolute error and root mean squared error, in MW |
| Bias | mean of forecast minus actual; positive means over-forecast |
| Peak MAE, peak bias | error on the daily maximum load, per complete day |
| Peak hour within 1 h | share of days where the forecast peak hour is within one hour of the actual peak hour |
| Under-forecast cost | MWh short multiplied by the assumed under price ($150 per MWh) |
| Over-forecast cost | MWh of surplus multiplied by the assumed over price ($40 per MWh) |
