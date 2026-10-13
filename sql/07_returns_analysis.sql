-- 07_returns_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only returns analysis over the SQLite database created by
-- sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Grain and join safety:
--   * `orders` is order-line level (10,194 lines for 5,111 distinct orders).
--   * `returns` is order-level: "Order ID" is the primary key (296 rows), and
--     every returned "Order ID" also exists in `orders` (checked by 02).
--   * To avoid multiplying sales/profit, orders are aggregated to order grain
--     (SUM per "Order ID") BEFORE joining `returns`, or joined line-to-order on
--     the unique returns key (a 1:1 match). Never join raw line rows straight to
--     a non-unique key.
--
-- Definitions:
--   total_orders          = COUNT(DISTINCT "Order ID") over orders
--   returned_orders       = COUNT(DISTINCT "Order ID") present in `returns`
--   return_rate           = returned_orders / total_orders   (distinct orders;
--                           guarded with NULLIF against a zero denominator)
--   total_sales           = SUM("Sales") over all order lines
--   returned_order_sales  = SUM("Sales") over the lines of returned orders
--   returned_order_profit = SUM("Profit") over the lines of returned orders
--   ROUND is presentation-only; ratios use unrounded values.
--
-- Retention: no rows are removed (retained repeated "Order ID + Product ID"
-- cases and rows duplicated when ignoring "Row ID" remain), no deduplication,
-- no data modification, and no date filter. Future-dated order lines and
-- Canadian data are therefore included. The analysis is whole-period.
--
-- Interpretation limits: results are DESCRIPTIVE, not causal. `returns` records
-- only that an order was returned (a flag); it carries no refund amount and no
-- per-product return status. Category/sub-category figures therefore describe
-- the product lines that sit WITHIN returned orders, not confirmed returned
-- products, refunds, or financial losses. Return status applies to the entire
-- order, not to individual lines.

-- ---------------------------------------------------------------------------
-- 1) Overall returns.
--    Orders are collapsed to one row per "Order ID" before joining `returns`,
--    so sales are not multiplied by the number of lines per order.
-- ---------------------------------------------------------------------------
WITH order_totals AS (
    SELECT
        "Order ID" AS order_id,
        SUM("Sales")  AS sales,
        SUM("Profit") AS profit
    FROM orders
    GROUP BY "Order ID"
)
SELECT
    COUNT(*)                                                        AS total_orders,
    SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END)       AS returned_orders,
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END) * 1.0
          / NULLIF(COUNT(*), 0), 4)                                 AS return_rate,
    ROUND(SUM(ot.sales), 2)                                         AS total_sales,
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN ot.sales ELSE 0 END), 2)
                                                                    AS returned_order_sales
FROM order_totals AS ot
LEFT JOIN returns AS r ON r."Order ID" = ot.order_id;

-- ---------------------------------------------------------------------------
-- 2) Returns by Region and by Segment (one result set, labelled by dimension).
--    Region and Segment are per-line attributes, so orders are aggregated to
--    ("Order ID", Region) and ("Order ID", Segment) separately before joining
--    `returns`. If an order ever spanned multiple regions/segments it would be
--    counted in each such group, so the per-group order counts are not additive
--    across groups; in this dataset every order sits in exactly one region and
--    one segment (verified in validation).
-- ---------------------------------------------------------------------------
WITH order_region AS (
    SELECT
        "Order ID" AS order_id,
        "Region"   AS region,
        SUM("Sales") AS sales
    FROM orders
    GROUP BY "Order ID", "Region"
),
order_segment AS (
    SELECT
        "Order ID" AS order_id,
        "Segment"  AS segment,
        SUM("Sales") AS sales
    FROM orders
    GROUP BY "Order ID", "Segment"
)
SELECT
    'region'                                                   AS dimension,
    g.region                                                   AS group_value,
    COUNT(*)                                                   AS orders,
    SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END)  AS returned_orders,
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END) * 1.0
          / NULLIF(COUNT(*), 0), 4)                            AS return_rate,
    ROUND(SUM(g.sales), 2)                                     AS total_sales,
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN g.sales ELSE 0 END), 2)
                                                               AS returned_order_sales
FROM order_region AS g
LEFT JOIN returns AS r ON r."Order ID" = g.order_id
GROUP BY g.region
UNION ALL
SELECT
    'segment',
    g.segment,
    COUNT(*),
    SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN 1 ELSE 0 END) * 1.0
          / NULLIF(COUNT(*), 0), 4),
    ROUND(SUM(g.sales), 2),
    ROUND(SUM(CASE WHEN r."Order ID" IS NOT NULL THEN g.sales ELSE 0 END), 2)
FROM order_segment AS g
LEFT JOIN returns AS r ON r."Order ID" = g.order_id
GROUP BY g.segment
ORDER BY dimension, group_value;

-- ---------------------------------------------------------------------------
-- 3) Returns by Category and Sub-Category.
--    Line-grain: counts and sums the product lines that fall WITHIN returned
--    orders. The join to `returns` is on its unique primary key, so each order
--    line matches at most once (no multiplication). Return status applies to
--    the whole order, so these are lines within returned orders -- NOT confirmed
--    returned products, refunds, or losses.
-- ---------------------------------------------------------------------------
SELECT
    o."Category"                            AS category,
    o."Sub-Category"                        AS sub_category,
    COUNT(*)                                AS returned_order_lines,
    ROUND(SUM(o."Sales"), 2)                AS returned_order_sales,
    ROUND(SUM(o."Profit"), 2)               AS returned_order_profit
FROM orders AS o
JOIN returns AS r ON r."Order ID" = o."Order ID"
GROUP BY o."Category", o."Sub-Category"
ORDER BY category, sub_category;
