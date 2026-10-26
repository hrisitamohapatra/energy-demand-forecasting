# Power BI build guide (week 5)

Goal: a four-page report plus an About page, built in **Power BI Desktop** (Windows) on the PostgreSQL star schema, saved as `powerbi/energy_report.pbix`.
Everything you need is in this repo: `sql/09_powerbi_views.sql` (views), `powerbi/measures.dax` (all DAX), `powerbi/energy_theme.json` (colours).

Before you start: run the whole pipeline (`python run_pipeline.py`) and notebooks 02, 03, 04 so `mart.fact_forecast` and `mart.fact_forecast_scenario` are filled. Re-running the pipeline rebuilds `mart` from scratch and empties the forecast tables, so rerun those notebooks afterwards.

**Suggested schedule:** Mon connect + model + measures · Tue pages 1-2 · Wed page 3 · Thu page 4 + About · Fri polish, tie-out checks, screenshots.

---

## 1 · Connect

1. Home > Get data > **PostgreSQL database**. Server `localhost`, database `energy_forecast`, mode **Import**.
2. Credentials > Database tab: user `postgres` and your password.
3. If it complains about encryption, untick *Encrypt connections* (a local server has no SSL). If it asks for a driver, install Npgsql.
4. In the Navigator, tick these and click **Transform Data**:

| Import | Rename to (in Power Query) |
| --- | --- |
| mart.dim_date | `dim_date` |
| mart.dim_hour | `dim_hour` |
| mart.dim_model | `dim_model` |
| mart.fact_load_hourly | `fact_load_hourly` |
| mart.v_fact_forecast | `fact_forecast` |
| mart.v_fact_forecast_scenario | `fact_forecast_scenario` |
| mart.v_daily_peak_forecast | `fact_daily_peak` |

5. Check types: `ts` = Date/Time, every `date_key` = Date, `temp_offset_c` = Decimal number. Close & Apply.

Expected row counts (Table view): dim_date 6,059 · dim_hour 24 · dim_model 4 · fact_load_hourly 145,392 · fact_forecast about 68,000 · fact_forecast_scenario 152,867.

## 2 · Build the model

**Helper tables** (Modeling > New table): paste `dim_split`, `Temp Offset`, `Under Price`, `Over Price` from section 0 of `measures.dax`.

**Relationships** (Model view). All many-to-one, single direction, from the many side to the one side:

| Many side | One side |
| --- | --- |
| fact_load_hourly[date_key] | dim_date[date_key] |
| fact_load_hourly[hour_of_day] | dim_hour[hour_of_day] |
| fact_forecast[date_key] | dim_date[date_key] |
| fact_forecast[hour_of_day] | dim_hour[hour_of_day] |
| fact_forecast[model_key] | dim_model[model_key] |
| fact_forecast[split] | dim_split[split] |
| fact_forecast_scenario[date_key] | dim_date[date_key] |
| fact_forecast_scenario[hour_of_day] | dim_hour[hour_of_day] |
| fact_forecast_scenario[model_key] | dim_model[model_key] |
| fact_daily_peak[date_key] | dim_date[date_key] |
| fact_daily_peak[model_key] | dim_model[model_key] |
| fact_daily_peak[split] | dim_split[split] |

Leave `Temp Offset`, `Under Price` and `Over Price` unrelated (they are selectors).

**Settings:**
- dim_date: right-click > **Mark as date table**, date column `date_key`. Sort `month_name` by `month`, `day_name` by `day_of_week`. Create a hierarchy year > quarter > month.
- dim_hour: sort `hour_label` by `hour_of_day`.
- Hide key and helper columns on the fact tables (`model_key`, `date_key`, `hour_of_day`) so report authors use the dimension columns.

**Measures:** create an empty table `_Measures` (Home > Enter data), then paste each measure from sections 1-5 of `measures.dax` into it. Format as you go: WAPE, MAPE, Peak Hour Hit Rate, Load YoY %, Scenario Change % as percentages; MW measures as whole numbers with a thousands separator; cost measures as currency with no decimals.

**Theme:** View > Themes > Browse for themes > `powerbi/energy_theme.json`.

## 3 · Tie-out check before you build pages

Drop each measure on a card or table with `dim_split[split]` = test and compare with the Python results (`docs/results/model_comparison.csv`). If these match, the model is wired correctly:

| Measure (test split) | seasonal_naive | prophet | lightgbm |
| --- | --- | --- | --- |
| WAPE | 11.30% | 6.05% | 3.19% |
| Peak Error MAE MW | about 4,389 | about 2,050 | about 1,126 |
| Peak Hour Hit Rate | about 64.5% | about 56.6% | about 76.1% |

WAPE should match exactly. The two peak measures can differ by a hair because the view drops the partial last day (2018-08-03), which Python counted. Unfiltered, **Peak Load MW** should be 62,009 and **Peak Date** 2006-08-02.

---

## 4 · Pages

Use one slicer-panel style on every page (same position, font and colours). Set the **split** slicer (`dim_split[split]`) to single-select with *test* selected on pages 2 and 4. Exclude `sarima` from every model slicer (it has no hourly forecasts): visual filter `model_name` is not `sarima`.

### Page 1 · Overview: how does demand behave?

| Visual | Fields |
| --- | --- |
| Slicers | dim_date[year] (dropdown), dim_date[season] (tiles) |
| Cards | Average Load MW · Peak Load MW · Peak Date · Best Model WAPE (visual filter split = test) |
| Line chart | x = dim_date[date_key], y = Average Load MW (turn the trend line on in Analytics) |
| Column chart | x = dim_date[year], y = Load YoY % |
| Column chart | x = dim_date[year], y = Peak Load MW |

Note 2002 and 2018 are partial years; mention it in a text box.

### Page 2 · Forecast vs actual: how good is each model?

| Visual | Fields |
| --- | --- |
| Slicers | dim_split[split] (test), dim_model[model_name] (**single select**), dim_date[date_key] (Between, set to one week) |
| Line chart | x = fact_forecast[ts] (continuous), y = Actual MW and Forecast MW. Actual black and thick |
| Matrix | rows = dim_hour[hour_label], columns = dim_model[model_name], values = WAPE, with a background colour scale |
| Bar chart | y = dim_model[model_name], x = WAPE |
| Table | model_name, WAPE, MAE MW, RMSE MW, Bias MW, Peak Error MAE MW, Peak Hour Hit Rate, WAPE Improvement vs Baseline % |

Format > Edit interactions: make the single-select model slicer and the date slicer **not** filter the matrix, bar chart and table, so they always compare all models. For the date slicer default, pick the week around the biggest test-period peak: `SELECT ts, actual_mw FROM mart.fact_forecast WHERE split='test' ORDER BY actual_mw DESC LIMIT 1;`.

Pin consistent colours: seasonal_naive grey, prophet orange, lightgbm blue.

### Page 3 · Peak-load analysis: when and why do peaks happen?

| Visual | Fields |
| --- | --- |
| Slicers | dim_date[year], dim_date[season] |
| Matrix (heatmap) | rows = dim_hour[hour_label], columns = dim_date[month_name], values = Peak Load MW, colour scale |
| Scatter | Details = dim_date[date_key] (**not** the date hierarchy), x = Daily Max Temp C, y = Peak Load MW, legend = dim_date[season] |
| Table | dim_date[date_key], Peak Load MW, Peak Hour, Daily Max Temp C, with a **Top N = 10 by Peak Load MW** visual filter |
| Column chart | x = dim_hour[hour_label], y = Peak Hour Hit Rate (visual filter model = lightgbm, split = test) |

**Drill-through page "Day detail":** add a new page, drag `dim_date[date_key]` into *Drill through*. Put a line chart of Average Load MW by hour (fact_load_hourly) and a card with Peak Load MW and Peak Hour. Right-click a day in the top-10 table > Drill through to open it.

### Page 4 · Cost and scenarios: what does error cost?

| Visual | Fields |
| --- | --- |
| Price slicers | 'Under Price'[Value] and 'Over Price'[Value], dropdown, single select (defaults 150 and 40) |
| Cards | Total Error Cost · Under-forecast Cost · Over-forecast Cost · Cost Saving vs Baseline |
| Stacked bar | y = dim_model[model_name], x = Under-forecast Cost and Over-forecast Cost |
| Scenario slicer | 'Temp Offset'[Value], single select |
| Line chart | x = dim_hour[hour_label], y = Scenario Avg Forecast MW and Scenario Baseline Avg MW (visual filter model = lightgbm) |
| Cards | Scenario Change MWh · Scenario Change % · Scenario Exposure Cost |
| Slicer | dim_date[season], so the scenario can be viewed by season |

Add a text box: *"Prices are illustrative assumptions, not market prices. Scenario forecasts move only the temperature inputs; the model's lag features still contain the real past weather, so the effect shown is conservative."*

The what-if offsets come from `mart.fact_forecast_scenario` (written by notebook 04). A DAX parameter cannot re-run the model; it only selects a pre-scored offset.

### About this report (last page)

A text-only page: data sources (PJM East hourly load from Kaggle, Open-Meteo weather for Philadelphia, US federal holidays), the split (train to 2015, validation 2016, test 2017 to 2018-08-03), imputed hours excluded from accuracy, forecast definition (each hour forecast 24 hours ahead), observed temperature standing in for a weather forecast, cost prices as assumptions, and the refresh date.

---

## 5 · Polish checklist

- [ ] Theme applied; one font; page titles consistent
- [ ] Same slicer panel style and position on every page
- [ ] Tooltips on the main charts (a report-page tooltip with date, hour, actual, forecast and error works well)
- [ ] Bookmarks: **Peak day** (page 2, date slicer on the peak week, lightgbm selected) and **Best model** (page 2 table sorted by WAPE)
- [ ] Navigation buttons between pages
- [ ] Axis titles and units (MW, %, $)
- [ ] Alt text on the visuals
- [ ] Save as `powerbi/energy_report.pbix`
- [ ] Screenshots of each page into `powerbi/screenshots/` (README needs three or four)

## 6 · Troubleshooting

| Problem | Fix |
| --- | --- |
| Blank WAPE or cost visuals | Check the split slicer has a selection and that `dim_split` relates to `fact_forecast[split]` |
| Matrix shows 0 or odd values for hours | Make sure the relationship uses `hour_of_day`, not `ts` |
| `Load YoY %` is blank | dim_date is not marked as a date table |
| Scenario cards are blank | Notebook 04 hasn't been run since the last pipeline rebuild |
| Scatter shows only years or months | Switch `date_key` from *Date Hierarchy* to plain `date_key` in the Details well |
| Numbers differ from Python | Confirm the views were imported (not the raw tables) and the split slicer is on *test* |
