"""Load model features from the mart layer and add split / grouping columns."""
import numpy as np
import pandas as pd

from src.config import TRAIN_END, VALID_END
from src.db import get_engine

TEMP_BINS = [-50, 0, 10, 20, 25, 30, 60]
TEMP_LABELS = ["<0C", "0-10C", "10-20C", "20-25C", "25-30C", ">30C"]
SEASONS = {12: "Winter", 1: "Winter", 2: "Winter", 3: "Spring", 4: "Spring", 5: "Spring",
           6: "Summer", 7: "Summer", 8: "Summer", 9: "Fall", 10: "Fall", 11: "Fall"}


def load_features(engine=None) -> pd.DataFrame:
    """Read mart.features_hourly (one row per hour, no leakage by construction)."""
    engine = engine or get_engine()
    df = pd.read_sql("SELECT * FROM mart.features_hourly ORDER BY ts", engine, parse_dates=["ts"])
    for col in df.columns:  # NUMERIC columns can arrive as Decimal objects
        if df[col].dtype == object:
            df[col] = pd.to_numeric(df[col])
    return df


def add_groups(df: pd.DataFrame) -> pd.DataFrame:
    """Add date, season, temperature band and day type columns used for slicing errors."""
    df = df.copy()
    df["date"] = df["ts"].dt.normalize()
    df["year"] = df["ts"].dt.year
    df["season"] = df["month"].map(SEASONS)
    df["temp_band"] = pd.cut(df["temp_c"], bins=TEMP_BINS, labels=TEMP_LABELS)
    df["day_type"] = np.select(
        [df["is_holiday"], df["is_weekend"]], ["holiday", "weekend"], default="weekday"
    )
    return df


def assign_split(df: pd.DataFrame) -> pd.DataFrame:
    """Label each row train / validation / test by date (time-ordered, never random)."""
    df = df.copy()
    d = df["ts"].dt.normalize()
    df["split"] = np.select(
        [d <= pd.Timestamp(TRAIN_END), d <= pd.Timestamp(VALID_END)],
        ["train", "validation"],
        default="test",
    )
    return df
