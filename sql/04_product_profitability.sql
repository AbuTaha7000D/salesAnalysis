-- 04_product_profitability.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only product/category profitability queries over the SQLite
-- database created by sql/01_create_database.sql and loaded by
-- scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line). Measures sum
-- line rows, while orders are counted with COUNT(DISTINCT "Order ID"). `returns`
-- is order-level and is deliberately not joined here (joining would multiply
-- order lines, and `returns` carries no amount). `people` is not needed.
--
-- Definitions (consistent with sql/03_sales_trends.sql):
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / SUM("Sales")   (a period ratio, not an
--                      average of row-level margins)
--   orders           = COUNT(DISTINCT "Order ID")      (orders containing the group)
--   units_sold       = SUM("Quantity")
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Rows and dates: no rows are removed (the retained repeated `Order ID +
-- Product ID` cases and rows duplicated when ignoring `Row ID` remain), and no
-- date filter is applied, so future-dated order lines are preserved rather than
-- silently excluded. Product/category figures therefore cover the whole dataset.
--
-- Product-name ambiguity: `Product ID` and `Product Name` are not 1:1 (some IDs
-- map to more than one name and vice versa), so products are grouped by
-- `Product ID`, the distinct-name count is reported, and a name is shown only
-- when exactly one distinct name exists; otherwise the name is labelled as
-- ambiguous. Do not treat the displayed name as a canonical mapping.
--
-- Interpretation limits: results are descriptive, not causal. Profitability is
-- whole-period and unadjusted for returns. A product/category with low sales can
-- show a volatile margin, so margins are only comparable above a stated sales
-- floor.

-- ---------------------------------------------------------------------------
-- 1) Category profitability.
-- ---------------------------------------------------------------------------
SELECT
    "Category"                                        AS category,
    COUNT(DISTINCT "Product ID")                      AS products,
    COUNT(DISTINCT "Order ID")                        AS orders,
    SUM("Quantity")                                   AS units_sold,
    ROUND(SUM("Sales"), 2)                            AS sales,
    ROUND(SUM("Profit"), 2)                           AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4) AS profit_margin,
    SUM(CASE WHEN "Profit" < 0 THEN 1 ELSE 0 END)     AS loss_making_lines
FROM orders
GROUP BY "Category"
ORDER BY profit DESC;

-- ---------------------------------------------------------------------------
-- 2) Sub-category profitability, weakest profit first.
-- ---------------------------------------------------------------------------
SELECT
    "Category"                                        AS category,
    "Sub-Category"                                    AS sub_category,
    COUNT(DISTINCT "Product ID")                      AS products,
    COUNT(DISTINCT "Order ID")                        AS orders,
    SUM("Quantity")                                   AS units_sold,
    ROUND(SUM("Sales"), 2)                            AS sales,
    ROUND(SUM("Profit"), 2)                           AS profit,
    ROUND(SUM("Profit") / NULLIF(SUM("Sales"), 0), 4) AS profit_margin,
    SUM(CASE WHEN "Profit" < 0 THEN 1 ELSE 0 END)     AS loss_making_lines
FROM orders
GROUP BY "Category", "Sub-Category"
ORDER BY profit ASC;

-- ---------------------------------------------------------------------------
-- 3) Top 25 products by absolute profit, with a parallel sales-volume rank.
--    Products are grouped by "Product ID". Ranking by profit (not sales) keeps
--    the comparison about profitability; the parallel sales_rank exposes
--    high-volume, low-profit products. "volume_vs_profit_gap" > 0 means the
--    product ranks better on sales than on profit.
--
--    profit_margin_comparable applies an arbitrary reporting cutoff of
--    sales >= 1000: this is a presentation choice to avoid volatile margins on
--    tiny sales, NOT a statistically validated threshold. Change it freely.
-- ---------------------------------------------------------------------------
WITH product AS (
    SELECT
        "Product ID"                                     AS product_id,
        COUNT(DISTINCT "Product Name")                   AS distinct_names,
        CASE
            WHEN COUNT(DISTINCT "Product Name") = 1
            THEN MIN("Product Name")
            ELSE '(ambiguous: ' || COUNT(DISTINCT "Product Name") || ' names)'
        END                                              AS product_name,
        MIN("Category")                                  AS category,
        MIN("Sub-Category")                              AS sub_category,
        COUNT(DISTINCT "Order ID")                       AS orders,
        SUM("Quantity")                                  AS units_sold,
        SUM("Sales")                                     AS sales,
        SUM("Profit")                                    AS profit
    FROM orders
    GROUP BY "Product ID"
),
ranked AS (
    SELECT
        product_id,
        distinct_names,
        product_name,
        category,
        sub_category,
        orders,
        units_sold,
        sales,
        profit,
        RANK() OVER (ORDER BY profit DESC) AS profit_rank,
        RANK() OVER (ORDER BY sales DESC)  AS sales_rank
    FROM product
)
SELECT
    profit_rank,
    sales_rank,
    (profit_rank - sales_rank)          AS volume_vs_profit_gap,
    product_id,
    distinct_names,
    product_name,
    category,
    sub_category,
    orders,
    units_sold,
    ROUND(sales, 2)                     AS sales,
    ROUND(profit, 2)                    AS profit,
    ROUND(profit / NULLIF(sales, 0), 4) AS profit_margin,
    CASE
        WHEN sales >= 1000
        THEN ROUND(profit / NULLIF(sales, 0), 4)
        ELSE NULL
    END                                 AS profit_margin_comparable
FROM ranked
ORDER BY profit_rank
LIMIT 25;

-- ---------------------------------------------------------------------------
-- 4) Top 25 loss-making products, worst absolute profit first.
-- ---------------------------------------------------------------------------
WITH product AS (
    SELECT
        "Product ID"                                     AS product_id,
        COUNT(DISTINCT "Product Name")                   AS distinct_names,
        CASE
            WHEN COUNT(DISTINCT "Product Name") = 1
            THEN MIN("Product Name")
            ELSE '(ambiguous: ' || COUNT(DISTINCT "Product Name") || ' names)'
        END                                              AS product_name,
        MIN("Category")                                  AS category,
        MIN("Sub-Category")                              AS sub_category,
        COUNT(DISTINCT "Order ID")                       AS orders,
        SUM("Quantity")                                  AS units_sold,
        SUM("Sales")                                     AS sales,
        SUM("Profit")                                    AS profit
    FROM orders
    GROUP BY "Product ID"
)
SELECT
    product_id,
    distinct_names,
    product_name,
    category,
    sub_category,
    orders,
    units_sold,
    ROUND(sales, 2)                     AS sales,
    ROUND(profit, 2)                    AS profit,
    ROUND(profit / NULLIF(sales, 0), 4) AS profit_margin
FROM product
WHERE profit < 0
ORDER BY profit ASC
LIMIT 25;
