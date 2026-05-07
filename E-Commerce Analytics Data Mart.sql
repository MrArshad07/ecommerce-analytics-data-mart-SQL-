

-- Create schema first
CREATE SCHEMA IF NOT EXISTS public ;

-- Customers Table
CREATE TABLE dim_customers(
    customer_key INT,
    customer_id INT,
    customer_number VARCHAR(50),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    country VARCHAR(50),
    marital_status VARCHAR(50),
    gender VARCHAR(50),
    birthdate DATE,
    create_date DATE
);

-- Products Table
CREATE TABLE dim_products(
    product_key INT,
    product_id INT,
    product_number VARCHAR(50),
    product_name VARCHAR(50),
    category_id VARCHAR(50),
    category VARCHAR(50),
    subcategory VARCHAR(50),
    maintenance VARCHAR(50),
    cost INT,
    product_line VARCHAR(50),
    start_date DATE
);

-- Sales Table
CREATE TABLE fact_sales(
    order_number VARCHAR(50),
    product_key INT,
    customer_key INT,
    order_date DATE,
    shipping_date DATE,
    due_date DATE,
    sales_amount INT,
    quantity SMALLINT,
    price INT
);


-- =========================================================
-- Yearly Sales Summary
-- Purpose: Analyze total sales and quantity per year
-- =========================================================
SELECT DATE_PART('year', order_date) AS order_year,
       SUM(sales_amount) AS total_sales,
	   sum(quantity) as total_quantity
FROM fact_sales
GROUP BY order_year
ORDER BY order_year;


-- =========================================================
-- Monthly Sales Trend + Running Total
-- Purpose: Shows monthly sales and cumulative growth over time
-- =========================================================
SELECT 
    month,
    total_sales,
    SUM(total_sales) OVER (ORDER BY month) AS running_total
FROM (
    SELECT 
        DATE_TRUNC('month', order_date) AS month,
        SUM(sales_amount) AS total_sales
    FROM fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATE_TRUNC('month', order_date)
) t
ORDER BY month;


-- =========================================================
-- Yearly Sales by Product
-- Purpose: Analyze how each product performs yearly
-- =========================================================
SELECT
    DATE_TRUNC('year', f.order_date) AS year, 
    SUM(f.sales_amount) AS current_sales,
    p.product_name
FROM fact_sales AS f
JOIN dim_products p 
    ON f.product_key = p.product_key
WHERE f.order_date IS NOT NULL
GROUP BY year, p.product_name;

-- =========================================================
-- Category Sales Contribution Analysis
-- Purpose: Shows total sales per category and its % contribution
-- =========================================================
WITH category_sales AS (
    SELECT 
        p.category,
        SUM(f.sales_amount) AS total_sales
    FROM dim_products AS p
    JOIN fact_sales AS f
        ON p.product_key = f.product_key
    GROUP BY p.category
)
SELECT 
    p.category,
    total_sales,
    SUM(total_sales) OVER () AS overall_sales,
    CONCAT(
        ROUND(
            (total_sales * 100.0 / SUM(total_sales) OVER ())::numeric, 
            2
        ), 
        '%'
    ) AS percentage_total
FROM category_sales p
ORDER BY total_sales DESC;


/*Group customers into three segments based on their spending behavior:
	- VIP: Customers with at least 12 months of history and spending more than €5,000.
	- Regular: Customers with at least 12 months of history but spending €5,000 or less.
	- New: Customers with a lifespan less than 12 months.
And find the total number of customers by each group
*/
WITH customer_spending AS (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spending,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order,

        (
            DATE_PART('year', AGE(MAX(order_date), MIN(order_date))) * 12
            +
            DATE_PART('month', AGE(MAX(order_date), MIN(order_date)))
        ) AS lifespan

    FROM fact_sales f
    LEFT JOIN dim_customers c
        ON f.customer_key = c.customer_key
    GROUP BY c.customer_key
)

SELECT 
    customer_segment,
    COUNT(customer_key) AS total_customers

FROM (
    SELECT 
        customer_key,

        CASE 
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment

    FROM customer_spending
) AS segmented_customers

GROUP BY customer_segment
ORDER BY total_customers DESC;


/*
===============================================================================
Customer Report
===============================================================================
Purpose:
    - This report consolidates key customer metrics and behaviors

Highlights:
    1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
    3. Aggregates customer-level metrics:
	   - total orders
	   - total sales
	   - total quantity purchased
	   - total products
	   - lifespan (in months)
    4. Calculates valuable KPIs:
	    - recency (months since last order)
		- average order value
		- average monthly spend
===============================================================================
*/

-- =============================================================================
-- Create Report: report_customers
CREATE VIEW report_customers AS
WITH base_query AS (

-- 1) Base Query
SELECT
    f.order_number,
    f.product_key,
    f.order_date,
    f.sales_amount,
    f.quantity,

    c.customer_key,
    c.customer_number,

    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,

    DATE_PART('year', AGE(CURRENT_DATE, c.birthdate)) AS age

FROM fact_sales f

LEFT JOIN dim_customers c
    ON c.customer_key = f.customer_key

WHERE order_date IS NOT NULL
),

customer_aggregation AS (

/*---------------------------------------------------------------------------
2) Customer Aggregations
---------------------------------------------------------------------------*/

SELECT 
    customer_key,
    customer_number,
    customer_name,
    age,

    COUNT(DISTINCT order_number) AS total_orders,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    COUNT(DISTINCT product_key) AS total_products,

    MAX(order_date) AS last_order_date,

    (
        DATE_PART('year', AGE(MAX(order_date), MIN(order_date))) * 12
        +
        DATE_PART('month', AGE(MAX(order_date), MIN(order_date)))
    ) AS lifespan

FROM base_query

GROUP BY 
    customer_key,
    customer_number,
    customer_name,
    age
)

SELECT
    customer_key,
    customer_number,
    customer_name,
    age,

    CASE 
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and above'
    END AS age_group,

    CASE 
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,

    last_order_date,

    (
        DATE_PART('year', AGE(CURRENT_DATE, last_order_date)) * 12
        +
        DATE_PART('month', AGE(CURRENT_DATE, last_order_date))
    ) AS recency,

    total_orders,
    total_sales,
    total_quantity,
    total_products,
    lifespan,

-- Compute average order value (AOV)

    CASE 
        WHEN total_orders = 0 THEN 0
        ELSE total_sales / total_orders
    END AS avg_order_value,

-- Compute average monthly spend

    CASE 
        WHEN lifespan = 0 THEN total_sales
        ELSE total_sales / lifespan
    END AS avg_monthly_spend

FROM customer_aggregation;


/*
===============================================================================
Product Report
===============================================================================
Purpose:
    - This report consolidates key product metrics and behaviors.

Highlights:
    1. Gathers essential fields such as product name, category, subcategory, and cost.
    2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers.
    3. Aggregates product-level metrics:
       - total orders
       - total sales
       - total quantity sold
       - total customers (unique)
       - lifespan (in months)
    4. Calculates valuable KPIs:
       - recency (months since last sale)
       - average order revenue (AOR)
       - average monthly revenue
===============================================================================
*/
-- =============================================================================
-- Create Report: gold.report_products
-- =============================================================================

CREATE VIEW report_products AS

WITH base_query AS (

    SELECT
        f.order_number,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,

        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost

    FROM fact_sales f

    LEFT JOIN dim_products p
        ON f.product_key = p.product_key

    WHERE f.order_date IS NOT NULL
),

product_aggregations AS (

    SELECT
        product_key,
        product_name,
        category,
        subcategory,
        cost,

        -- lifespan in months
        (
            DATE_PART('year', AGE(MAX(order_date), MIN(order_date))) * 12 +
            DATE_PART('month', AGE(MAX(order_date), MIN(order_date)))
        ) AS lifespan,

        MAX(order_date) AS last_sale_date,

        COUNT(DISTINCT order_number) AS total_orders,
        COUNT(DISTINCT customer_key) AS total_customers,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity,

        ROUND(
            AVG(CASE 
                    WHEN quantity = 0 THEN NULL
                    ELSE sales_amount::numeric / quantity
                END),
            1
        ) AS avg_selling_price

    FROM base_query

    GROUP BY
        product_key,
        product_name,
        category,
        subcategory,
        cost
)

SELECT 
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,

    -- recency in months
    (
        DATE_PART('year', AGE(CURRENT_DATE, last_sale_date)) * 12 +
        DATE_PART('month', AGE(CURRENT_DATE, last_sale_date))
    ) AS recency_in_months,

    CASE
        WHEN total_sales > 50000 THEN 'High-Performer'
        WHEN total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END AS product_segment,

    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,

    -- Average Order Revenue (AOR)
    CASE 
        WHEN total_orders = 0 THEN 0
        ELSE total_sales / total_orders
    END AS avg_order_revenue,

    -- Average Monthly Revenue
    CASE
        WHEN lifespan = 0 THEN total_sales
        ELSE total_sales / lifespan
    END AS avg_monthly_revenue

FROM product_aggregations;

select*from report_products