-- 02_validate_database.sql
-- Superstore Sales & Profitability Analysis
--
-- Purpose: read-only validation queries for the SQLite database created by
-- sql/01_create_database.sql and loaded by scripts/load_superstore_db.py.
--
-- Each statement below is a SELECT that returns a single result set with a check
-- name, the expected value, the actual value, and a status. Status is 'PASS' or
-- 'FAIL' for checks, and 'INFO' for the statements that only list schema details
-- (those are not tests). No statement modifies data.
--
-- Reference counts expected from the processed CSV files:
--   orders  = 10194 rows
--   people  = 4 rows
--   returns = 296 rows
--   distinct "Order ID" in orders = 5111

-- Row counts for all three tables.
SELECT 'row_count_orders' AS check_name, 10194 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 10194 THEN 'PASS' ELSE 'FAIL' END AS status
FROM orders
UNION ALL
SELECT 'row_count_people', 4, COUNT(*),
       CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END
FROM people
UNION ALL
SELECT 'row_count_returns', 296, COUNT(*),
       CASE WHEN COUNT(*) = 296 THEN 'PASS' ELSE 'FAIL' END
FROM returns;

-- Column count of the orders table.
SELECT 'order_column_count' AS check_name, 21 AS expected,
       (SELECT COUNT(*) FROM pragma_table_info('orders')) AS actual,
       CASE WHEN (SELECT COUNT(*) FROM pragma_table_info('orders')) = 21 THEN 'PASS' ELSE 'FAIL' END AS status;

-- "Row ID" must be unique across all order lines.
SELECT 'row_id_unique' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT "Row ID") AS distinct_row_id,
       CASE WHEN COUNT(*) = COUNT(DISTINCT "Row ID") THEN 'PASS' ELSE 'FAIL' END AS status
FROM orders;

-- Distinct order count is lower than the line count because orders have multiple lines.
SELECT 'distinct_order_count' AS check_name, 5111 AS expected,
       COUNT(DISTINCT "Order ID") AS actual,
       CASE WHEN COUNT(DISTINCT "Order ID") = 5111 THEN 'PASS' ELSE 'FAIL' END AS status
FROM orders;

-- "Order ID" in returns must be unique (returns is an order-level table).
SELECT 'returns_order_id_unique' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT "Order ID") AS distinct_order_id,
       CASE WHEN COUNT(*) = COUNT(DISTINCT "Order ID") THEN 'PASS' ELSE 'FAIL' END AS status
FROM returns;

-- Every returned order must exist in orders.
SELECT 'returns_without_matching_order' AS check_name, 0 AS expected,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM returns
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE orders."Order ID" = returns."Order ID");

-- Every order region must be covered by the people reference table.
SELECT 'order_regions_missing_in_people' AS check_name, 0 AS expected,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (SELECT DISTINCT "Region" AS order_region FROM orders WHERE "Region" IS NOT NULL) AS order_regions
WHERE NOT EXISTS (SELECT 1 FROM people WHERE people."Region" = order_regions.order_region);

-- Postal Code must be stored as text.
SELECT 'postal_code_storage_type' AS check_name, 'text' AS expected,
       GROUP_CONCAT(DISTINCT typeof("Postal Code")) AS actual,
       CASE WHEN SUM(CASE WHEN typeof("Postal Code") <> 'text' THEN 1 ELSE 0 END) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM orders;

-- Numeric measures must remain numeric (Sales/Profit/Discount real, Quantity integer).
SELECT 'numeric_storage_types' AS check_name,
       'Sales=real, Profit=real, Discount=real, Quantity=integer' AS expected,
       'Sales=' || (SELECT GROUP_CONCAT(DISTINCT typeof("Sales")) FROM orders) ||
       ', Profit=' || (SELECT GROUP_CONCAT(DISTINCT typeof("Profit")) FROM orders) ||
       ', Discount=' || (SELECT GROUP_CONCAT(DISTINCT typeof("Discount")) FROM orders) ||
       ', Quantity=' || (SELECT GROUP_CONCAT(DISTINCT typeof("Quantity")) FROM orders) AS actual,
       CASE WHEN (SELECT COUNT(*) FROM orders
                  WHERE typeof("Sales") <> 'real'
                     OR typeof("Profit") <> 'real'
                     OR typeof("Discount") <> 'real'
                     OR typeof("Quantity") <> 'integer') = 0 THEN 'PASS' ELSE 'FAIL' END AS status;

-- Order and ship dates must already be ISO calendar dates (YYYY-MM-DD).
SELECT 'date_format_iso' AS check_name, 0 AS expected,
       SUM(CASE WHEN "Order Date" NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                 OR "Ship Date"  NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                THEN 1 ELSE 0 END) AS actual,
       CASE WHEN SUM(CASE WHEN "Order Date" NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                            OR "Ship Date"  NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                           THEN 1 ELSE 0 END) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM orders;

-- The orders."Region" foreign key must be defined to people."Region".
SELECT 'orders_region_fk_defined' AS check_name, 1 AS expected,
       (SELECT COUNT(*) FROM pragma_foreign_key_list('orders')
         WHERE "table" = 'people' AND "to" = 'Region') AS actual,
       CASE WHEN (SELECT COUNT(*) FROM pragma_foreign_key_list('orders')
                   WHERE "table" = 'people' AND "to" = 'Region') >= 1
            THEN 'PASS' ELSE 'FAIL' END AS status;

-- No foreign-key violations may exist in the data.
SELECT 'foreign_key_violations' AS check_name, 0 AS expected,
       (SELECT COUNT(*) FROM pragma_foreign_key_check) AS actual,
       CASE WHEN (SELECT COUNT(*) FROM pragma_foreign_key_check) = 0
            THEN 'PASS' ELSE 'FAIL' END AS status;

-- Column names for each table, in creation order.
SELECT 'orders_columns' AS check_name,
       'Row ID, Order ID, Order Date, Ship Date, Ship Mode, Customer ID, Customer Name, Segment, Country/Region, City, State/Province, Postal Code, Region, Product ID, Category, Sub-Category, Product Name, Sales, Quantity, Discount, Profit' AS expected,
       (SELECT GROUP_CONCAT(name, ', ') FROM pragma_table_info('orders')) AS actual,
       'INFO' AS status;

SELECT 'people_columns' AS check_name,
       'Regional Manager, Region' AS expected,
       (SELECT GROUP_CONCAT(name, ', ') FROM pragma_table_info('people')) AS actual,
       'INFO' AS status;

SELECT 'returns_columns' AS check_name,
       'Order ID, Returned' AS expected,
       (SELECT GROUP_CONCAT(name, ', ') FROM pragma_table_info('returns')) AS actual,
       'INFO' AS status;
