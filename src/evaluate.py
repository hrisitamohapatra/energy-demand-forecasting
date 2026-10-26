"""Forecast accuracy metrics: hourly accuracy, daily-peak accuracy, error by group.

Rows whose actual load was imputed (is_imputed) are excluded, and days that contain
an imputed hour are excluded from the peak metrics, so models are judged on real data.
"""
import numpy as np
import pandas as pd

from src.config import EVAL_SPLITS


def hourly_metrics(actual, pred) -> dict:
    a = np.asarray(actual, dtype=float)
    p = np.asarray(pred, dtype=float)
    err = p - a
    return {
        "MAPE_%": float(np.mean(np.abs(err) / a) * 100),
        "WAPE_%": float(np.abs(err).sum() / a.sum() * 100),
        "RMSE_MW": float(np.sqrt(np.mean(err ** 2))),
        "MAE_MW": float(np.abs(err).mean()),
        "bias_MW": float(err.mean()),
        "n_hours": int(len(a)),
    }


def peak_metrics(df: pd.DataFrame, actual: str = "load_mw", pred: str = "forecast_mw") -> dict:
    """Daily peak error (MW) and how often the predicted peak hour is within 1 hour of the real one."""
    d = df[["ts", actual, pred]].reset_index(drop=True)
    d["date"] = d["ts"].dt.date
    d["hour"] = d["ts"].dt.hour
    g = d.groupby("date")
    act_peak, pred_peak = g[actual].max(), g[pred].max()
    act_hour = d.loc[g[actual].idxmax(), ["date", "hour"]].set_index("date")["hour"]
    pred_hour = d.loc[g[pred].idxmax(), ["date", "hour"]].set_index("date")["hour"]
    err = pred_peak - act_peak
    return {
        "peak_MAE_MW": float(err.abs().mean()),
        "peak_bias_MW": float(err.mean()),
        "peak_MAPE_%": float((err.abs() / act_peak).mean() * 100),
        "peak_hour_within_1h_%": float(((act_hour - pred_hour).abs() <= 1).mean() * 100),
        "n_days": int(len(act_peak)),
    }


def score(df: pd.DataFrame, pred_col: str) -> dict:
    """Hourly + peak metrics for one set of predictions (imputed hours/days excluded)."""
    real = df[~df["is_imputed"]]
    bad_days = set(df.loc[df["is_imputed"], "ts"].dt.date)
    peak_df = df[~df["ts"].dt.date.isin(bad_days)]
    return {**hourly_metrics(real["load_mw"], real[pred_col]),
            **peak_metrics(peak_df, "load_mw", pred_col)}


def summarize(df: pd.DataFrame, pred_col: str, name: str, splits=EVAL_SPLITS) -> pd.DataFrame:
    """One row per split with hourly and peak metrics for a model's predictions."""
    rows = []
    for s in splits:
        rows.append({"model": name, "split": s, **score(df[df["split"] == s], pred_col)})
    return pd.DataFrame(rows)


def error_by(df: pd.DataFrame, group_col: str, pred_col: str = "forecast_mw") -> pd.DataFrame:
    """WAPE, MAE and bias per group (hour of day, season, temperature band, ...)."""
    sub = df[~df["is_imputed"]]
    err = sub[pred_col] - sub["load_mw"]
    tmp = pd.DataFrame({group_col: sub[group_col], "abs_err": err.abs(), "err": err,
                        "actual": sub["load_mw"]})
    out = tmp.groupby(group_col, observed=True).agg(
        abs_err_sum=("abs_err", "sum"), actual_sum=("actual", "sum"),
        MAE_MW=("abs_err", "mean"), bias_MW=("err", "mean"), n_hours=("err", "size"))
    out["WAPE_%"] = out["abs_err_sum"] / out["actual_sum"] * 100
    return out[["WAPE_%", "MAE_MW", "bias_MW", "n_hours"]]
