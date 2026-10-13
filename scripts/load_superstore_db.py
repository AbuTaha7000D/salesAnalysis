#!/usr/bin/env python3
"""Create or rebuild the Superstore SQLite database from the processed CSV files.

This loader uses only the Python standard library (``sqlite3``, ``csv``, ``os`` and
``tempfile``). All paths are resolved relative to the repository (based on this
file's location), so the script can be run from any working directory.

Rebuilding is reproducible and failure-safe:

* The schema is created and every CSV is loaded and validated in a temporary
  database file located next to the destination.
* Only after all steps succeed is the destination replaced atomically with
  ``os.replace()``. If anything fails, the temporary database and its SQLite
  sidecar files are removed and any existing destination database is left
  untouched.

Usage:
    python scripts/load_superstore_db.py
"""

from __future__ import annotations

import csv
import os
import sqlite3
import sys
import tempfile
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = REPO_ROOT / "sql" / "01_create_database.sql"
PROCESSED_DIRECTORY = REPO_ROOT / "data" / "processed"
DATABASE_PATH = PROCESSED_DIRECTORY / "superstore.db"

# Tables in load order. The parent table (people) is loaded before the child
# table (orders) because orders."Region" references people."Region" and
# foreign-key enforcement is enabled.
TABLES = (
    ("people", "people_clean.csv"),
    ("orders", "orders_clean.csv"),
    ("returns", "returns_clean.csv"),
)

# Primary key used to match source rows with imported rows during validation.
PRIMARY_KEYS = {
    "people": "Region",
    "orders": "Row ID",
    "returns": "Order ID",
}

DATE_COLUMNS = frozenset({"Order Date", "Ship Date"})
INTEGER_COLUMNS = frozenset({"Row ID", "Quantity"})
REAL_COLUMNS = frozenset({"Sales", "Discount", "Profit"})

# SQLite sidecar files that may accompany a database file.
SIDECAR_SUFFIXES = ("", "-journal", "-wal", "-shm")


class LoadError(RuntimeError):
    """Raised when loading or validating the database fails."""


def normalize_date(value: str) -> str | None:
    """Return an ISO 8601 calendar date (YYYY-MM-DD) from a CSV date value."""
    value = value.strip()
    if value == "":
        return None
    try:
        return datetime.fromisoformat(value).date().isoformat()
    except ValueError:
        pass
    for date_format in ("%m/%d/%Y", "%m/%d/%y", "%Y/%m/%d"):
        try:
            return datetime.strptime(value, date_format).date().isoformat()
        except ValueError:
            continue
    raise LoadError(f"Unrecognized date value: {value!r}")


def convert_value(column: str, value: str):
    """Convert a raw CSV string into the Python value stored in SQLite.

    Postal Code and other text columns are returned unchanged so that stored
    values (including leading-zero text such as "05401") are preserved exactly.
    """
    if column in DATE_COLUMNS:
        return normalize_date(value)
    if column in REAL_COLUMNS:
        return None if value.strip() == "" else float(value)
    if column in INTEGER_COLUMNS:
        return None if value.strip() == "" else int(float(value))
    return value


def read_csv(path: Path):
    """Read a processed CSV and return (columns, rows) with converted values."""
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise LoadError(f"CSV file has no header row: {path}")
        columns = list(reader.fieldnames)
        rows = [
            [convert_value(column, raw[column]) for column in columns]
            for raw in reader
        ]
    return columns, rows


def insert_rows(connection, table, columns, rows):
    if not rows:
        return
    quoted_columns = ", ".join(f'"{column}"' for column in columns)
    placeholders = ", ".join("?" for _ in columns)
    connection.executemany(
        f'INSERT INTO "{table}" ({quoted_columns}) VALUES ({placeholders})', rows
    )


def foreign_key_enforcement_is_on(connection) -> bool:
    return connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1


def verify_foreign_key_enforcement(connection):
    """Require foreign-key enforcement and prove it with a violating update."""
    if not foreign_key_enforcement_is_on(connection):
        raise LoadError("Foreign-key enforcement is not enabled on the connection.")

    connection.execute("SAVEPOINT fk_probe")
    violation_raised = False
    try:
        connection.execute(
            'UPDATE orders SET "Region" = ? '
            'WHERE "Row ID" = (SELECT MIN("Row ID") FROM orders)',
            ("__foreign_key_probe__",),
        )
    except sqlite3.IntegrityError:
        violation_raised = True
    finally:
        connection.execute("ROLLBACK TO fk_probe")
        connection.execute("RELEASE fk_probe")

    if not violation_raised:
        raise LoadError(
            'Foreign-key constraint on orders."Region" was not enforced.'
        )


def validate_table(connection, table, columns, rows, key_column):
    """Confirm imported rows, keys, and values match the source CSV exactly."""
    key_position = columns.index(key_column)
    quoted_columns = ", ".join(f'"{column}"' for column in columns)
    imported_rows = connection.execute(
        f'SELECT {quoted_columns} FROM "{table}"'
    ).fetchall()

    if len(imported_rows) != len(rows):
        raise LoadError(
            f"{table}: imported {len(imported_rows)} rows but the CSV has {len(rows)}."
        )

    imported_by_key = {}
    for row in imported_rows:
        key = row[key_position]
        if key in imported_by_key:
            raise LoadError(f"{table}: duplicate primary key {key!r} after import.")
        imported_by_key[key] = row

    for expected in rows:
        key = expected[key_position]
        actual = imported_by_key.get(key)
        if actual is None:
            raise LoadError(f"{table}: primary key {key!r} from the CSV is missing.")
        for position, column in enumerate(columns):
            if actual[position] != expected[position]:
                raise LoadError(
                    f"{table}.{column} for key {key!r} does not match the CSV: "
                    f"imported {actual[position]!r}, expected {expected[position]!r}."
                )

    return len(imported_rows)


def build_database(database_path: Path):
    """Create the schema and load/validate all data into ``database_path``.

    The database connection is always closed before this function returns or
    raises, so the caller can safely replace the destination once it returns.
    """
    if not SCHEMA_PATH.exists():
        raise LoadError(f"Schema file not found: {SCHEMA_PATH}")
    schema_sql = SCHEMA_PATH.read_text(encoding="utf-8")

    connection = sqlite3.connect(database_path, isolation_level=None)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.executescript(schema_sql)

        sources = {}
        for table, filename in TABLES:
            csv_path = PROCESSED_DIRECTORY / filename
            if not csv_path.exists():
                raise LoadError(f"Processed CSV not found: {csv_path}")
            sources[table] = read_csv(csv_path)

        connection.execute("BEGIN")
        try:
            for table, _ in TABLES:
                insert_rows(connection, table, *sources[table])

            verify_foreign_key_enforcement(connection)

            counts = {
                table: validate_table(
                    connection, table, *sources[table], PRIMARY_KEYS[table]
                )
                for table, _ in TABLES
            }
            connection.commit()
        except Exception:
            connection.rollback()
            raise

        return counts
    finally:
        connection.close()


def remove_temporary_database(database_path: Path) -> None:
    """Delete a temporary database file and any SQLite sidecar files."""
    for suffix in SIDECAR_SUFFIXES:
        candidate = Path(f"{database_path}{suffix}")
        try:
            candidate.unlink()
        except FileNotFoundError:
            pass


def preserve_destination_mode(temporary_path: Path) -> None:
    """Match the destination file mode (fallback to 0644) for the new database."""
    try:
        mode = DATABASE_PATH.stat().st_mode & 0o777
    except FileNotFoundError:
        mode = 0o644
    os.chmod(temporary_path, mode)


def load_database():
    """Build into a temporary database, then atomically replace the destination."""
    PROCESSED_DIRECTORY.mkdir(parents=True, exist_ok=True)

    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix="superstore.", suffix=".db.tmp", dir=PROCESSED_DIRECTORY
    )
    os.close(file_descriptor)
    temporary_path = Path(temporary_name)

    try:
        counts = build_database(temporary_path)
        preserve_destination_mode(temporary_path)
    except Exception:
        remove_temporary_database(temporary_path)
        raise

    # All connections are closed; replace the destination in a single atomic step.
    try:
        os.replace(temporary_path, DATABASE_PATH)
    except Exception:
        remove_temporary_database(temporary_path)
        raise

    return counts


def main() -> int:
    print(f"Repository root: {REPO_ROOT}")
    print(f"Database:        {DATABASE_PATH}")
    try:
        counts = load_database()
    except (LoadError, sqlite3.Error, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        print("Existing database (if any) was left unchanged.", file=sys.stderr)
        return 1

    print("Database created/updated successfully (replaced atomically).")
    for table, _ in TABLES:
        print(f"  {table}: {counts[table]} rows")
    print("Imported values match the processed CSVs for every row and column.")
    print("Foreign-key enforcement is enabled and verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
