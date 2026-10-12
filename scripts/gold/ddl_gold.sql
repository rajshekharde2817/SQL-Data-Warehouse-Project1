/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================
Script Purpose:
    This script creates views for the Gold layer in the data warehouse.
    The Gold layer represents the final dimension and fact views (Star Schema).

    Each view transforms and combines data from the Silver layer to produce
    a clean, enriched, and business-ready dataset.

Usage:
    These views can be queried directly for analytics and reporting.
===============================================================================
*/

-- ============================================================================
-- Create Dimension: gold.dim_customers
-- ============================================================================

PRINT '------------------------------------------------';
PRINT 'Creating View: gold.dim_customers';
PRINT '------------------------------------------------';

IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
    ci.cst_id AS customer_id,
    ci.cst_key AS customer_number,
    ci.cst_firstname AS first_name,
    ci.cst_lastname AS last_name,
    la.CNTRY AS country,
    ca.BDATE AS birthdate,
    CASE
        WHEN ci.cst_gndr <> 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.GEN, 'n/a')
    END AS gender,
    ci.cst_marital_status AS marital_status,
    ci.cst_create_date AS created_date
FROM silver.crm_cust_info AS ci
LEFT JOIN silver.erp_CUST_AZ12 AS ca
    ON ci.cst_key = ca.CID
LEFT JOIN silver.erp_LOC_A101 AS la
    ON ci.cst_key = la.CID;
GO


-- ============================================================================
-- Create Dimension: gold.dim_products
-- ============================================================================

PRINT '------------------------------------------------';
PRINT 'Creating View: gold.dim_products';
PRINT '------------------------------------------------';

IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY pi.prd_start_dt, pi.prd_key
    ) AS product_key,
    pi.prd_id AS product_id,
    pi.prd_key AS product_number,
    pi.prd_nm AS product_name,
    pi.cat_id AS category_id,
    pc.CAT AS category,
    pc.SUBCAT AS subcategory,
    pc.MAINTENANCE AS maintenance,
    pi.prd_cost AS product_cost,
    pi.prd_line AS product_line,
    pi.prd_start_dt AS start_date
FROM silver.crm_prd_info AS pi
LEFT JOIN silver.erp_PX_CAT_G1V2 AS pc
    ON pi.cat_id = pc.ID
WHERE pi.prd_end_dt IS NULL;
GO


-- ============================================================================
-- Create Fact View: gold.fact_sales
-- ============================================================================

PRINT '------------------------------------------------';
PRINT 'Creating View: gold.fact_sales';
PRINT '------------------------------------------------';

IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num AS order_number,
    dp.product_key,
    dc.customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt AS shipping_date,
    sd.sls_due_dt AS due_date,
    sd.sls_sales AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price
FROM silver.crm_sales_details AS sd
LEFT JOIN gold.dim_products AS dp
    ON sd.sls_prd_key = dp.product_number
LEFT JOIN gold.dim_customers AS dc
    ON sd.sls_cust_id = dc.customer_id;
GO


-- ============================================================================
-- Gold View Creation Completed
-- ============================================================================

PRINT '================================================';
PRINT 'Gold Layer Views Created Successfully';
PRINT '================================================';

-- Optional validation:
-- SELECT TOP (10) * FROM gold.dim_customers;
-- SELECT TOP (10) * FROM gold.dim_products;
-- SELECT TOP (10) * FROM gold.fact_sales;
