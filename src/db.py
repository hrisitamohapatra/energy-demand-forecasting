"""Database connection helper. Reads PG* settings from the environment or the .env file."""
import os
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.engine import URL

ROOT = Path(__file__).resolve().parents[1]


def load_env() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def get_engine():
    load_env()
    url = URL.create(
        "postgresql+psycopg2",
        username=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD"),
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "5432")),
        database=os.environ.get("PGDATABASE", "energy_forecast"),
    )
    return create_engine(url)
