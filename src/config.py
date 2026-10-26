"""Project-wide settings. Split dates can be overridden with environment variables
(useful for testing on a smaller dataset)."""
import os

# Time-ordered split: train on the early years, tune on one validation year,
# test on the most recent period. Never use a random split.
TRAIN_END = os.environ.get("ENERGY_TRAIN_END", "2015-12-31")   # train: start .. this date
VALID_END = os.environ.get("ENERGY_VALID_END", "2016-12-31")   # validation: day after TRAIN_END .. this date
# test: everything after VALID_END (2017-01-01 .. 2018-08-03)

# Prophet is slow on 14 years of hourly data, so it fits on the most recent training years only.
PROPHET_TRAIN_START = os.environ.get("ENERGY_PROPHET_TRAIN_START", "2011-01-01")

EVAL_SPLITS = ("validation", "test")

# Expanding-window backtest (week 4): N folds, each testing on the next BACKTEST_TEST_SIZE hours.
BACKTEST_FOLDS = int(os.environ.get("ENERGY_BACKTEST_FOLDS", "6"))
BACKTEST_TEST_SIZE = int(os.environ.get("ENERGY_BACKTEST_TEST_SIZE", "8760"))   # ~1 year

# Temperature what-if offsets (degrees C) scored by LightGBM for the Power BI scenario page.
SCENARIO_OFFSETS = list(range(-5, 6))
