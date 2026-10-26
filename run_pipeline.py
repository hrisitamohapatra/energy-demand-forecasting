"""Runs the numbered SQL scripts in sql/ in order and stops on the first failure.

Usage (from the project root):
    python run_pipeline.py                 # run every script found, 01 -> 10
    python run_pipeline.py --only 04       # run just step 04
    python run_pipeline.py --upto 03       # run 01 through 03

Connection settings come from environment variables (or a .env file, see
.env.example): PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE.
Scripts run through psql so that \\copy in 02_load_raw.sql works.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"
DEFAULT_PSQL = r"C:\Program Files\PostgreSQL\18\bin\psql.exe"


def load_env_file() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def find_psql() -> str:
    found = shutil.which("psql")
    if found:
        return found
    if Path(DEFAULT_PSQL).exists():
        return DEFAULT_PSQL
    sys.exit("psql not found. Add PostgreSQL's bin folder to PATH or edit DEFAULT_PSQL.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="run only the script with this number prefix, e.g. 03")
    parser.add_argument("--upto", help="run scripts up to and including this number prefix")
    args = parser.parse_args()

    load_env_file()
    os.environ.setdefault("PGHOST", "localhost")
    os.environ.setdefault("PGPORT", "5432")
    os.environ.setdefault("PGUSER", "postgres")
    os.environ.setdefault("PGDATABASE", "energy_forecast")
    if "PGPASSWORD" not in os.environ:
        sys.exit("Set PGPASSWORD (environment variable or .env file) first.")

    # Steps are (name, kind, path). 03b_load_holidays sorts right after 03_stage.
    steps = [(p.name, "sql", p) for p in SQL_DIR.glob("[0-9][0-9]_*.sql")]
    holidays_py = ROOT / "src" / "load_holidays.py"
    if holidays_py.exists():
        steps.append(("03b_load_holidays.py", "py", holidays_py))
    steps.sort(key=lambda s: s[0])
    if args.only:
        steps = [s for s in steps if s[0].startswith(args.only)]
    if args.upto:
        steps = [s for s in steps if s[0][:2] <= args.upto]
    if not steps:
        sys.exit("No matching steps found.")

    psql = find_psql()
    for name, kind, path in steps:
        print(f"\n=== {name} ===", flush=True)
        if kind == "sql":
            cmd = [psql, "-v", "ON_ERROR_STOP=1", "-X", "-P", "pager=off", "-f", str(path)]
        else:
            cmd = [sys.executable, str(path)]
        result = subprocess.run(cmd, cwd=ROOT)  # cwd=ROOT so data/... paths resolve
        if result.returncode != 0:
            sys.exit(f"\nStopped: {name} failed.")
    print("\nPipeline finished.")


if __name__ == "__main__":
    main()
