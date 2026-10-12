-- In this file we insert data into Silver tables applying different transformation logics.

-- Creating a store procedure to run

/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    Transforms and loads data from Bronze tables into Silver tables.

    Includes:
    - Truncating Silver tables before loading.
    - Logging each table's loading steps.
    - Measuring individual table load durations.
    - Measuring total batch duration.
    - Error handling with SQL Server error details.
Usage Example:
    EXEC silver.load_silver;
===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    --SET NOCOUNT ON; -- This suppresses the messages such as “(397 rows affected)” that normally 
	--appear after INSERT, UPDATE, and DELETE statements.

    DECLARE
        @start_time       DATETIME,
        @end_time         DATETIME,
        @batch_start_time DATETIME,
        @batch_end_time   DATETIME;

    BEGIN TRY

        SET @batch_start_time = GETDATE();

        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';


        /*================================================
          CRM TABLES
        =================================================*/

        PRINT '------------------------------------------------';
        PRINT 'Loading CRM Tables';
        PRINT '------------------------------------------------';


        /*-----------------------------------------------
          1. CRM CUSTOMER
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.crm_cust_info';

        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '>> Loading data into: silver.crm_cust_info';

        INSERT INTO silver.crm_cust_info
        (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,

            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'S'
                    THEN 'Single'
                WHEN UPPER(TRIM(cst_marital_status)) = 'M'
                    THEN 'Married'
                ELSE 'n/a'
            END AS cst_marital_status,

            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'F'
                    THEN 'Female'
                WHEN UPPER(TRIM(cst_gndr)) = 'M'
                    THEN 'Male'
                ELSE 'n/a'
            END AS cst_gndr,

            cst_create_date

        FROM
        (
            SELECT *,
                ROW_NUMBER() OVER
                (
                    PARTITION BY cst_id
                    ORDER BY cst_create_date DESC
                ) AS flag_last
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) AS t
        WHERE flag_last = 1;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + 'seconds';

        PRINT '>> -------------';


        /*-----------------------------------------------
          2. CRM PRODUCT
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.crm_prd_info';

        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '>> Loading data into: silver.crm_prd_info';

        INSERT INTO silver.crm_prd_info
        (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
            SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
            prd_nm,
            ISNULL(prd_cost, 0) AS prd_cost,

            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'n/a'
            END AS prd_line,

            CAST(prd_start_dt AS DATE) AS prd_start_dt,

            CAST(
                DATEADD(
                    DAY,
                    -1,
                    LEAD(prd_start_dt) OVER
                    (
                        PARTITION BY prd_key
                        ORDER BY prd_start_dt ASC
                    )
                )
                AS DATE
            ) AS prd_end_dt

        FROM bronze.crm_prd_info;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';

        PRINT '>> -------------';


        /*-----------------------------------------------
          3. CRM SALES DETAILS
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.crm_sales_details';

        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '>> Loading data into: silver.crm_sales_details';

        INSERT INTO silver.crm_sales_details
        (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,

            CASE
                WHEN sls_order_dt = 0
                  OR LEN(sls_order_dt) <> 8
                    THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR(50)) AS DATE)
            END AS sls_order_dt,

            CASE
                WHEN sls_ship_dt = 0
                  OR LEN(sls_ship_dt) <> 8
                    THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR(50)) AS DATE)
            END AS sls_ship_dt,

            CASE
                WHEN sls_due_dt = 0
                  OR LEN(sls_due_dt) <> 8
                    THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR(50)) AS DATE)
            END AS sls_due_dt,

            -- Existing sales transformation logic
            CASE
                WHEN sls_sales IS NULL
                  OR sls_sales <= 0
                  OR sls_sales <> ABS(sls_price) * sls_quantity
                    THEN ABS(sls_price) * sls_quantity
                ELSE sls_sales
            END AS sls_sales,

            sls_quantity,

            CASE
                WHEN sls_price IS NULL
                  OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS sls_price

        FROM bronze.crm_sales_details;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';

        PRINT '>> -------------';


        /*================================================
          ERP TABLES
        =================================================*/

        PRINT '------------------------------------------------';
        PRINT 'Loading ERP Tables';
        PRINT '------------------------------------------------';


        /*-----------------------------------------------
          4. ERP CUSTOMER
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.erp_cust_az12';

        TRUNCATE TABLE silver.erp_cust_az12;

        PRINT '>> Loading data into: silver.erp_cust_az12';

        INSERT INTO silver.erp_cust_az12
        (
            CID,
            BDATE,
            GEN
        )
        SELECT
            CASE
                WHEN CID LIKE 'NAS%'
                    THEN SUBSTRING(CID, 4, LEN(CID))
                ELSE CID
            END AS CID,

            CASE
                WHEN BDATE > GETDATE() THEN NULL
                ELSE BDATE
            END AS BDATE,

            CASE
                WHEN UPPER(TRIM(GEN)) IN ('F', 'FEMALE')
                    THEN 'Female'
                WHEN UPPER(TRIM(GEN)) IN ('M', 'MALE')
                    THEN 'Male'
                ELSE 'n/a'
            END AS GEN

        FROM bronze.erp_cust_az12;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';

        PRINT '>> -------------';


        /*-----------------------------------------------
          5. ERP LOCATION
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.erp_loc_a101';

        TRUNCATE TABLE silver.erp_loc_a101;

        PRINT '>> Loading data into: silver.erp_loc_a101';

        INSERT INTO silver.erp_loc_a101
        (
            CID,
            CNTRY
        )
        SELECT
            REPLACE(CID, '-', '') AS CID,

            CASE
                WHEN UPPER(TRIM(CNTRY)) IN ('USA', 'US')
                    THEN 'Unitest States'
                WHEN UPPER(TRIM(CNTRY)) = 'DE'
                    THEN ' Germany'
                WHEN UPPER(TRIM(CNTRY)) = ' '
                  OR CNTRY IS NULL
                    THEN 'n/a'
                ELSE TRIM(CNTRY)
            END AS CNTRY

        FROM bronze.erp_loc_a101;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';

        PRINT '>> -------------';


        /*-----------------------------------------------
          6. ERP PRODUCT CATEGORY
        -----------------------------------------------*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating table: silver.erp_px_cat_g1v2';

        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        PRINT '>> Loading data into: silver.erp_px_cat_g1v2';

        INSERT INTO silver.erp_px_cat_g1v2
        (
            ID,
            CAT,
            SUBCAT,
            MAINTENANCE
        )
        SELECT
            ID,
            CAT,
            SUBCAT,
            MAINTENANCE
        FROM bronze.erp_px_cat_g1v2;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';

        PRINT '>> -------------';


        /*================================================
          BATCH COMPLETION
        =================================================*/

        SET @batch_end_time = GETDATE();

        PRINT '================================================';
        PRINT 'Loading Silver Layer is Completed';
        PRINT 'Total Load Duration: '
            + CAST(
                DATEDIFF(SECOND, @batch_start_time, @batch_end_time)
                AS NVARCHAR(20)
              )
            + ' seconds';
        PRINT '================================================';

    END TRY

    BEGIN CATCH

        SET @batch_end_time = GETDATE();

        PRINT '================================================';
        PRINT 'ERROR OCCURRED DURING LOADING SILVER LAYER';
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: '
            + CAST(ERROR_NUMBER() AS NVARCHAR(20));
        PRINT 'Error State: '
            + CAST(ERROR_STATE() AS NVARCHAR(20));
        PRINT 'Error Line: '
            + CAST(ERROR_LINE() AS NVARCHAR(20));
        PRINT 'Elapsed Time Before Error: '
            + CAST(
                DATEDIFF(SECOND, @batch_start_time, @batch_end_time)
                AS NVARCHAR(20)
              )
            + ' seconds';
        PRINT '================================================';

        -- Return the failure to the calling session or job.
        THROW;

    END CATCH
END;


