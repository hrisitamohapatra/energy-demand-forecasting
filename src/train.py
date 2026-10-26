"""LightGBM training helpers, plus temperature what-if and sensitivity helpers."""
import itertools

import lightgbm as lgb
import numpy as np
import pandas as pd

from src.evaluate import hourly_metrics

# Every feature is known at forecast time: lags and rolling windows stop >= 24h back
# (see sql/05_features.sql). Temperature, humidity and wind are OBSERVED values standing in
# for a weather forecast, which flatters accuracy (state this in the README).
FEATURES = [
    "load_lag_24h", "load_lag_48h", "load_lag_168h",
    "load_roll_24h", "load_max_24h", "load_roll_7d", "load_std_7d",
    "hour_of_day", "day_of_week", "month", "day_of_year", "week_of_year",
    "is_weekend", "is_holiday",
    "temp_c", "humidity_pct", "wind_kmh", "hdd", "cdd",
]
HDD_CDD_BASE_C = 18.3

BASE_PARAMS = dict(learning_rate=0.05, subsample=0.8, subsample_freq=1,
                   colsample_bytree=0.8, random_state=42, verbose=-1, n_jobs=-1)

# Small grid, tuned on the validation year only.
GRID = dict(num_leaves=[31, 127], min_child_samples=[20, 100],
            objective=["regression", "regression_l1"])


def make_xy(df: pd.DataFrame):
    X = df[FEATURES].astype(float)
    return X, df["load_mw"].astype(float)


def fit_with_early_stopping(train, valid, params, max_estimators=5000, patience=100):
    Xt, yt = make_xy(train)
    Xv, yv = make_xy(valid)
    model = lgb.LGBMRegressor(n_estimators=max_estimators, **BASE_PARAMS, **params)
    model.fit(Xt, yt, eval_set=[(Xv, yv)], eval_metric="l1",
              callbacks=[lgb.early_stopping(patience, verbose=False)])
    return model


def fit_fixed(train, params, n_estimators):
    Xt, yt = make_xy(train)
    model = lgb.LGBMRegressor(n_estimators=n_estimators, **BASE_PARAMS, **params)
    model.fit(Xt, yt)
    return model


def tune(train, valid) -> pd.DataFrame:
    """Try every combination in GRID; rank by validation WAPE (imputed hours excluded)."""
    rows = []
    keys = list(GRID)
    real = valid[~valid["is_imputed"]]
    Xr, _ = make_xy(real)
    for combo in itertools.product(*GRID.values()):
        params = dict(zip(keys, combo))
        model = fit_with_early_stopping(train, valid, params)
        pred = model.predict(Xr)
        m = hourly_metrics(real["load_mw"], pred)
        rows.append({**params, "best_iteration": int(model.best_iteration_),
                     "valid_WAPE_%": m["WAPE_%"], "valid_RMSE_MW": m["RMSE_MW"]})
    return pd.DataFrame(rows).sort_values("valid_WAPE_%").reset_index(drop=True)


def shift_temperature(df: pd.DataFrame, offset_c: float = 0.0, noise_sd_c: float = 0.0,
                      seed: int = 0) -> pd.DataFrame:
    """Return a copy with temperature shifted (what-if) and/or noised (forecast-error test).
    hdd and cdd are recomputed. Lag features are NOT changed, so a scenario only moves the
    contemporaneous temperature inputs (a conservative what-if)."""
    d = df.copy()
    t = d["temp_c"].astype(float) + offset_c
    if noise_sd_c:
        t = t + np.random.default_rng(seed).normal(0, noise_sd_c, len(d))
    d["temp_c"] = t
    d["hdd"] = np.maximum(HDD_CDD_BASE_C - t, 0)
    d["cdd"] = np.maximum(t - HDD_CDD_BASE_C, 0)
    return d
