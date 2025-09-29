-- IMPORTING DATA

-- Setting up the table and importing data
CREATE TABLE online_retail (
    invoice_no VARCHAR(20),
    stock_code VARCHAR(20),
    description VARCHAR(255),
    quantity INT,
    invoice_date TIMESTAMP,
    unit_price NUMERIC(10, 2),
    customer_id INT,
    country VARCHAR(50)
);

COMMENT ON TABLE online_retail IS 'Contains transactional data from the online retail dataset for RFM analysis.';

COPY online_retail 
FROM 'D:\Online Retail.csv' 
WITH (FORMAT CSV, HEADER);


-- EXPLORING DATA

-- How many total rows are in the table?

SELECT COUNT(*) AS total_rows
FROM online_retail;

-- What is the date range of the transactions?

SELECT
    MIN(invoice_date) AS first_transaction,
    MAX(invoice_date) AS last_transaction
FROM online_retail;

-- How many unique invoices (orders) are there?

SELECT COUNT(DISTINCT invoice_no) AS total_orders
FROM online_retail;

-- How many unique customers are in the dataset?

SELECT COUNT(DISTINCT customer_id) AS unique_customers
FROM online_retail;

-- Who are the top 10 customers by total spending?

SELECT
    customer_id,
    ROUND(SUM(quantity * unit_price), 2) AS total_spent
FROM
    online_retail
GROUP BY
    customer_id
ORDER BY
    total_spent DESC
LIMIT 10;

-- What are the top 10 best-selling products by quantity?

SELECT
    stock_code,
    description,
    SUM(quantity) AS total_quantity_sold
FROM
    online_retail
GROUP BY
    stock_code, description
ORDER BY
    total_quantity_sold DESC
LIMIT 10;

-- What are the top 10 products by total revenue?

SELECT
    stock_code,
    description,
    ROUND(SUM(quantity * unit_price), 2) AS total_revenue
FROM
    online_retail
GROUP BY
    stock_code, description
ORDER BY
    total_revenue DESC
LIMIT 10;

-- How many orders were placed each month?

SELECT
    TO_CHAR(invoice_date, 'YYYY-MM') AS sales_month,
    COUNT(DISTINCT invoice_no) AS number_of_orders
FROM
    online_retail
GROUP BY
    sales_month
ORDER BY
    sales_month;
	
-- What was the total revenue per month?

SELECT
    TO_CHAR(invoice_date, 'YYYY-MM') AS sales_month,
    ROUND(SUM(quantity * unit_price), 2) AS monthly_revenue
FROM
    online_retail
GROUP BY
    sales_month
ORDER BY
    sales_month;

-- How many customers are there per country?

SELECT
    country,
    COUNT(DISTINCT customer_id) AS number_of_customers
FROM
    online_retail
GROUP BY
    country
ORDER BY
    number_of_customers DESC;

-- CLEANING DATA

START TRANSACTION;
BEGIN;

-- Removing all rows where the customer_id is NULL.
DELETE FROM online_retail
WHERE customer_id IS NULL;

-- Removing all rows with a negative or zero quantity.
DELETE FROM online_retail
WHERE quantity <= 0;

-- Removing any items that have a unit_price of zero.
DELETE FROM online_retail
WHERE unit_price <= 0;

-- Checking the result before committing:
SELECT COUNT(*) FROM online_retail;
SELECT * FROM online_retail LIMIT 100;

-- If you are satisfied with the changes, make them permanent.
COMMIT;


-- PERFORMING RFM ANALYSIS

WITH
-- Get the max invoice date once
max_date AS (
    SELECT MAX(CAST(invoice_date AS DATE)) AS max_dt
    FROM online_retail
),

-- Calculate Recency, Frequency, Monetary
rfm_raw AS (
    SELECT
        customer_id,
        m.max_dt - MAX(CAST(o.invoice_date AS DATE)) AS recency,
        COUNT(DISTINCT o.invoice_no) AS frequency,
        SUM(o.quantity * o.unit_price) AS monetary_value
    FROM
        online_retail o
        CROSS JOIN max_date m
    WHERE
        o.quantity > 0   -- exclude returns/cancellations
    GROUP BY
        customer_id, m.max_dt
),

-- Score customers 1–5
rfm_scored AS (
    SELECT
        customer_id,
        recency,
        frequency,
        monetary_value,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,       -- recent = high score
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
    FROM
        rfm_raw
)

-- Final segmentation
SELECT
    r.customer_id,
    r.recency,
    r.frequency,
    ROUND(r.monetary_value, 2) AS monetary_value,
    r.r_score,
    r.f_score,
    r.m_score,
    CONCAT(r.r_score, r.f_score, r.m_score) AS rfm_score,
    CASE
        WHEN r.r_score >= 4 AND r.f_score >= 4 AND r.m_score >= 4 THEN 'Champions'
        WHEN r.r_score >= 4 AND r.f_score >= 3 THEN 'Loyal Customers'
        WHEN r.r_score = 5 AND r.f_score <= 2 THEN 'New Customers'
        WHEN r.r_score >= 3 AND r.f_score >= 3 THEN 'Potential Loyalists'
        WHEN r.r_score = 3 AND r.f_score <= 2 THEN 'Need Attention'
        WHEN r.r_score = 2 AND r.f_score >= 3 THEN 'About to Sleep'
        WHEN r.r_score <= 2 AND r.f_score <= 2 AND r.m_score >= 2 THEN 'At Risk'
        WHEN r.r_score = 1 AND r.f_score = 1 AND r.m_score = 1 THEN 'Lost Customers'
        ELSE 'Other'
    END AS customer_segment
FROM
    rfm_scored r
ORDER BY
    r.customer_id;

