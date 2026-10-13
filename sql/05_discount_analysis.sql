-- 05_discount_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only discount-analysis queries over the SQLite database created
-- by sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line). Statement 1
-- and statement 3 aggregate lines into discount bands / sub-categories because
-- those are the dimensions under analysis and all KPIs below are additive sums.
-- Statement 2 stays at order-line grain to show specific loss-making lines.
-- `returns` is order-level and is deliberately not joined here (joining would
-- multiply order lines, and `returns` carries no amount).
--
-- Rows and dates: no rows are removed (retained repeated `Order ID + Product ID`
-- cases and rows duplicated when ignoring `Row ID` remain) and no date filter is
-- applied, so future-dated order lines are preserved rather than silently
-- excluded. The analysis is whole-period and unadjusted for returns.
--
-- Definitions (consistent with sql/03_sales_trends.sql and
-- sql/04_product_profitability.sql):
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / SUM("Sales")   (a group ratio; never an
--                      average of row-level margins)
--   orders           = COUNT(DISTINCT "Order ID")      (orders touching the group)
--   units_sold       = SUM("Quantity")
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Discount bands (half-open, lower-exclusive / upper-inclusive; zero separate):
--   0  = 0.00 (no discount)          "Discount = 0"
--   1  = (0.00, 0.10]                "0.00 < Discount <= 0.10"
--   2  = (0.10, 0.20]                ... through ...
--   8  = (0.70, 0.80]                "0.70 < Discount <= 0.80" (0.80 = dataset max)
--   99 = out of range (catch-all; expected to be empty and checked in validation)
--
-- sales_weighted_discount_index = SUM("Sales" * "Discount") / SUM("Sales").
--   This is a revenue-weighted average of the per-line Discount values within a
--   group. It is NOT the actual discount rate: it is not a contractual rate, it
--   is sensitive to line mix, and it weights large lines more heavily. Use it
--   only as a descriptive intensity indicator.
--
-- Interpretation limits: these are DESCRIPTIVE ASSOCIATIONS, not causal
-- evidence. Discounts are not assigned at random and may be applied to already
-- weak products/segments; margin mixed across product, segment, quantity, and
-- price effects. High-discount bands are sparse, so their margins are volatile:
-- read the reported line counts (sample sizes) alongside every margin.

-- ---------------------------------------------------------------------------
-- 1) Profitability by discount band.
--    Sample size (order_lines) is reported per band so sparse high-discount
--    bands can be interpreted cautiously.
-- ---------------------------------------------------------------------------
WITH banded AS (
    SELECT
        CASE
            WHEN "Discount" = 0                            THEN 0
            WHEN "Discount" > 0    AND "Discount" <= 0.10  THEN 1
            WHEN "Discount" > 0.10 AND "Discount" <= 0.20  THEN 2
            WHEN "Discount" > 0.20 AND "Discount" <= 0.30  THEN 3
            WHEN "Discount" > 0.30 AND "Discount" <= 0.40  THEN 4
            WHEN "Discount" > 0.40 AND "Discount" <= 0.50  THEN 5
            WHEN "Discount" > 0.50 AND "Discount" <= 0.60  THEN 6
            WHEN "Discount" > 0.60 AND "Discount" <= 0.70  THEN 7
            WHEN "Discount" > 0.70 AND "Discount" <= 0.80  THEN 8
            ELSE 99
        END AS band_order,
        "Order ID" AS order_id,
        "Quantity" AS quantity,
        "Discount" AS discount,
        "Sales"    AS sales,
        "Profit"   AS profit
    FROM orders
)
SELECT
    band_order,
    CASE band_order
        WHEN 0 THEN '0.00 (no discount)'
        WHEN 1 THEN '(0.00, 0.10]'
        WHEN 2 THEN '(0.10, 0.20]'
        WHEN 3 THEN '(0.20, 0.30]'
        WHEN 4 THEN '(0.30, 0.40]'
        WHEN 5 THEN '(0.40, 0.50]'
        WHEN 6 THEN '(0.50, 0.60]'
        WHEN 7 THEN '(0.60, 0.70]'
        WHEN 8 THEN '(0.70, 0.80]'
        ELSE 'out of range'
    END                                                     AS discount_band,
    MIN(discount)                                           AS band_discount_min,
    MAX(discount)                                           AS band_discount_max,
    COUNT(*)                                                AS order_lines,
    COUNT(DISTINCT order_id)                                AS orders,
    SUM(quantity)                                           AS units_sold,
    ROUND(SUM(sales), 2)                                    AS sales,
    ROUND(SUM(profit), 2)                                   AS profit,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0), 4)           AS profit_margin,
    ROUND(AVG(discount), 4)                                 AS avg_line_discount,
    ROUND(SUM(sales * discount) / NULLIF(SUM(sales), 0), 4) AS sales_weighted_discount_index,
    SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)             AS loss_making_lines,
    ROUND(SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) * 1.0
          / NULLIF(COUNT(*), 0), 4)                         AS loss_line_share
FROM banded
GROUP BY band_order
ORDER BY band_order;

-- ---------------------------------------------------------------------------
-- 2) Top 25 worst loss-making order lines (most negative Profit first).
--    Kept at order-line grain to show concrete evidence; it does not by itself
--    establish that the discount caused the loss.
-- ---------------------------------------------------------------------------
SELECT
    "Discount"                              AS discount,
    ROUND("Sales", 2)                       AS sales,
    "Quantity"                              AS quantity,
    ROUND("Profit", 2)                      AS profit,
    ROUND("Profit" / NULLIF("Sales", 0), 4) AS line_profit_margin,
    "Category"                              AS category,
    "Sub-Category"                          AS sub_category,
    "Product ID"                            AS product_id,
    "Order ID"                              AS order_id
FROM orders
WHERE "Profit" < 0
ORDER BY "Profit" ASC
LIMIT 25;

-- ---------------------------------------------------------------------------
-- 3) Discount intensity and discounted-vs-undiscounted profitability by
--    Sub-Category. This adds the discount lens only; absolute sub-category
--    profitability is covered in sql/04_product_profitability.sql.
-- ---------------------------------------------------------------------------
SELECT
    "Sub-Category"                                          AS sub_category,
    COUNT(*)                                                AS order_lines,
    SUM(CASE WHEN "Discount" > 0 THEN 1 ELSE 0 END)         AS discounted_lines,
    ROUND(SUM(CASE WHEN "Discount" > 0 THEN 1 ELSE 0 END) * 1.0
          / NULLIF(COUNT(*), 0), 4)                         AS discounted_line_share,
    ROUND(SUM("Sales" * "Discount") / NULLIF(SUM("Sales"), 0), 4) AS sales_weighted_discount_index,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4)       AS margin_overall,
    ROUND(SUM(CASE WHEN "Discount" = 0 THEN "Profit" END)
          / NULLIF(SUM(CASE WHEN "Discount" = 0 THEN "Sales" END), 0), 4) AS margin_undiscounted,
    ROUND(SUM(CASE WHEN "Discount" > 0 THEN "Profit" END)
          / NULLIF(SUM(CASE WHEN "Discount" > 0 THEN "Sales" END), 0), 4) AS margin_discounted
FROM orders
GROUP BY "Sub-Category"
ORDER BY discounted_line_share DESC;
