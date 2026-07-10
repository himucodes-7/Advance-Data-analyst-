USE DataWarehouseAnalytics -- first Execut this line when you work in this query page 
/*

Customer Report

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
		- average monthly spend */

/* 
1) Base Query : Retrive core column from tables
*/

-- =============================================================================
IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL
    DROP VIEW gold.report_customers;

GO
CREATE VIEW gold.report_customers AS 

WITH base_query AS (
--1) Base Query : Retrive core column from tables
	SELECT
		s.order_number as order_number,
		s.product_key,
		p.product_name,
		s.order_date,
		s.sales_amount ,
		s.quantity as quantity,
		c.customer_key as customer_key,
		c.customer_number,
		CONCAT(c.first_name,' ',c.last_name) as customer_name,
		DATEDIFF(year,c.birthdate,GETDATE()) as age  
	
	FROM gold.fact_sales as s
	LEFT JOIN gold.dim_customers as c
	on s.customer_key = c.customer_key
	LEFT JOIN gold.dim_products as p
	ON s.product_key = p.product_key
	WHERE order_date IS NOT NULL 
)

/* 
3. Aggregates customer-level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan (in months)
		- last order of customer */

, customer_aggregation as (
	SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
	count(distinct order_number) as total_order,
	SUM(quantity) as quantity,
	SUM(sales_amount) as sales_amount,
	COUNT(product_key) as total_product,
	DATEDIFF(month,MIN(order_date),MAX(order_date)) as life_span,
	MAX(order_date) as last_order 
	from base_query  
	GROUP BY 
			customer_key,
			customer_number,
			customer_name,
			age
)
/*
2. Segments customers into categories (VIP, Regular, New) and age groups.
*/
SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
		CASE 
				WHEN age < 20 THEN 'Under 20'
				WHEN age between 20 and 29 THEN '20-29'
				WHEN age between 30 and 39 THEN '30-39'
				WHEN age between 40 and 49 THEN '40-49'
				ELSE '50 and above'
		END AS age_group,
		CASE 
			WHEN life_span >= 12 AND sales_amount > 5000 THEN 'VIP'
			WHEN life_span >= 12 AND sales_amount <= 5000 THEN 'Regular'
			ELSE 'New'
		END AS customer_segment,
	total_order,
	quantity,
	sales_amount,
	FORMAT(GETDATE(), 'MMMM yyyy') as current_month,
	FORMAT(last_order,'MMMM yyyy') as last_order_month ,
	-- - recency (months since last order)----v 
	DATEDIFF(MONTH,last_order,getdate())as regency,
	total_product,
	-- average order value
	

	CASE
		WHEN sales_amount = 0 THEN 0 
		ELSE sales_amount / total_order 
	END AS avg_order_value,
	life_span,
	-- average monthly spend\
	case 
		WHEN life_span = 0 THEN sales_amount
		else sales_amount / life_span 
	END as avg_monthly_spend 

FROM customer_aggregation;
