-- 09_shipping_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only shipping/duration queries over the SQLite database created
-- by sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line; 10,194 lines
-- for 5,111 distinct orders). Line measures (units, sales, profit) sum line
-- rows, while orders are counted with COUNT(DISTINCT "Order ID"). `returns` is
-- order-level and is deliberately not joined here.
--
-- Shipping duration: computed as
--   julianday("Ship Date") - julianday("Order Date")
-- in fractional days. It is the ORDER-TO-SHIP duration for an order, i.e. the
-- time from the order being placed to it being shipped. It is NOT confirmed
-- delivery time, transit time, or fulfilment time; no delivery date exists in
-- the data. `"Order Date"` and `"Ship Date"` are ISO 8601 (YYYY-MM-DD) TEXT and
-- are constant within an order. Duration is therefore computed at ONE ROW PER
-- "Order ID" (via GROUP BY "Order ID") before any order-level average, median,
-- distribution or count, so multiple product lines never inflate order counts
-- or skew duration statistics.
--
-- Definitions (consistent with sql/03_sales_trends.sql through
-- sql/08_customer_analysis.sql):
--   orders           = COUNT(DISTINCT "Order ID")   (distinct orders)
--   order_lines      = COUNT(*)                     (line rows)
--   units_sold       = SUM("Quantity")
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / NULLIF(SUM("Sales"), 0)   (a group ratio)
--   avg_ship_days    = AVG over distinct orders of order-to-ship duration
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Duration bands (statement 2) are mutually exclusive and exhaustive for any
-- non-negative duration, expressed in whole days:
--   0 days (same day) | 1-2 days | 3-4 days | 5-7 days | 8+ days
-- A final 'out of range (negative)' catch-all keeps the set exhaustive even if
-- an unexpected Ship Date before Order Date ever appears; it is empty here.
--
-- Medians (statement 3) are exact, not approximations: orders are ranked within
-- each region with ROW_NUMBER(); for an odd count the single middle rank is
-- used, and for an even count the two middle ranks are averaged, so even-sized
-- groups are handled correctly.
--
-- Rows and dates: no rows are removed, no deduplication is performed, `returns`
-- is not joined, and no date filter is applied. Future-dated order lines and
-- Canadian data are retained, so shipping figures cover the whole dataset.
--
-- Interpretation limits: results are DESCRIPTIVE, not causal. Shipping mode is
-- chosen by the customer (or fulfilment policy), not assigned at random, so
-- differences across modes or regions are associations only and do not identify
-- the effect of choosing a mode. Durations are also unadjusted for returns.

-- ---------------------------------------------------------------------------
-- 1) Shipping-mode performance, best sales first. Line measures come from the
--    line-level table; avg_ship_days is averaged over distinct orders so that
--    multi-line orders are counted once.
-- ---------------------------------------------------------------------------
WITH orders_duration AS (
    SELECT
        "Order ID"                                     AS order_id,
        MIN("Ship Mode")                               AS ship_mode,
        julianday(MIN("Ship Date")) - julianday(MIN("Order Date")) AS duration_days
    FROM orders
    GROUP BY "Order ID"
),
duration_by_mode AS (
    SELECT
        ship_mode,
        COUNT(*)          AS orders,
        AVG(duration_days) AS avg_ship_days
    FROM orders_duration
    GROUP BY ship_mode
),
lines_by_mode AS (
    SELECT
        "Ship Mode"        AS ship_mode,
        COUNT(*)           AS order_lines,
        SUM("Quantity")    AS units_sold,
        SUM("Sales")       AS sales,
        SUM("Profit")      AS profit
    FROM orders
    GROUP BY "Ship Mode"
)
SELECT
    l.ship_mode,
    d.orders,
    l.order_lines,
    l.units_sold,
    ROUND(l.sales, 2)                                  AS sales,
    ROUND(l.profit, 2)                                 AS profit,
    ROUND(l.profit / NULLIF(l.sales, 0), 4)            AS profit_margin,
    ROUND(d.avg_ship_days, 4)                          AS avg_ship_days
FROM lines_by_mode AS l
JOIN duration_by_mode AS d ON d.ship_mode = l.ship_mode
ORDER BY l.sales DESC;

-- ---------------------------------------------------------------------------
-- 2) Shipping-duration distribution across distinct orders, with each band's
--    share of all orders. Durations are computed at order grain first.
-- ---------------------------------------------------------------------------
WITH orders_duration AS (
    SELECT
        "Order ID"                                     AS order_id,
        julianday(MIN("Ship Date")) - julianday(MIN("Order Date")) AS duration_days
    FROM orders
    GROUP BY "Order ID"
),
banded AS (
    SELECT
        CASE
            WHEN duration_days < 0  THEN 'out of range (negative)'
            WHEN duration_days = 0  THEN '0 days (same day)'
            WHEN duration_days <= 2 THEN '1-2 days'
            WHEN duration_days <= 4 THEN '3-4 days'
            WHEN duration_days <= 7 THEN '5-7 days'
            ELSE '8+ days'
        END AS duration_band,
        CASE
            WHEN duration_days < 0  THEN 99
            WHEN duration_days = 0  THEN 1
            WHEN duration_days <= 2 THEN 2
            WHEN duration_days <= 4 THEN 3
            WHEN duration_days <= 7 THEN 4
            ELSE 5
        END AS band_order
    FROM orders_duration
)
SELECT
    band_order,
    duration_band,
    COUNT(*)                                          AS orders,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM banded), 0), 2)
                                                      AS pct_of_orders
FROM banded
GROUP BY band_order, duration_band
ORDER BY band_order;

-- ---------------------------------------------------------------------------
-- 3) Shipping duration by region: distinct orders, average and exact median
--    (in days). Median uses ROW_NUMBER(); for an even order count the two
--    middle durations are averaged, for an odd count the single middle one.
-- ---------------------------------------------------------------------------
WITH orders_duration AS (
    SELECT
        "Order ID"                                      AS order_id,
        MIN("Region")                                   AS region,
        julianday(MIN("Ship Date")) - julianday(MIN("Order Date")) AS duration_days
    FROM orders
    GROUP BY "Order ID"
),
ranked AS (
    SELECT
        region,
        duration_days,
        ROW_NUMBER() OVER (PARTITION BY region ORDER BY duration_days) AS rn,
        COUNT(*)     OVER (PARTITION BY region)                        AS cnt
    FROM orders_duration
)
SELECT
    region,
    COUNT(*)                                            AS orders,
    ROUND(AVG(duration_days), 4)                        AS avg_ship_days,
    ROUND(AVG(CASE WHEN rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
                   THEN duration_days END), 4)          AS median_ship_days
FROM ranked
GROUP BY region
ORDER BY avg_ship_days DESC;
