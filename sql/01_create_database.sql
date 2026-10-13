-- 01_create_database.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: create (or recreate) the SQLite schema for the processed Superstore data.
--
-- How to use:
--   * This script only defines the schema. It is safe to re-run: every table is
--     dropped and recreated first, so no duplicate rows can accumulate.
--   * Rows are loaded from the processed CSV files by scripts/load_superstore_db.py,
--     which uses the project .venv and the standard-library sqlite3 module. Loading
--     is not performed by this SQL script so that CSV parsing and ISO date
--     normalization stay in one explicit, repeatable place.
--
-- Data model:
--   orders  -> order-line level records (one row per product line within an order).
--   people  -> reference table: one regional manager per region.
--   returns -> order-level records: one row per returned order.
--
-- Grain and relationships:
--   * orders is line-level; "Row ID" uniquely identifies a line while "Order ID"
--     intentionally repeats when an order has multiple lines.
--   * orders."Region" has a foreign key to people."Region".
--   * returns is order-level. There is deliberately no foreign key from
--     returns."Order ID" to orders."Order ID", because "Order ID" is not unique in
--     orders (line grain) and SQLite requires the parent key to be unique.
--   * The tables are never joined during loading, so order lines are not multiplied.

PRAGMA foreign_keys = ON;

-- Drop children before parents so foreign-key enforcement cannot block a rebuild.
DROP TABLE IF EXISTS returns;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS people;

-- ---------------------------------------------------------------------------
-- people: reference table with one row per region. "Region" is unique here and
-- is the parent key referenced by orders."Region".
-- ---------------------------------------------------------------------------
CREATE TABLE people (
    "Regional Manager" TEXT,
    "Region"           TEXT PRIMARY KEY
);

-- ---------------------------------------------------------------------------
-- orders: one row per order line. "Row ID" uniquely identifies a line, while
-- "Order ID" intentionally repeats when an order contains multiple lines.
-- Dates are stored as ISO 8601 calendar dates (YYYY-MM-DD) in TEXT columns.
-- "Postal Code" is stored as TEXT and is not padded or converted to a number.
-- ---------------------------------------------------------------------------
CREATE TABLE orders (
    "Row ID"          INTEGER PRIMARY KEY,
    "Order ID"        TEXT    NOT NULL,
    "Order Date"      TEXT    NOT NULL,
    "Ship Date"       TEXT    NOT NULL,
    "Ship Mode"       TEXT,
    "Customer ID"     TEXT,
    "Customer Name"   TEXT,
    "Segment"         TEXT,
    "Country/Region"  TEXT,
    "City"            TEXT,
    "State/Province"  TEXT,
    "Postal Code"     TEXT,
    "Region"          TEXT    REFERENCES people("Region"),
    "Product ID"      TEXT,
    "Category"        TEXT,
    "Sub-Category"    TEXT,
    "Product Name"    TEXT,
    "Sales"           REAL,
    "Quantity"        INTEGER,
    "Discount"        REAL,
    "Profit"          REAL
);

CREATE INDEX idx_orders_order_id ON orders("Order ID");
CREATE INDEX idx_orders_region ON orders("Region");

-- ---------------------------------------------------------------------------
-- returns: order-level records. "Order ID" is unique in this table.
-- ---------------------------------------------------------------------------
CREATE TABLE returns (
    "Order ID" TEXT PRIMARY KEY,
    "Returned" TEXT
);
