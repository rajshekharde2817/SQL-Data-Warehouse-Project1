/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Script Purpose:
    Performs data-quality checks against the Gold dimension and fact views
    in the data warehouse star schema.

    Checks include:
      - NULL and duplicate dimension identifiers
      - Dimension lookup-key uniqueness
      - Missing customer/product dimension lookups in the sales fact view
      - Unwanted spaces and invalid standardized values
      - Product current-record filtering
      - Sales row-count and measure consistency checks
      - Cross-view reconciliation

Usage:
    Run after deploying the Gold views and loading Silver.
    Review returned rows and investigate exceptions.

Important:
    These checks are read-only; they do not update or delete data.
    Some results are warnings and require business interpretation.
    ROW_NUMBER() surrogate keys in the current Gold views are generated at
    query time and are not guaranteed to be stable across executions.
===============================================================================
*/

SET NOCOUNT ON;

PRINT '===============================================================';
PRINT 'GOLD LAYER DATA QUALITY CHECKS';
PRINT '===============================================================';


/*=============================================================================
  1. CUSTOMER DIMENSION: gold.dim_customers
=============================================================================*/

PRINT '---------------------------------------------------------------';
PRINT 'Checking gold.dim_customers';
PRINT '---------------------------------------------------------------';

-- 1.1 Check for NULL customer IDs.
-- Expectation: No results if customer_id is mandatory.
SELECT *
FROM gold.dim_customers
WHERE customer_id IS NULL;

-- 1.2 Check for duplicate customer IDs.
-- Expectation: No results if one row per CRM customer is intended.
SELECT customer_id, COUNT(*) AS record_count
FROM gold.dim_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 1.3 Check for duplicate customer numbers.
-- Expectation: No results if customer_number is the unique business key.
SELECT customer_number, COUNT(*) AS record_count
FROM gold.dim_customers
WHERE customer_number IS NOT NULL
GROUP BY customer_number
HAVING COUNT(*) > 1;

-- 1.4 Check for NULL customer numbers.
-- Expectation: No results if customer_number is mandatory.
SELECT *
FROM gold.dim_customers
WHERE customer_number IS NULL;

-- 1.5 Check for unwanted leading/trailing spaces in names and number.
-- Expectation: No results.
SELECT *
FROM gold.dim_customers
WHERE (customer_number IS NOT NULL AND customer_number <> TRIM(customer_number))
   OR (first_name IS NOT NULL AND first_name <> TRIM(first_name))
   OR (last_name IS NOT NULL AND last_name <> TRIM(last_name));

-- 1.6 Check standardized gender values.
-- Expectation under current transformation: Male, Female, or n/a.
SELECT *
FROM gold.dim_customers
WHERE gender IS NULL
   OR gender NOT IN ('Male', 'Female', 'n/a');

-- 1.7 Check standardized marital status.
-- Expectation under current Silver transformation: Single, Married, or n/a.
SELECT *
FROM gold.dim_customers
WHERE marital_status IS NULL
   OR marital_status NOT IN ('Single', 'Married', 'n/a');

-- 1.8 Check multiple dimension rows for the same customer number.
-- This is another view-level uniqueness check; review if results appear.
SELECT customer_number, COUNT(*) AS record_count
FROM gold.dim_customers
GROUP BY customer_number
HAVING COUNT(*) > 1;


/*=============================================================================
  2. PRODUCT DIMENSION: gold.dim_products
=============================================================================*/

PRINT '---------------------------------------------------------------';
PRINT 'Checking gold.dim_products';
PRINT '---------------------------------------------------------------';

-- 2.1 Check for NULL product IDs.
SELECT *
FROM gold.dim_products
WHERE product_id IS NULL;

-- 2.2 Check for duplicate product IDs.
-- Expectation: No results if product_id uniquely identifies the product.
SELECT product_id, COUNT(*) AS record_count
FROM gold.dim_products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- 2.3 Check for NULL product numbers.
SELECT *
FROM gold.dim_products
WHERE product_number IS NULL;

-- 2.4 Check for duplicate product numbers.
-- Critical: the fact view uses product_number to look up product_key.
-- Expectation: No results, otherwise fact rows may multiply.
SELECT product_number, COUNT(*) AS record_count
FROM gold.dim_products
WHERE product_number IS NOT NULL
GROUP BY product_number
HAVING COUNT(*) > 1;

-- 2.5 Check for NULL product surrogate keys.
SELECT *
FROM gold.dim_products
WHERE product_key IS NULL;

-- 2.6 Check for unwanted spaces in product text.
SELECT *
FROM gold.dim_products
WHERE (product_number IS NOT NULL AND product_number <> TRIM(product_number))
   OR (product_name IS NOT NULL AND product_name <> TRIM(product_name))
   OR (product_line IS NOT NULL AND product_line <> TRIM(product_line));

-- 2.7 Check negative product costs.
-- Expectation depends on business rules; review any results.
SELECT *
FROM gold.dim_products
WHERE product_cost < 0;

-- 2.8 Check current-product filter.
-- The view definition uses WHERE prd_end_dt IS NULL.
-- Compare against the source rows eligible for the view.
SELECT p.*
FROM silver.crm_prd_info AS p
WHERE p.prd_end_dt IS NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM gold.dim_products AS gp
      WHERE gp.product_id = p.prd_id
  );

-- 2.9 Check category enrichment failures.
-- NULL category attributes may be legitimate or may indicate an unmatched ERP category.
SELECT *
FROM gold.dim_products
WHERE category_id IS NOT NULL
  AND category IS NULL;


/*=============================================================================
  3. SALES FACT: gold.fact_sales
=============================================================================*/

PRINT '---------------------------------------------------------------';
PRINT 'Checking gold.fact_sales';
PRINT '---------------------------------------------------------------';

-- 3.1 Check for NULL order numbers.
SELECT *
FROM gold.fact_sales
WHERE order_number IS NULL;

-- 3.2 Check for duplicate order numbers.
-- WARNING: an order may have multiple lines. Do not treat duplicates as errors
-- unless the business grain says one row per order_number.
SELECT order_number, COUNT(*) AS record_count
FROM gold.fact_sales
WHERE order_number IS NOT NULL
GROUP BY order_number
HAVING COUNT(*) > 1;

-- 3.3 Check missing product dimension lookups.
-- Expectation: No results if every sales product should be present in dim_products.
SELECT *
FROM gold.fact_sales
WHERE product_key IS NULL;

-- 3.4 Check missing customer dimension lookups.
-- Expectation: No results if every sales customer should be present in dim_customers.
SELECT *
FROM gold.fact_sales
WHERE customer_key IS NULL;

-- 3.5 Check missing order dates.
SELECT *
FROM gold.fact_sales
WHERE order_date IS NULL;

-- 3.6 Check shipment date before order date.
SELECT *
FROM gold.fact_sales
WHERE order_date IS NOT NULL
  AND shipping_date IS NOT NULL
  AND shipping_date < order_date;

-- 3.7 Check due date before order date.
SELECT *
FROM gold.fact_sales
WHERE order_date IS NOT NULL
  AND due_date IS NOT NULL
  AND due_date < order_date;

-- 3.8 Check NULL sales amounts or quantities.
-- Review according to the approved business rules.
SELECT *
FROM gold.fact_sales
WHERE sales_amount IS NULL
   OR quantity IS NULL;

-- 3.9 Check arithmetic consistency between sales, price, and quantity.
-- This is a diagnostic check only. Discounts, returns, and adjustments may
-- explain differences, so do not assume every mismatch is invalid.
SELECT *
FROM gold.fact_sales
WHERE sales_amount IS NOT NULL
  AND quantity IS NOT NULL
  AND sls_price IS NOT NULL
  AND sales_amount <> quantity * sls_price;

-- 3.10 Check negative sales amounts.
-- Informational: negative sales may represent returns or credits.
SELECT *
FROM gold.fact_sales
WHERE sales_amount < 0;


/*=============================================================================
  4. FACT-TO-DIMENSION RECONCILIATION
=============================================================================*/

PRINT '---------------------------------------------------------------';
PRINT 'Checking fact-to-dimension relationships';
PRINT '---------------------------------------------------------------';

-- 4.1 Verify fact row count equals Silver sales row count.
-- Expectation: Counts should match when the dimension joins do not multiply
-- rows and the fact view retains every Silver sales row.
SELECT
    (SELECT COUNT_BIG(*) FROM silver.crm_sales_details) AS silver_sales_rows,
    (SELECT COUNT_BIG(*) FROM gold.fact_sales) AS gold_fact_rows;

-- 4.2 Check sales source rows with no matching current product dimension row.
-- Historical products are excluded from dim_products by its current-product
-- filter, so results may be expected and should be interpreted accordingly.
SELECT sd.*
FROM silver.crm_sales_details AS sd
LEFT JOIN gold.dim_products AS dp
    ON sd.sls_prd_key = dp.product_number
WHERE dp.product_key IS NULL;

-- 4.3 Check sales source rows with no matching customer dimension row.
SELECT sd.*
FROM silver.crm_sales_details AS sd
LEFT JOIN gold.dim_customers AS dc
    ON sd.sls_cust_id = dc.customer_id
WHERE dc.customer_key IS NULL;


/*=============================================================================
  5. SURROGATE KEY AND VIEW BEHAVIOR NOTES
=============================================================================*/

PRINT '---------------------------------------------------------------';
PRINT 'Reviewing Gold view design assumptions';
PRINT '---------------------------------------------------------------';

-- 5.1 Check for duplicate customer IDs in the customer dimension.
-- Duplicate customer IDs may multiply fact rows during the customer join.
SELECT customer_id, COUNT(*) AS record_count
FROM gold.dim_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 5.2 Check for duplicate product numbers in the product dimension.
-- Duplicate product numbers may multiply fact rows during the product join.
SELECT product_number, COUNT(*) AS record_count
FROM gold.dim_products
GROUP BY product_number
HAVING COUNT(*) > 1;

-- Note:
-- customer_key and product_key are generated using ROW_NUMBER() in views.
-- They are query-generated values, not persistent keys. If stable surrogate
-- keys are required, consider persisted keys or a stable key strategy.


PRINT '===============================================================';
PRINT 'GOLD LAYER QUALITY CHECKS COMPLETED';
PRINT 'Review returned result sets and investigate exceptions.';
PRINT '===============================================================';
