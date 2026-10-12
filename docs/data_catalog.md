[gold_layer_data_catalog.md](https://github.com/user-attachments/files/33344490/gold_layer_data_catalog.md)
# Gold Layer Data Catalog

**Data model:** Star schema  
**Layer:** Gold  
**Implementation:** SQL Server views  
**Purpose:** Provide business-friendly dimensions and a sales fact view for analytics and reporting.

> **Data type note:** `ROW_NUMBER()` returns `BIGINT` in SQL Server, so `customer_key` and `product_key` are `BIGINT`, not `INT`. For columns selected directly from Silver, the exact data type is inherited from the underlying Silver column. Confirm inherited types in the live database before treating this catalog as an authoritative schema reference.

---

## 1. `gold.dim_customers`

**Purpose:** Stores customer details enriched with demographic and geographic information from CRM and ERP sources.

| Column Name | Data Type | Description |
|---|---|---|
| `customer_key` | `BIGINT` | Query-generated surrogate key assigned using `ROW_NUMBER()` ordered by `cst_id`. |
| `customer_id` | Same as `silver.crm_cust_info.cst_id` (typically `INT`) | Customer identifier originating from CRM. |
| `customer_number` | Same as `silver.crm_cust_info.cst_key` | Business/customer number used to match CRM customers to ERP customer and location records. |
| `first_name` | Same as `silver.crm_cust_info.cst_firstname` | Customer's first name from CRM. |
| `last_name` | Same as `silver.crm_cust_info.cst_lastname` | Customer's last name from CRM. |
| `country` | Same as `silver.erp_loc_a101.CNTRY` | Customer country sourced from ERP location data; may be NULL when no location matches. |
| `birthdate` | Same as `silver.erp_cust_az12.BDATE` (typically `DATE`) | Customer birth date from ERP; may be NULL when no ERP customer or birthdate is available. |
| `gender` | Result type of the `CASE` expression (typically `NVARCHAR`) | Uses CRM gender when it is not `'n/a'`; otherwise falls back to ERP gender, defaulting to `'n/a'` if ERP gender is NULL. |
| `marital_status` | Same as `silver.crm_cust_info.cst_marital_status` | Standardized customer marital status from CRM. |
| `created_date` | Same as `silver.crm_cust_info.cst_create_date` | Date the customer record was created in CRM. |

**Sources:** `silver.crm_cust_info` (driving source), `silver.erp_cust_az12`, and `silver.erp_loc_a101`.

**Join behavior:** `LEFT JOIN` keeps CRM customer rows when ERP customer or location matches are missing.

**Important:** `customer_key` is calculated at query time. Because it uses `ROW_NUMBER()`, it is not a persistent key and can change when the underlying data or ordering changes.

---

## 2. `gold.dim_products`

**Purpose:** Provides a business-friendly product dimension enriched with ERP category, subcategory, and maintenance attributes. The view includes only products where `prd_end_dt IS NULL`.

| Column Name | Data Type | Description |
|---|---|---|
| `product_key` | `BIGINT` | Query-generated surrogate key assigned using `ROW_NUMBER()` ordered by product start date and product number. |
| `product_id` | Same as `silver.crm_prd_info.prd_id` (typically `INT`) | Source product identifier from CRM. |
| `product_number` | Same as `silver.crm_prd_info.prd_key` | Product business key used to identify and join the product across views. |
| `product_name` | Same as `silver.crm_prd_info.prd_nm` | Product name from CRM. |
| `category_id` | Same as `silver.crm_prd_info.cat_id` | Category identifier derived from the CRM product key and used to join to ERP category data. |
| `category` | Same as `silver.erp_px_cat_g1v2.CAT` | Product category from ERP; may be NULL if no category match exists. |
| `subcategory` | Same as `silver.erp_px_cat_g1v2.SUBCAT` | Product subcategory from ERP; may be NULL if no category match exists. |
| `maintenance` | Same as `silver.erp_px_cat_g1v2.MAINTENANCE` | Maintenance attribute from ERP category data. |
| `product_cost` | Same as `silver.crm_prd_info.prd_cost` | Product cost from CRM product data. |
| `product_line` | Same as `silver.crm_prd_info.prd_line` | Standardized product line, such as Mountain, Road, Other Sales, or Touring. |
| `start_date` | Same as `silver.crm_prd_info.prd_start_dt` (typically `DATE`) | Effective start date of the product record. |

**Sources:** `silver.crm_prd_info` (driving source) and `silver.erp_px_cat_g1v2`.

**Join behavior:** `LEFT JOIN` retains eligible CRM products even if ERP category information is missing.

**Filtering rule:** `WHERE pi.prd_end_dt IS NULL` excludes records with an end date. Confirm this matches the business definition of a current product.

---

## 3. `gold.fact_sales`

**Purpose:** Provides sales transaction measures and dates, with product and customer surrogate keys looked up from the Gold dimension views.

| Column Name | Data Type | Description |
|---|---|---|
| `order_number` | Same as `silver.crm_sales_details.sls_ord_num` | Source sales order number. Confirm transaction grain before treating this alone as unique. |
| `product_key` | `BIGINT`, nullable due to `LEFT JOIN` | Product surrogate key looked up using the product business key; NULL means no matching product dimension row was found. |
| `customer_key` | `BIGINT`, nullable due to `LEFT JOIN` | Customer surrogate key looked up using CRM customer ID; NULL means no matching customer dimension row was found. |
| `order_date` | Same as `silver.crm_sales_details.sls_order_dt` (typically `DATE`) | Date the order was placed. |
| `shipping_date` | Same as `silver.crm_sales_details.sls_ship_dt` (typically `DATE`) | Date the order was shipped. |
| `due_date` | Same as `silver.crm_sales_details.sls_due_dt` (typically `DATE`) | Due date associated with the order. |
| `sales_amount` | Same as `silver.crm_sales_details.sls_sales` | Sales amount recorded for the transaction. |
| `quantity` | Same as `silver.crm_sales_details.sls_quantity` (typically `INT`) | Quantity associated with the sales transaction. |
| `sls_price` | Same as `silver.crm_sales_details.sls_price` | Price value from the sales source; the view retains the source column name. |

**Sources:** `silver.crm_sales_details` (driving source), `gold.dim_products`, and `gold.dim_customers`.

**Join behavior:** Both dimensions are joined with `LEFT JOIN`, so sales rows remain present when product or customer lookups fail. The corresponding surrogate key is then NULL.

**Fact grain:** The view is intended to return one row per row in `silver.crm_sales_details`, subject to row multiplication if a dimension lookup key is not unique.

---

## Cross-view relationship summary

| Fact column | Dimension | Lookup condition |
|---|---|---|
| `gold.fact_sales.product_key` | `gold.dim_products.product_key` | `silver.crm_sales_details.sls_prd_key = gold.dim_products.product_number` |
| `gold.fact_sales.customer_key` | `gold.dim_customers.customer_key` | `silver.crm_sales_details.sls_cust_id = gold.dim_customers.customer_id` |

## Validation notes for the team

1. Verify inherited column types in the live database before publishing this catalog as an authoritative schema reference.
2. `ROW_NUMBER()` keys are generated at query time and are not guaranteed to remain stable across executions if source rows or ordering change.
3. Validate that each product business key and customer ID matches at most one row in its dimension view; otherwise fact rows can multiply during joins.
4. Confirm that filtering products with `prd_end_dt IS NULL` is the intended definition of a current product.
5. Review unmatched `product_key` and `customer_key` values in `gold.fact_sales`; they become NULL because of the `LEFT JOIN`s.
