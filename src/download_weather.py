"""Download hourly Philadelphia weather from Open-Meteo, one year at a time.

Each year is cached to data/weather/philly_<year>.csv, so a failed or rate-limited
run can simply be repeated: finished years are skipped. At the end all yearly
files are combined into data/weather_philly.csv (the file loaded by 02_load_raw.sql).

Run from the project root:  python src/download_weather.py
"""
import time
from pathlib import Path

import pandas as pd
import requests

START_YEAR, END_YEAR = 2002, 2018
URL = "https://archive-api.open-meteo.com/v1/archive"
OUT_DIR = Path("data/weather")
COMBINED = Path("data/weather_philly.csv")


def fetch_year(year: int) -> pd.DataFrame:
    params = {
        "latitude": 39.95,
        "longitude": -75.17,
        "start_date": f"{year}-01-01",
        "end_date": f"{year}-12-31",
        "hourly": "temperature_2m,relative_humidity_2m,wind_speed_10m",
        "timezone": "America/New_York",  # local time, matches the PJM load file
    }
    for attempt in range(4):
        r = requests.get(URL, params=params, timeout=60)
        if r.status_code == 429:  # rate limited: back off and retry
            wait = 30 * (attempt + 1)
            print(f"  rate limited, waiting {wait}s")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return pd.DataFrame(r.json()["hourly"])
    raise RuntimeError(f"Open-Meteo kept rate limiting year {year}; rerun later.")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for year in range(START_YEAR, END_YEAR + 1):
        f = OUT_DIR / f"philly_{year}.csv"
        if f.exists():
            print("cached", f)
            continue
        fetch_year(year).to_csv(f, index=False)
        print("saved ", f)
        time.sleep(2)

    frames = [pd.read_csv(OUT_DIR / f"philly_{y}.csv") for y in range(START_YEAR, END_YEAR + 1)]
    combined = pd.concat(frames, ignore_index=True)
    combined.to_csv(COMBINED, index=False)
    print(f"combined {len(combined):,} rows -> {COMBINED}")


if __name__ == "__main__":
    main()
