-- 10_geographic_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only geographic performance queries over the SQLite database
-- created by sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line; 10,194 lines
-- for 5,111 distinct orders). Measures sum line rows, while orders are counted
-- with COUNT(DISTINCT "Order ID"). `returns` is order-level and is deliberately
-- not joined here (joining would multiply order lines, and `returns` carries no
-- amount).
--
-- Definitions (consistent with sql/03_sales_trends.sql through
-- sql/09_shipping_analysis.sql):
--   orders           = COUNT(DISTINCT "Order ID")   (orders containing the group)
--   order_lines      = COUNT(*)                     (line rows)
--   units_sold       = SUM("Quantity")
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / NULLIF(SUM("Sales"), 0)   (a group ratio,
--                      never an average of line-level margins)
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Geography: `Region` and `Country/Region` are separate labels. Region is a
-- manager grouping (see `people`); Country/Region is the country. There are two
-- countries (Canada, United States) and four regions (Central, East, South,
-- West); Canada does not use the South region. State/Province names are not
-- assumed globally unique, so statement 3 groups by BOTH "Country/Region" and
-- "State/Province". (In this dataset the 59 state/province names happen to be
-- unique across the 2 countries, but the query does not rely on that.)
--
-- Distinct order counts are NOT additive across groups: an order can contain
-- lines attributed to more than one group, so it is then counted once per such
-- group. Line measures (order_lines, units_sold, sales, profit) are additive.
-- (Verified in validation: no order spans multiple countries, regions, or
-- states/provinces here, so per-group orders currently sum to 5,111.)
--
-- Rows and dates: no rows are removed, no deduplication is performed, `returns`
-- is not joined, and no date filter is applied. Future-dated order lines and
-- Canadian data are retained, so geographic figures cover the whole dataset.
--
-- Interpretation limits: results are DESCRIPTIVE, not causal. Profitability is
-- whole-period and unadjusted for returns. Small locations can show a volatile
-- margin, so `order_lines` and `orders` should be read alongside the ratio.

-- ---------------------------------------------------------------------------
-- 1) Country performance, best sales first.
-- ---------------------------------------------------------------------------
SELECT
    "Country/Region"                                  AS country,
    COUNT(DISTINCT "Order ID")                        AS orders,
    COUNT(*)                                          AS order_lines,
    SUM("Quantity")                                   AS units_sold,
    ROUND(SUM("Sales"), 2)                            AS sales,
    ROUND(SUM("Profit"), 2)                           AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4) AS profit_margin
FROM orders
GROUP BY "Country/Region"
ORDER BY sales DESC;

-- ---------------------------------------------------------------------------
-- 2) Region performance, best sales first. Region is the regional-manager
--    grouping, not the country.
-- ---------------------------------------------------------------------------
SELECT
    "Region"                                          AS region,
    COUNT(DISTINCT "Order ID")                        AS orders,
    COUNT(*)                                          AS order_lines,
    SUM("Quantity")                                   AS units_sold,
    ROUND(SUM("Sales"), 2)                            AS sales,
    ROUND(SUM("Profit"), 2)                           AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4) AS profit_margin
FROM orders
GROUP BY "Region"
ORDER BY sales DESC;

-- ---------------------------------------------------------------------------
-- 3) State/Province performance, weakest profit first to surface loss-making
--    locations. Grouped by BOTH "Country/Region" and "State/Province" because a
--    state/province name is not assumed to be globally unique.
-- ---------------------------------------------------------------------------
SELECT
    "Country/Region"                                  AS country,
    "State/Province"                                  AS state_province,
    COUNT(DISTINCT "Order ID")                        AS orders,
    COUNT(*)                                          AS order_lines,
    SUM("Quantity")                                   AS units_sold,
    ROUND(SUM("Sales"), 2)                            AS sales,
    ROUND(SUM("Profit"), 2)                           AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4) AS profit_margin
FROM orders
GROUP BY "Country/Region", "State/Province"
ORDER BY profit ASC, "Country/Region", "State/Province";
