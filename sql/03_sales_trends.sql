-- 03_sales_trends.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only sales-trend queries over the SQLite database created by
-- sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Grain: the `orders` table is order-line level. Measures sum line rows, while
-- orders are counted with COUNT(DISTINCT "Order ID"). `returns` is order-level
-- and is deliberately not joined here (joining would multiply order lines).
--
-- Definitions:
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / SUM("Sales")   (a period ratio, not an
--                      average of row-level or order-level margins)
--   orders           = COUNT(DISTINCT "Order ID")
--   units_sold       = SUM("Quantity")
--   avg_order_value  = SUM("Sales") / COUNT(DISTINCT "Order ID")
--
-- Period assignment uses "Order Date" (ISO 8601 text, so strftime works and
-- 'YYYY-MM' sorts chronologically). No date filter is applied: future-dated
-- records are preserved, not silently excluded.
--
-- All divisions use NULLIF to avoid errors and to return NULL instead of a
-- misleading value when a denominator is zero.

-- ---------------------------------------------------------------------------
-- 1) Monthly sales, profit and profit margin, with month-over-month changes.
-- ---------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', "Order Date") AS month,
        COUNT(DISTINCT "Order ID")      AS orders,
        SUM("Quantity")                 AS units_sold,
        SUM("Sales")                    AS sales,
        SUM("Profit")                   AS profit
    FROM orders
    GROUP BY month
),
monthly_with_previous AS (
    SELECT
        month,
        orders,
        units_sold,
        sales,
        profit,
        LAG(sales)  OVER (ORDER BY month) AS previous_sales,
        LAG(profit) OVER (ORDER BY month) AS previous_profit
    FROM monthly
)
SELECT
    month,
    orders,
    units_sold,
    ROUND(sales, 2)                                                       AS sales,
    ROUND(profit, 2)                                                      AS profit,
    ROUND(profit / NULLIF(sales, 0), 4)                                   AS profit_margin,
    ROUND(sales / NULLIF(orders, 0), 2)                                   AS avg_order_value,
    ROUND(sales - previous_sales, 2)                                      AS sales_change,
    ROUND((sales - previous_sales) / NULLIF(previous_sales, 0), 4)        AS sales_change_pct,
    ROUND(profit - previous_profit, 2)                                    AS profit_change,
    CASE
        WHEN previous_profit > 0
        THEN ROUND((profit - previous_profit) / previous_profit, 4)
        ELSE NULL
    END                                                                   AS profit_change_pct
FROM monthly_with_previous
ORDER BY month;

-- ---------------------------------------------------------------------------
-- 2) Yearly sales, profit and profit margin.
-- ---------------------------------------------------------------------------
SELECT
    strftime('%Y', "Order Date")                          AS year,
    COUNT(DISTINCT "Order ID")                            AS orders,
    SUM("Quantity")                                       AS units_sold,
    ROUND(SUM("Sales"), 2)                                AS sales,
    ROUND(SUM("Profit"), 2)                               AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4)     AS profit_margin,
    ROUND(SUM("Sales") / NULLIF(COUNT(DISTINCT "Order ID"), 0), 2) AS avg_order_value
FROM orders
GROUP BY year
ORDER BY year;
