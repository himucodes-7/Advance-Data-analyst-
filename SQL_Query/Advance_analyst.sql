use DataWarehouseAnalytics
-- Change over time analysis 
-- salees Performance Over Time 
--#region Query2
select 
	year, 
	order_date,
	total_sale,
	total_quantity,
	total_price
from 
	( SELECT
		YEAR(order_date) as year,
		DATENAME(MONTH,order_date) as order_date, 
		MONTH(order_date) as month,
		SUM(sales_amount) as total_sale,
		SUM(quantity) as total_quantity,
		SUM(price) as total_price
	from gold.fact_sales


	WHERE order_date is not NULL 


	GROUP BY YEAR(order_date) ,DATENAME(MONTH,order_date) , MONTH(order_date)
	) as t 
order by year, month
--#endregion

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-- cumulative analysis 
-- Calculate the total sales per month and the running total of sales over time.


SELECT 
	year,
	months,
	total_sales,
	SUM(total_sales) over(PARTITION BY year
					 ORDER BY months
					 ROWS BETWEEN UNBOUNDED PRECEDING and CURRENT ROW ) as sales_Running_total 

FROM (				
		SELECT
			year(order_date) as year, 
			DATEPART(MONTH,order_date) as months,
			sum(sales_amount) as total_sales 
		from gold.fact_sales
		where year(order_date) is not null
		GROUP BY year(order_date),DATEPART(MONTH,order_date)

		
	) as t 

order by year,months

--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
/* Analyze the -- yearly performance of products -- by comparing their sales
to both the average sales performance of the product and the previous year's sales */

WITH Yearly_product_sales AS (
select 
	year(s.order_date) as order_date,
	s.product_key,
	sum(s.sales_amount) as amount,
	SUM(s.quantity) as quantity,
	p.product_name as product_name
from gold.fact_sales as s 
LEFT JOIN gold.dim_products as p
on  s.product_key = p.product_key
where s.order_date is not null 
GROUP BY year(s.order_date),s.product_key,p.product_name
--order by order_date
)

SELECT 
  order_date,
  product_key,
  amount,
  quantity,
  product_name,
  AVG(amount) over(partition by product_name ) AS avg_sales,
  amount - AVG(amount) over(partition by product_name ) as avg_difference,
  LAG(amount) OVER(partition by product_name order by order_date ) as py_sales,
  amount - LAG(amount) OVER(partition by product_name order by order_date ) as py_sales_diff
FROM Yearly_product_sales
ORDER BY product_name,order_date;


--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------

--Analyze how an individual part is performing compared to the overall,
--allowing us to understand which category has the greatest impact on the business.


WITH  product_cat AS (

SELECT 
	p.category as category,
	sum(s.sales_amount) as total_sales,
	sum(sum(s.sales_amount)) OVER() as overall_sales
from gold.fact_sales as s
LEFT JOIN gold.dim_products as p
on s.product_key = p.product_key
GROUP BY p.category

)

select 
category,
total_sales,
overall_sales,
CONCAT(ROUND((CAST (total_sales as FLOAT ) / overall_sales )  * 100,2),'%')  as  cate_percentage 
from product_cat;


--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
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

SELECT * from gold.report_customers;
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------
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
IF OBJECT_ID('gold.report_products', 'V') IS NOT NULL
    DROP VIEW gold.report_products;
GO
CREATE VIEW gold.report_products AS

WITH base_query AS (
/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from fact_sales and dim_products
---------------------------------------------------------------------------*/
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
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE order_date IS NOT NULL  -- only consider valid sales dates
),

product_aggregations AS (
/*---------------------------------------------------------------------------
2) Product Aggregations: Summarizes key metrics at the product level
---------------------------------------------------------------------------*/
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
	COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)),1) AS avg_selling_price
FROM base_query

GROUP BY
    product_key,
    product_name,
    category,
    subcategory,
    cost
)

/*---------------------------------------------------------------------------
  3) Final Query: Combines all product results into one output
---------------------------------------------------------------------------*/
SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
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

FROM product_aggregations ;