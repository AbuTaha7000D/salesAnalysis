-- 08_customer_analysis.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only customer performance queries over the SQLite database
-- created by sql/01_create_database.sql and loaded by
-- scripts/load_superstore_db.py.
--
-- Grain: `orders` is order-line level (one row per product line). Measures sum
-- line rows, while orders are counted with COUNT(DISTINCT "Order ID"). `returns`
-- is order-level and is deliberately not joined here (joining would multiply
-- order lines, and `returns` carries no amount). `people` is not needed.
--
-- Definitions (consistent with sql/03_sales_trends.sql through
-- sql/07_returns_analysis.sql):
--   sales            = SUM("Sales")
--   profit           = SUM("Profit")
--   profit_margin    = SUM("Profit") / NULLIF(SUM("Sales"), 0)   (a group ratio,
--                      never an average of line-level margins)
--   orders           = COUNT(DISTINCT "Order ID")   (orders containing the customer)
--   units_sold       = SUM("Quantity")
--   avg_order_value  = SUM("Sales") / NULLIF(COUNT(DISTINCT "Order ID"), 0)
--   All divisions use NULLIF to return NULL instead of erroring on a zero
--   denominator. ROUND is presentation-only; ratios use unrounded sums.
--
-- Grouping: customers are grouped by `Customer ID`, NEVER by `Customer Name`
-- alone, because a name may map to more than one ID. The distinct-name count is
-- reported, and a name is shown only when exactly one distinct name exists;
-- otherwise it is labelled as ambiguous. Here one name ("Harry Olson") maps to
-- five Customer IDs, so the same displayed name reappears on several rows: the
-- name is not a unique customer key, and the Customer ID must be used to
-- identify a customer. (No Customer ID maps to multiple names, so no
-- ambiguous-name label is triggered in this dataset.)
--
-- Rows and dates: no rows are removed (the retained repeated `Order ID +
-- Product ID` cases and rows duplicated when ignoring `Row ID` remain), and no
-- date filter is applied, so future-dated order lines are preserved rather than
-- silently excluded. Canadian data is kept. Customer figures therefore cover
-- the whole dataset.
--
-- Interpretation limits: results are descriptive, not causal. Profitability is
-- whole-period and unadjusted for returns. A customer with low sales can show a
-- volatile margin or AOV, so high-margin/low-volume customers should be read
-- alongside the reported order counts. Distinct order counts are NOT additive
-- across customers: an order can contain lines attributed to more than one
-- Customer ID, so it is then counted once per such customer. In this dataset
-- two orders each span four Customer IDs, so the per-customer `orders` column
-- sums to 5,117 while the dataset holds 5,111 distinct orders. Each row's
-- `orders`, `profit_margin` and `avg_order_value` are still correct for that
-- Customer ID; only summing `orders` (or deriving an AOV from summed sales over
-- summed orders) across customers would over-/mis-count.

-- ---------------------------------------------------------------------------
-- 1) Customer performance, one row per "Customer ID", best sales first.
-- ---------------------------------------------------------------------------
WITH customer AS (
    SELECT
        "Customer ID"                                    AS customer_id,
        COUNT(DISTINCT "Customer Name")                  AS distinct_names,
        CASE
            WHEN COUNT(DISTINCT "Customer Name") = 1
            THEN MIN("Customer Name")
            ELSE '(ambiguous: ' || COUNT(DISTINCT "Customer Name") || ' names)'
        END                                              AS customer_name,
        COUNT(DISTINCT "Order ID")                       AS orders,
        SUM("Quantity")                                  AS units_sold,
        SUM("Sales")                                     AS sales,
        SUM("Profit")                                    AS profit
    FROM orders
    GROUP BY "Customer ID"
)
SELECT
    customer_id,
    distinct_names,
    customer_name,
    orders,
    units_sold,
    ROUND(sales, 2)                                      AS sales,
    ROUND(profit, 2)                                     AS profit,
    ROUND(profit / NULLIF(sales, 0), 4)                  AS profit_margin,
    ROUND(sales / NULLIF(orders, 0), 2)                  AS avg_order_value
FROM customer
ORDER BY sales DESC;

-- ---------------------------------------------------------------------------
-- 2) Top 25 customers by total sales, highest first, with a parallel profit
--    rank. Ranking by sales (not profit) keeps the comparison about revenue;
--    the parallel profit_rank exposes high-revenue, low-profit customers.
--    volume_vs_profit_gap = profit_rank - sales_rank (same definition as
--    sql/04): a positive value means the customer ranks better by sales than by
--    profit; a negative value means the customer ranks better by profit than by
--    sales.
-- ---------------------------------------------------------------------------
WITH customer AS (
    SELECT
        "Customer ID"                                    AS customer_id,
        COUNT(DISTINCT "Customer Name")                  AS distinct_names,
        CASE
            WHEN COUNT(DISTINCT "Customer Name") = 1
            THEN MIN("Customer Name")
            ELSE '(ambiguous: ' || COUNT(DISTINCT "Customer Name") || ' names)'
        END                                              AS customer_name,
        COUNT(DISTINCT "Order ID")                       AS orders,
        SUM("Sales")                                     AS sales,
        SUM("Profit")                                    AS profit
    FROM orders
    GROUP BY "Customer ID"
),
ranked AS (
    SELECT
        customer_id,
        distinct_names,
        customer_name,
        orders,
        sales,
        profit,
        RANK() OVER (ORDER BY sales DESC)  AS sales_rank,
        RANK() OVER (ORDER BY profit DESC) AS profit_rank
    FROM customer
)
SELECT
    sales_rank,
    profit_rank,
    (profit_rank - sales_rank)          AS volume_vs_profit_gap,
    customer_id,
    distinct_names,
    customer_name,
    orders,
    ROUND(sales, 2)                     AS sales,
    ROUND(profit, 2)                    AS profit,
    ROUND(profit / NULLIF(sales, 0), 4) AS profit_margin
FROM ranked
ORDER BY sales_rank
LIMIT 25;

-- ---------------------------------------------------------------------------
-- 3) Top 25 customers by total profit, highest first, with a parallel sales
--    rank. volume_vs_profit_gap = profit_rank - sales_rank (same definition as
--    sql/04): a positive value means the customer ranks better by sales than by
--    profit; a negative value means the customer ranks better by profit than by
--    sales.
-- ---------------------------------------------------------------------------
WITH customer AS (
    SELECT
        "Customer ID"                                    AS customer_id,
        COUNT(DISTINCT "Customer Name")                  AS distinct_names,
        CASE
            WHEN COUNT(DISTINCT "Customer Name") = 1
            THEN MIN("Customer Name")
            ELSE '(ambiguous: ' || COUNT(DISTINCT "Customer Name") || ' names)'
        END                                              AS customer_name,
        COUNT(DISTINCT "Order ID")                       AS orders,
        SUM("Sales")                                     AS sales,
        SUM("Profit")                                    AS profit
    FROM orders
    GROUP BY "Customer ID"
),
ranked AS (
    SELECT
        customer_id,
        distinct_names,
        customer_name,
        orders,
        sales,
        profit,
        RANK() OVER (ORDER BY profit DESC) AS profit_rank,
        RANK() OVER (ORDER BY sales DESC)  AS sales_rank
    FROM customer
)
SELECT
    profit_rank,
    sales_rank,
    (profit_rank - sales_rank)          AS volume_vs_profit_gap,
    customer_id,
    distinct_names,
    customer_name,
    orders,
    ROUND(profit, 2)                    AS profit,
    ROUND(sales, 2)                     AS sales,
    ROUND(profit / NULLIF(sales, 0), 4) AS profit_margin
FROM ranked
ORDER BY profit_rank
LIMIT 25;
