-- 06_regional_segment_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only regional and customer-segment performance queries over the
-- SQLite database created by sql/01_create_database.sql and loaded by
-- scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line). Every measure
-- below is an additive sum over line rows, so grouping lines by Region/Segment
-- is valid. Orders are counted with COUNT(DISTINCT "Order ID"). `returns` is
-- order-level and is deliberately not joined here (joining would multiply order
-- lines, and `returns` carries no amount).
--
-- Definitions (consistent with sql/03_sales_trends.sql through
-- sql/05_discount_analysis.sql):
--   order_lines      = COUNT(*)
--   orders           = COUNT(DISTINCT "Order ID")   (distinct orders in the group)
--   units_sold       = SUM("Quantity")
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / SUM("Sales")  (a group ratio; never an
--                      average of row-level margins)
--   avg_order_value  = SUM("Sales") / COUNT(DISTINCT "Order ID")
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Region and Segment are per-line attributes. In principle an order could have
-- lines in more than one Region or Segment. Therefore distinct order counts and
-- average order value MUST NOT be summed across groups: an order spanning groups
-- would be counted once per group, so SUM(orders) can exceed the 5,111 distinct
-- orders and per-group AOV can be deflated. Only order_lines, units_sold, sales,
-- and profit reconcile additively across groups. Whether orders actually span
-- groups is checked separately (validation), but the caution applies regardless.
--
-- Rows and dates: no rows are removed (retained repeated `Order ID + Product ID`
-- cases and rows duplicated when ignoring `Row ID` remain) and no date filter is
-- applied, so future-dated order lines are preserved rather than silently
-- excluded. The analysis is whole-period and unadjusted for returns. Retained
-- duplicate lines slightly inflate the additive measures.
--
-- Interpretation limits: results are DESCRIPTIVE, not causal; the Regional
-- Manager label from `people` is contextual only and implies nothing about
-- manager performance. `Region` groups include the Canadian order lines (Canada
-- still carries a Region), so results mix both countries. Groups differ in size
-- (segments and Region x Segment cells especially), so margins on small groups
-- are volatile: read order_lines/orders alongside every margin.

-- ---------------------------------------------------------------------------
-- 1) Regional performance. The LEFT JOIN to `people` adds the Regional Manager
--    as a 1:1 label ("Region" is the parent primary key), so it does not change
--    the grain or any metric.
-- ---------------------------------------------------------------------------
SELECT
    o."Region"                                             AS region,
    p."Regional Manager"                                   AS regional_manager,
    COUNT(*)                                               AS order_lines,
    COUNT(DISTINCT o."Order ID")                           AS orders,
    SUM(o."Quantity")                                      AS units_sold,
    ROUND(SUM(o."Sales"), 2)                               AS sales,
    ROUND(SUM(o."Profit"), 2)                              AS profit,
    ROUND(SUM(o."Profit") / NULLIF(SUM(o."Sales"), 0), 4)  AS profit_margin,
    ROUND(SUM(o."Sales") / NULLIF(COUNT(DISTINCT o."Order ID"), 0), 2) AS avg_order_value
FROM orders AS o
LEFT JOIN people AS p ON p."Region" = o."Region"
GROUP BY o."Region", p."Regional Manager"
ORDER BY profit DESC;

-- ---------------------------------------------------------------------------
-- 2) Segment performance.
-- ---------------------------------------------------------------------------
SELECT
    "Segment"                                              AS segment,
    COUNT(*)                                               AS order_lines,
    COUNT(DISTINCT "Order ID")                             AS orders,
    SUM("Quantity")                                        AS units_sold,
    ROUND(SUM("Sales"), 2)                                 AS sales,
    ROUND(SUM("Profit"), 2)                                AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4)      AS profit_margin,
    ROUND(SUM("Sales") / NULLIF(COUNT(DISTINCT "Order ID"), 0), 2) AS avg_order_value
FROM orders
GROUP BY "Segment"
ORDER BY profit DESC;

-- ---------------------------------------------------------------------------
-- 3) Region x Segment performance. Adds the cross dimension to show whether a
--    region's margin is broad or concentrated in one segment, and whether a
--    segment behaves differently across regions. Descriptive only: cells differ
--    in size, so small cells can show volatile margins.
-- ---------------------------------------------------------------------------
SELECT
    "Region"                                               AS region,
    "Segment"                                              AS segment,
    COUNT(*)                                               AS order_lines,
    COUNT(DISTINCT "Order ID")                             AS orders,
    SUM("Quantity")                                        AS units_sold,
    ROUND(SUM("Sales"), 2)                                 AS sales,
    ROUND(SUM("Profit"), 2)                                AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4)      AS profit_margin,
    ROUND(SUM("Sales") / NULLIF(COUNT(DISTINCT "Order ID"), 0), 2) AS avg_order_value
FROM orders
GROUP BY "Region", "Segment"
ORDER BY region, profit DESC;
