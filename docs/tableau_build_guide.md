# Tableau build guide (Week 6)

Goal: one dashboard that a stranger can read in 30 seconds, built from the three CSV files the
pipeline writes. Tableau Public (free) is enough. Budget about 1 to 1.5 hours.

## 0. Make the CSV files

From the project root, with the virtual environment on and PGPASSWORD set:

```
python run_pipeline.py --only 10
```

This writes three files into the `tableau` folder. It needs the forecasts to be in the database
already (the Week 3 and 4 notebooks write them) and the views from step 09.

| File | One row per | Use |
|---|---|---|
| tableau_hourly.csv | hour x model x split | accuracy by hour, season, temperature, day type |
| tableau_daily_peak.csv | day x model x split | daily peak error and peak-hour hits |
| tableau_scenarios.csv | day x temperature shift | what-if chart |

Check the row counts match Power BI (test split, LightGBM: WAPE about 3.19%).

## 1. Connect

1. Open Tableau Public, then **Text file**, and pick `tableau_hourly.csv`.
2. For each extra file use **Data > New Data Source > Text file**. Do not join the three files;
   keep them as three separate data sources.
3. In the hourly source, check types: `ts` is Date & Time, `date_key` is Date, `year` and `month`
   are numbers (set them to Dimensions), and `split`, `model_name`, `season` are strings.

## 2. Calculated fields

Create these in the hourly source:

```
WAPE        = SUM([abs_error_mw]) / SUM([actual_mw])
Bias MW     = AVG([error_mw])
MAE MW      = AVG([abs_error_mw])
```

In the daily-peak source:

```
Peak MAE MW      = AVG([abs_peak_error_mw])
Peak hit rate    = AVG([peak_hour_hit])
```

Format WAPE and Peak hit rate as percentages with 2 decimals.

## 3. Sheets

Put a `split = test` filter on every sheet (right-click > Add to Context so it applies first),
and show it as a single-value dropdown on the dashboard.

1. **WAPE by model:** Rows `model_name`, Columns `WAPE`, sorted ascending. Label the bars.
2. **WAPE by hour:** Columns `hour_of_day` (discrete), Rows `WAPE`, Color `model_name`.
3. **Season x hour heat map:** Columns `hour_of_day`, Rows `season`, Color `WAPE`, with the
   Model filter set to one model (LightGBM by default).
4. **Error by temperature band:** Columns `temp_band`, Rows `Bias MW` and `WAPE`.
5. **Day type:** Columns `day_type`, Rows `WAPE`. This shows holidays are the hardest days.
6. **Actual vs forecast:** Columns `date_key` (day), Rows `AVG(actual_mw)` and
   `AVG(forecast_mw)`, dual line.
7. **Peak error:** daily-peak source, Columns `model_name`, Rows `Peak MAE MW`, plus a second
   sheet with `Peak hit rate` by `season`.
8. **What-if:** scenarios source, Columns `temp_offset_c`, Rows `AVG(avg_forecast_mw)`.

## 4. Dashboard

Size: Fixed, 1400 x 900 px.

- Top row: title, then four big numbers (WAPE, MAE, Bias, Peak hit rate) for the chosen model.
- Left column: Split and Model filters (apply to all sheets using this data source).
- Middle: actual vs forecast line (sheet 6), then WAPE by model (1) and WAPE by hour (2).
- Bottom: heat map (3), temperature band (4), day type (5).
- Footer text: "Observed temperature stands in for a weather forecast. Forecasts are 24 hours
  ahead for every hour. Test period: 1 Jan 2017 to 3 Aug 2018."

Keep one colour for LightGBM (the model you picked) and grey for the others, so the eye goes to
the winner.

## 5. Finish

1. Add a second dashboard tab only if you have time: peak error (7) and the what-if (8).
2. **File > Save to Your Computer** to create the `.twbx` and keep it in `tableau/`.
3. Take a screenshot of the dashboard into `tableau/screenshots/`.
4. Keep the three CSV files out of git if they are large (check `git status`); the README says
   how to regenerate them.
