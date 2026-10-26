"""Write model predictions to the mart so Power BI and Tableau read the same numbers."""
import pandas as pd
from sqlalchemy import text

from src.db import get_engine


def _model_key(conn, model_name: str) -> int:
    key = conn.execute(text("SELECT model_key FROM mart.dim_model WHERE model_name = :m"),
                       {"m": model_name}).scalar()
    if key is None:
        raise ValueError(f"Unknown model_name {model_name!r}; add it to mart.dim_model first.")
    return key


def write_forecasts(df: pd.DataFrame, model_name: str, engine=None) -> int:
    """df needs columns: ts, forecast_mw, load_mw (the actual) and split.
    Replaces this model's stored rows for the splits present in df. Returns rows written."""
    engine = engine or get_engine()
    out = pd.DataFrame({
        "ts": df["ts"],
        "split": df["split"],
        "forecast_mw": df["forecast_mw"].astype(float).round(2),
        "actual_mw": df["load_mw"].astype(float).round(2),
    })
    out = out[out["split"].isin(["train", "validation", "test", "backtest"])]
    splits = sorted(out["split"].unique())
    with engine.begin() as conn:
        key = _model_key(conn, model_name)
        conn.execute(text("DELETE FROM mart.fact_forecast WHERE model_key = :k AND split = ANY(:s)"),
                     {"k": key, "s": splits})
        out.insert(1, "model_key", key)
        out.to_sql("fact_forecast", conn, schema="mart", if_exists="append", index=False,
                   method="multi", chunksize=5000)
    return len(out)


def write_scenarios(df: pd.DataFrame, model_name: str, engine=None) -> int:
    """df needs columns: ts, temp_offset_c, forecast_mw. Replaces this model's scenario rows."""
    engine = engine or get_engine()
    out = pd.DataFrame({
        "ts": df["ts"],
        "temp_offset_c": df["temp_offset_c"].astype(float),
        "forecast_mw": df["forecast_mw"].astype(float).round(2),
    })
    with engine.begin() as conn:
        key = _model_key(conn, model_name)
        conn.execute(text("DELETE FROM mart.fact_forecast_scenario WHERE model_key = :k"), {"k": key})
        out.insert(1, "model_key", key)
        out.to_sql("fact_forecast_scenario", conn, schema="mart", if_exists="append", index=False,
                   method="multi", chunksize=5000)
    return len(out)
