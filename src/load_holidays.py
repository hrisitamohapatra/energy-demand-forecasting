"""Load US federal holidays (2002-2018) into staging.holidays.

Pipeline step 03b: runs after 03_stage.sql and before 04_clean.sql.
Connection settings come from the PG* environment variables.
"""
import os

import holidays
import psycopg2
from psycopg2.extras import execute_values

YEARS = range(2002, 2019)


def main() -> None:
    us = holidays.US(years=YEARS)  # federal holidays, including observed days
    rows = sorted(us.items())

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD"),
        dbname=os.environ.get("PGDATABASE", "energy_forecast"),
    )
    with conn, conn.cursor() as cur:
        cur.execute("TRUNCATE staging.holidays")
        execute_values(cur, "INSERT INTO staging.holidays (holiday_date, holiday_name) VALUES %s", rows)
    conn.close()
    print(f"loaded {len(rows)} holidays into staging.holidays")


if __name__ == "__main__":
    main()
