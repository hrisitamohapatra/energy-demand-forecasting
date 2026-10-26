# Assumptions and design decisions

## Forecast definition

- **24 hours ahead for every hour.** Each hour's forecast uses only information at least 24 hours
  old: lags of 24, 48 and 168 hours, and rolling windows that end 24 hours before the hour. This
  is checked in `sql/07_checks.sql` (leakage tests compare each lag with the actual earlier load).
- A forecast issued once at midnight for the whole next day could not use the same hour of
  yesterday for late-evening hours. It would be somewhat less accurate than the numbers reported.

## Weather

- **Observed temperature stands in for a weather forecast.** A real system would use forecast
  temperature, so real-world accuracy would be lower. Random-noise test on the test set:

  | Noise (standard deviation) | WAPE | Peak hour within 1 h |
  | --- | --- | --- |
  | 0 °C | 3.19% | 76.1% |
  | 1 °C | 3.52% | 68.7% |
  | 2 °C | 4.31% | 60.7% |
  | 3 °C | 5.27% | 54.3% |

- **One weather station** (Philadelphia, 39.95 N, -75.17 W) represents the whole region.
- Heating and cooling degrees use a base of 18.3 °C (65 °F).

## Data cleaning

- Timestamps are local wall-clock time in both sources, so no time-zone conversion is done.
- The fall-back hour appears twice in the load file (4 cases); the two readings are averaged.
- Missing hours (30) are linearly interpolated and flagged `is_imputed`, so every day has exactly
  24 rows and a 24-row lag always means the same clock hour yesterday.
- Outliers are flagged (a spike or dip more than 25% from both neighbours in the same direction),
  never deleted. The range check allows 10,000 to 70,000 MW.
- **Imputed hours, and days containing them, are excluded from every metric** in Python, Power BI
  and Tableau.
- 2002 and 2018 are partial years (the data starts on 1 Jan 2002 and ends on 3 Aug 2018).

## Splits and model selection

| Split | Period |
| --- | --- |
| Train | up to 31 Dec 2015 |
| Validation | 2016 |
| Test | 1 Jan 2017 to 3 Aug 2018 (13,895 hours, 578 complete days) |

- Splits are time-ordered, never random. Every choice (LightGBM settings, Prophet trend type) was
  made on validation only; the test set was scored afterwards.
- LightGBM: 8-setting grid on validation with early stopping; validation scores come from a model
  trained on train only, test scores from a model refit on train plus validation.
- Prophet fits on 2011 to 2015 only, to keep the run time down. A flat trend beat a linear trend on
  validation and was chosen. The linear version under-forecast by 3,297 MW on the test set.
- SARIMA(1,0,1)(1,1,1,7) forecasts the daily peak one day ahead; it has no hourly output.
- The expanding-window backtest uses six folds of about one year each (test windows from 4 Aug
  2012 to 3 Aug 2018), with training always ending where the fold begins.

## Baselines

- **Seasonal naive** (the plan's baseline): the load at the same hour one week earlier.
- **Same hour yesterday**: a stronger benchmark, reported alongside. Load correlates 0.89 with the
  load 24 hours earlier and 0.78 with the load 168 hours earlier.

## Cost of forecast error

- Prices are illustrative assumptions, not market data: **$150 per MWh** for under-forecast
  (emergency purchase) and **$40 per MWh** for over-forecast (wasted procurement).
- Each hourly row represents one hour, so a shortfall of X MW is X MWh.
- Costs are summed over the whole test period for the whole region, so the totals are large. Use
  them to compare models, not as a budget.

## Temperature what-if

- LightGBM is scored with temperature (and heating and cooling degrees) shifted by -5 to +5 °C.
  **Lag features are not changed**, so the scenario is conservative: it moves only the
  contemporaneous temperature inputs.
- Averaged over the whole year, +5 °C adds about 1,340 MW (+4.3%) and -5 °C removes about 480 MW.
  The yearly average mixes seasons, because warmth lowers winter heating demand and raises summer
  cooling demand.

## Dimension choices

- `is_peak_period` in `dim_hour` is an assumption: 15:00 to 20:59.
- Seasons are meteorological: Winter = Dec to Feb, Spring = Mar to May, Summer = Jun to Aug,
  Fall = Sep to Nov.

## Dashboards

- Power BI and Tableau read the same forecasts. Daily-peak figures can differ in the last digits
  between the notebooks (for example 1,126 MW) and the dashboards (1,124 MW) because the views
  keep only complete 24-hour days with no imputed hours.
- The Tableau CSV export is `sql/10_export_tableau.sql` rather than `08`, because it reads views
  created by `09_powerbi_views.sql`.
- SARIMA is not on the hourly dashboards because it forecasts only the daily peak.
