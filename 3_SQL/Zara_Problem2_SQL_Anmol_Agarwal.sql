-- ######################################################################
-- ZARA CAPSTONE - PROBLEM STATEMENT 2 (SQL): PRICING, PROMOTIONS AND MARGIN
-- Business Analyst: Anmol Agarwal | Business owner: Head of Merchandising
-- Database: MySQL, schema `zara` (6 tables loaded with csv_to_sql.py)
-- ######################################################################
--
-- RULES USED IN EVERY QUERY
--   * All money in US dollars via the exchange_rates table:
--     1 EUR = 1.08, 1 GBP = 1.27, 1 CNY = 0.14, 1 USD = 1.
--   * Money comes from Line_Total, never Invoice_Total (4,200 invoices disagree).
--   * Net sales = sales + returns. Returns have a POSITIVE Quantity but a
--     NEGATIVE Line_Total, so returned units are counted as negative units.
--   * Gross margin = net sales - production cost x net units.
--     Production_Cost is in EUR, so it is converted at 1.08.
--   * 25 products have a cost about 100x too high (decimal error); costs above
--     200 EUR (or above 10x their sub-category's typical cost) are divided by 100.
--   * A discounted line has Discount > 0 and belongs to the Winter Sale, the
--     Summer Sale or Black Friday 2024 (discounts table).
--
-- CONTENTS
--   0. First look at the data
--   1. Reference tables (exchange rates, country and city names)
--   2. Data checks ("Trust the numbers") and the data quality log
--   3. Sales and margin: KPIs, category margin, markdown depth, what ends up in the sale
--   4. Promotions: sale phases, Black Friday and the early sale, monthly trend
--   5. Products: top products, Pareto, returns
--   6. Reusable report: stored procedure promo_report
--
-- Results in the RESULT / FINDING comments are the outputs of each query
-- (whole period 1 Jan 2023 - 18 Mar 2025 unless stated).
-- ######################################################################



-- ======================================================================
-- 0. FIRST LOOK AT THE DATA
-- 0.1 Row count of every table (are all six tables loaded?)
-- ======================================================================
USE zara;

SELECT 'stores' AS table_name, COUNT(*) AS row_count FROM stores
UNION ALL
SELECT 'employees', COUNT(*) FROM employees
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'discounts', COUNT(*) FROM discounts
UNION ALL
SELECT 'transactions', COUNT(*) FROM transactions;
-- RESULT: stores 35 | employees 1,746 | customers 591,159 | products 7,199 |
--         discounts 513 | transactions 3,340,935.
-- FINDING: all six tables loaded completely.

-- ======================================================================
-- 0.2 Structure of transactions, and sales vs returns
-- How: column list, then lines and Line_Total per Transaction_Type.
-- ======================================================================
DESCRIBE transactions;
SELECT
    Transaction_Type,
    COUNT(*) AS Total_Rows,
    SUM(Line_Total) AS Total_Line_Amount
FROM transactions
GROUP BY Transaction_Type;
-- RESULT: Sale 3,042,562 lines (Line_Total 261,299,978) | Return 298,373 lines
--         (Line_Total -19,733,816). These totals mix four currencies, so they
--         are only a row check - every later query converts to USD first.
-- FINDING: about 9% of lines are returns, and returns carry negative amounts.

-- ======================================================================
-- 0.3 Raw country names in stores, and the date range of the data
-- ======================================================================
DESCRIBE transactions;
SELECT DISTINCT Country FROM stores;
-- RESULT: 7 countries, three in the local language: 中国, Deutschland, España.
-- FINDING: names must be translated (country_map) before reporting.



SELECT MIN(Date), MAX(Date) FROM transactions;
-- RESULT: 2023-01-01 10:00:00 to 2025-03-18 21:53:10.
-- FINDING: 2025 is a partial year (to 18 March) and is compared only
--          with the same dates in 2024.




USE zara;

-- ======================================================================
-- 1. REFERENCE TABLES
-- 1.1 exchange_rates: one rate per currency, used to convert every amount to USD.
-- 1.2 country_map: local country names -> English (中国 -> China, etc.).
-- 1.3 city_map: local city names -> English (München -> Munich, etc.).
-- ======================================================================
DROP TABLE IF EXISTS exchange_rates;
CREATE TABLE exchange_rates (
    Currency    VARCHAR(3) PRIMARY KEY,
    Rate_to_USD DECIMAL(8,4) NOT NULL
);

INSERT INTO exchange_rates VALUES
 ('USD', 1.0000), ('EUR', 1.0800), ('GBP', 1.2700), ('CNY', 0.1400);
 
 DROP TABLE IF EXISTS country_map;
CREATE TABLE country_map (
    Raw_Country VARCHAR(100) PRIMARY KEY,
    Country_EN  VARCHAR(100) NOT NULL
);
INSERT INTO country_map VALUES
 ('United States','United States'), ('中国','China'), ('Deutschland','Germany'),
 ('France','France'), ('España','Spain'), ('Portugal','Portugal'),
 ('United Kingdom','United Kingdom');
 
 DROP TABLE IF EXISTS city_map;
CREATE TABLE city_map (
    Raw_City VARCHAR(100) PRIMARY KEY,
    City_EN  VARCHAR(100) NOT NULL
);
INSERT INTO city_map VALUES
 ('上海','Shanghai'), ('北京','Beijing'), ('广州','Guangzhou'), ('深圳','Shenzhen'), ('成都','Chengdu'),
 ('München','Munich'), ('Köln','Cologne'), ('Frankfurt am Main','Frankfurt'),
 ('Lisboa','Lisbon'), ('Sevilla','Seville');
 
-- RESULT: exchange_rates 4 rows | country_map 7 rows | city_map 10 rows.


-- ======================================================================
-- 2. DATA CHECKS ("TRUST THE NUMBERS")
-- 2.1 Invoices whose Invoice_Total does not equal the sum of their lines.
-- How: one row per invoice with MAX(Invoice_Total) and SUM(Line_Total).
-- The full table timed out on 3.3M rows, so it is rebuilt store by store
-- below (store 1 here, then stores 31-35 in the next block).
-- ======================================================================
DROP TABLE IF EXISTS invoice_summary;
CREATE TABLE invoice_summary AS
SELECT Invoice_ID,
       MAX(Invoice_Total) AS invoice_total,
       SUM(Line_Total)    AS sum_of_lines,
       COUNT(*)           AS line_count
FROM transactions
GROUP BY Invoice_ID;

USE zara;
DROP TABLE IF EXISTS invoice_summary;
CREATE TABLE invoice_summary (Invoice_ID VARCHAR(255), Store_ID BIGINT,
    invoice_total DECIMAL(16,4), sum_of_lines DECIMAL(16,4), line_count INT);

INSERT INTO invoice_summary
SELECT Invoice_ID, Store_ID, MAX(Invoice_Total), SUM(Line_Total), COUNT(*)
FROM transactions WHERE Store_ID = 1 GROUP BY Invoice_ID, Store_ID;
-- RESULT: store 1 -> 111,429 invoices in invoice_summary.

 
 


USE zara;

-- 2.1 (continued) invoice_summary for more stores.
-- The table is dropped and re-created so the file runs top to bottom, and the
-- Store_ID index the FORCE INDEX hints rely on is created first (skip the
-- CREATE INDEX line if the index already exists in your database).
DROP TABLE IF EXISTS invoice_summary;
CREATE INDEX ix_t_store ON transactions (Store_ID);

CREATE TABLE invoice_summary (
    Invoice_ID    VARCHAR(255),
    Store_ID      BIGINT,
    invoice_total DECIMAL(16,4),
    sum_of_lines  DECIMAL(16,4),
    line_count    INT
);

INSERT INTO invoice_summary
SELECT Invoice_ID, Store_ID, MAX(Invoice_Total), SUM(Line_Total), COUNT(*)
FROM transactions FORCE INDEX (ix_t_store)
WHERE Store_ID = 1
GROUP BY Invoice_ID, Store_ID;

INSERT INTO invoice_summary
SELECT Invoice_ID, Store_ID, MAX(Invoice_Total), SUM(Line_Total), COUNT(*)
FROM transactions FORCE INDEX (ix_t_store)
WHERE Store_ID BETWEEN 31 AND 35
GROUP BY Invoice_ID, Store_ID;

SELECT COUNT(*) FROM invoice_summary;
-- RESULT: 363,265 invoices (store 1: 111,429 + stores 31-35: 251,836).
-- FINDING (all 1,786,791 invoices): 4,200 invoices have an Invoice_Total that
--          does not equal the sum of their lines -> money is always taken
--          from Line_Total, and invoices are counted with COUNT(DISTINCT).



-- ======================================================================
-- 2.2 Lines with no size or colour
-- Store 1 first (fast), then the whole table.
-- ======================================================================
SELECT SUM(Size  IS NULL OR TRIM(Size)  = '') AS missing_size,
       SUM(Color IS NULL OR TRIM(Color) = '') AS missing_color
FROM transactions FORCE INDEX (ix_t_store)
WHERE Store_ID = 1;
-- RESULT: store 1 -> 663 lines with no size, 299 with no colour.

-- ======================================================================
-- 2.3 Products whose production cost cannot be right
-- How: min / average / max cost per category and sub-category,
-- then products costing more than 10x their sub-category's typical cost.
-- ======================================================================
SELECT Category, Sub_Category,
       COUNT(*)              AS products,
       MIN(Production_Cost)  AS min_cost,
       ROUND(AVG(Production_Cost), 2) AS avg_cost,
       MAX(Production_Cost)  AS max_cost,
       SUM(Production_Cost IS NULL OR Production_Cost <= 0) AS zero_or_missing
FROM products
GROUP BY Category, Sub_Category
ORDER BY Category, Sub_Category;
-- RESULT: 29 sub-categories. Every sub-category has a maximum far above its
--         average (e.g. Man Shoes: average 69.23, max 4,469; Woman Coats and
--         Trench Coats: average 65.43, max 4,355).

SELECT SUM(Size  IS NULL OR TRIM(Size)  = '') AS missing_size,
       SUM(Color IS NULL OR TRIM(Color) = '') AS missing_color
FROM transactions;
-- RESULT: 13,363 lines with no size, 6,681 with no colour (whole table).
-- FINDING: under 0.4% of lines; kept, and colour can come from products.

SELECT p.Product_ID, p.Description_EN, p.Sub_Category, p.Production_Cost
FROM products p
JOIN (SELECT Sub_Category, AVG(Production_Cost) AS typical
      FROM products WHERE Production_Cost < 200 GROUP BY Sub_Category) a
  ON a.Sub_Category = p.Sub_Category
WHERE p.Production_Cost > 10 * a.typical
ORDER BY p.Production_Cost DESC;
-- RESULT: 25 products. Worst: 6775 Shoes 4,469 | 1487 Coats and Trench Coats
--         4,355 | 4198 Blazers 3,608 - all about 100x their sub-category.
-- FINDING: decimal-point errors; the cost is divided by 100 in every margin
--          query, otherwise margin would be badly understated.

-- ======================================================================
-- 2.4 Products that were never sold
-- How: LEFT JOIN products to transactions.
-- ======================================================================
SELECT COUNT(*) AS never_sold
FROM products p
LEFT JOIN transactions t ON t.Product_ID = p.Product_ID
WHERE t.Product_ID IS NULL;
-- RESULT: 36 products never sold.
-- FINDING: kept in products but left out of products-sold and Pareto counts.

-- ======================================================================
-- 2.5 Sales served by an employee from another store
-- How: join each line's employee to employees and compare Store_ID.
-- ======================================================================
CREATE INDEX ix_e_empid ON employees(Employee_ID);

SELECT COUNT(*) AS lines_wrong_store_employee
FROM transactions t
JOIN employees e ON e.Employee_ID = t.Employee_ID
WHERE e.Store_ID <> t.Store_ID;
-- RESULT: 1,452 lines served by an employee from another store.
-- FINDING: 0.04% of lines; no effect on sales or margin, so kept.

-- ======================================================================
-- 2.6 DATA QUALITY LOG - one row per issue and what was done about it
-- ======================================================================
USE zara;
DROP TABLE IF EXISTS dq_log;
CREATE TABLE dq_log (
    Issue_ID INT AUTO_INCREMENT PRIMARY KEY,
    Table_Name VARCHAR(50), Column_Name VARCHAR(100), Issue VARCHAR(255),
    Rows_Affected BIGINT, Fix_Applied VARCHAR(255)
);

INSERT INTO dq_log (Table_Name, Column_Name, Issue, Rows_Affected, Fix_Applied) VALUES
('transactions','Invoice_Total','Does not equal sum of Line_Totals; mostly not rounding',4200,
 'Not corrected. All money from Line_Total; invoices counted with COUNT(DISTINCT Invoice_ID)'),
('transactions','Size','Size missing, spread across all stores',13363,
 'Lines kept; size labelled Unknown; excluded only from size-level analysis'),
('transactions','Color','Colour missing',6681,
 'Colour taken from products.Color via Product_ID'),
('products','Production_Cost','Cost about 100x too high (decimal-point error) in 24-25 products',25,
 'Corrected in v_products_clean: cost > 10x sub-category typical is divided by 100'),
('transactions','Employee_ID','Sale served by an employee from another store',1452,
 'Kept; no effect on sales or margin; handle in employee productivity analysis (Problem 1)'),
('products','Product_ID','Products never sold',36,
 'Kept in products; excluded from products-sold and Pareto counts');

select * from dq_log;
-- RESULT: 6 rows - Invoice_Total 4,200 | Size 13,363 | Color 6,681 |
--         Production_Cost 25 | Employee_ID 1,452 | Product_ID 36.

USE zara;

-- ======================================================================
-- 3. SALES AND MARGIN
-- One-time speed-up for the 3.3M-row transactions table: more memory for
-- MySQL (needs admin rights) and one covering index, then fresh statistics.
-- ======================================================================
-- 1. Give MySQL more memory (2 GB; use 1073741824 if your laptop has under 8 GB RAM)
SET GLOBAL innodb_buffer_pool_size =1073741824 ;

-- 2. Build one index that holds the columns your queries use (takes a few minutes, once)
CREATE INDEX ix_cover ON transactions
    (Product_ID, Currency, Transaction_Type, Discount, `Date`, Quantity, Line_Total);

-- 3. Refresh MySQL's statistics so it picks the index
ANALYZE TABLE transactions;

-- ======================================================================
-- 3.1 KPIs BY YEAR: gross sales, returns, net sales, gross margin, margin %
-- How: A) typical cost per sub-category, B) corrected cost in USD per
-- product, C) totals per year; returned units count as negative.
-- ======================================================================
WITH typical_cost AS (          -- step A: what a normal cost looks like per sub-category
    SELECT Sub_Category, AVG(Production_Cost) AS typical
    FROM products
    WHERE Production_Cost < 200
    GROUP BY Sub_Category
),
product_cost AS (               -- step B: one corrected cost in US dollars per product
    SELECT p.Product_ID,
           CASE WHEN p.Production_Cost > 10 * t.typical
                THEN p.Production_Cost / 100
                ELSE p.Production_Cost END * 1.08 AS cost_usd
    FROM products p
    JOIN typical_cost t ON t.Sub_Category = p.Sub_Category
),
yearly AS (                     -- step C: totals per year
    SELECT YEAR(tr.`Date`) AS yr,
           SUM(CASE WHEN tr.Transaction_Type = 'Sale'
                    THEN tr.Line_Total * er.Rate_to_USD ELSE 0 END)   AS gross_sales,
           SUM(CASE WHEN tr.Transaction_Type = 'Return'
                    THEN tr.Line_Total * er.Rate_to_USD ELSE 0 END)   AS returns,
           SUM(tr.Line_Total * er.Rate_to_USD)                        AS net_sales,
           SUM(CASE WHEN tr.Transaction_Type = 'Return' THEN -tr.Quantity ELSE tr.Quantity END
               * pc.cost_usd)                                         AS cost_of_goods
    FROM transactions tr
    JOIN exchange_rates er ON er.Currency   = tr.Currency
    JOIN product_cost   pc ON pc.Product_ID = tr.Product_ID
    GROUP BY YEAR(tr.`Date`)
)
SELECT yr,
       ROUND(gross_sales)                       AS gross_sales_usd,
       ROUND(returns)                           AS returns_usd,
       ROUND(net_sales)                         AS net_sales_usd,
       ROUND(net_sales - cost_of_goods)         AS gross_margin_usd,
       ROUND(100 * (net_sales - cost_of_goods) / net_sales, 2) AS gross_margin_pct
FROM yearly
ORDER BY yr;
-- RESULT:
--   2023: gross 64.16M | returns -6.67M | net 57.49M | margin 32.86M | 57.16%
--   2024: gross 65.57M | returns -7.35M | net 58.22M | margin 33.12M | 56.88%
--   2025 (to 18 Mar): gross 12.31M | returns -1.44M | net 10.87M | margin 5.60M | 51.53%
-- FINDING: net sales grew 1.3% in 2024 but margin % slipped from 57.2% to
--   56.9%; early 2025 is 51.5% because Jan-Mar is Winter Sale season.


-- ======================================================================
-- 3.2 CATEGORY MARGIN: gross margin % by category and sub-category
-- Which sub-categories earn least, and why? (lowest margin first)
-- ======================================================================
SELECT p.Category,
       p.Sub_Category,
       ROUND(SUM(t.Line_Total * er.Rate_to_USD))                          AS net_sales_usd,
       ROUND(SUM(t.Line_Total * er.Rate_to_USD
             - (CASE WHEN t.Transaction_Type = 'Return' THEN -t.Quantity ELSE t.Quantity END)
               * (CASE WHEN p.Production_Cost > 200 THEN p.Production_Cost / 100
                       ELSE p.Production_Cost END) * 1.08))              AS gross_margin_usd,
       ROUND(100 * SUM(t.Line_Total * er.Rate_to_USD
             - (CASE WHEN t.Transaction_Type = 'Return' THEN -t.Quantity ELSE t.Quantity END)
               * (CASE WHEN p.Production_Cost > 200 THEN p.Production_Cost / 100
                       ELSE p.Production_Cost END) * 1.08)
             / SUM(t.Line_Total * er.Rate_to_USD), 2)                     AS gross_margin_pct
FROM transactions t
JOIN exchange_rates er ON er.Currency  = t.Currency
JOIN products       p  ON p.Product_ID = t.Product_ID
GROUP BY p.Category, p.Sub_Category
ORDER BY gross_margin_pct ASC;
-- RESULT: lowest margin: Kids Shoes 47.1% | Girls 48.3% | Baby 48.3% | Boys 49.0% |
--         Man Coats and Jackets 50.6%. Highest: Man Perfumes 76.0% | Woman
--         Perfumes 75.4% | Woman Accessories 63.8%.
--         By category: Woman 57.8% | Man 56.0% | Kids 48.3%.
-- FINDING: Kids earns least because its prices are low against its cost and
--   it is heavily discounted; coats and jackets lose margin because almost a
--   third of their units are sold on markdown (query 3.4).

-- ======================================================================
-- 3.3 MARKDOWN DEPTH: share of lines, net sales and margin % per band
-- How: CASE groups Discount into full price, 30%, 40-50% and 60-70%.
-- At which depth does Zara start losing money on a sale?
-- ======================================================================
SELECT CASE WHEN t.Discount = 0               THEN '1 Full price'
            WHEN t.Discount <= 0.35           THEN '2  30%'
            WHEN t.Discount <= 0.55           THEN '3  40-50%'
            ELSE                                   '4  60-70%' END   AS markdown_band,
       SUM(t.Transaction_Type = 'Sale')                                AS sale_lines,
       ROUND(100 * SUM(t.Transaction_Type = 'Sale')
             / SUM(SUM(t.Transaction_Type = 'Sale')) OVER (), 2)       AS pct_of_sale_lines,
       ROUND(SUM(t.Line_Total * er.Rate_to_USD))                       AS net_sales_usd,
       ROUND(100 * SUM(t.Line_Total * er.Rate_to_USD
             - (CASE WHEN t.Transaction_Type = 'Return' THEN -t.Quantity ELSE t.Quantity END)
               * (CASE WHEN p.Production_Cost > 200 THEN p.Production_Cost / 100 ELSE p.Production_Cost END) * 1.08)
             / SUM(t.Line_Total * er.Rate_to_USD), 2)                  AS gross_margin_pct
FROM transactions t
JOIN exchange_rates er ON er.Currency  = t.Currency
JOIN products       p  ON p.Product_ID = t.Product_ID
GROUP BY markdown_band
ORDER BY markdown_band;
-- RESULT:
--   1 Full price : 2,445,540 sale lines | 80.4% of lines | net 109.58M | GM 60.55%
--   2  30%       :   181,154 sale lines |  5.9% of lines | net   6.27M | GM 43.44%
--   3  40-50%    :   373,075 sale lines | 12.3% of lines | net  10.13M | GM 27.19%
--   4  60-70%    :    42,793 sale lines |  1.4% of lines | net   0.61M | GM -40.79%
-- FINDING: margin falls with every step of depth (60.6% -> 43.4% -> 27.2%) and
--   turns NEGATIVE at 70% off (-40.8%): the price is then below the cost to make.
--   Zara loses money somewhere between 50% and 70% off. One sale line in five
--   (19.6%) is on markdown; the 60-70% lines are few (1.4%) but each destroys value.


-- ======================================================================
-- 3.4 WHAT ENDS UP IN THE SALE: share of each sub-category's units on markdown
-- Which collections are overbought, and which are never discounted?
-- ======================================================================
SELECT p.Category,
       p.Sub_Category,
       SUM(t.Quantity)                                            AS units_sold,
       SUM(CASE WHEN t.Discount > 0 THEN t.Quantity ELSE 0 END)   AS units_on_markdown,
       ROUND(100 * SUM(CASE WHEN t.Discount > 0 THEN t.Quantity ELSE 0 END)
             / SUM(t.Quantity), 1)                                AS pct_units_on_markdown
FROM transactions t
JOIN products p ON p.Product_ID = t.Product_ID
WHERE t.Transaction_Type = 'Sale'
GROUP BY p.Category, p.Sub_Category
ORDER BY pct_units_on_markdown DESC;
-- RESULT: 29 sub-categories; 3,316,530 units sold, 650,754 on markdown = 19.6%.
--   Most discounted: Man Coats and Jackets 29.1% | Man Knitwear and Sweatshirts
--     28.5% | Kids Shoes 27.1% | Kids Girls 26.1% | Man Shoes 25.3% | Kids Boys 25.0%.
--   Least discounted: Man Jeans 14.5% | Woman Jeans 14.7% | Woman Blazers 16.3% |
--     Man Shirts 16.3%. Never discounted: Man and Woman Perfumes (0%).
-- FINDING: outerwear, knitwear and kids' wear are the overbought collections
--   (25-29% of units on markdown); jeans are the best managed. The most
--   discounted sub-categories are also the lowest-margin ones in 3.2.


-- ======================================================================
-- 4. PROMOTIONS
-- 4.1 SALE PHASES vs THE TWO WEEKS BEFORE THE SALE
-- How: Step 0 reads season and phase from the discounts calendar; Step 1 builds
-- daily sales per sub-category and country (only the dates needed); Step 2
-- joins them to each phase on date range, category, sub-category and country
-- (blank country = all seven); Step 3 takes the 14 days before phase 1;
-- Step 4 compares units, sales and margin PER DAY (phases are 14 days, BF is 4).
-- ======================================================================
CREATE INDEX ix_p_id ON products (Product_ID);
CREATE INDEX ix_s_id ON stores (Store_ID);
WITH cal AS (            -- Step 0: calendar with clean names
    SELECT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(Description, 'during our ', -1), ' - phase', 1)) AS season,
           IF(Description LIKE '%phase%', SUBSTRING_INDEX(Description, 'phase ', -1), 'BF')     AS phase_no,
           Start AS start_date, `End` AS end_date, Category, Sub_Category,
           NULLIF(TRIM(Country), '')                            AS country,   -- NULL = all 7 countries
           COALESCE(NULLIF(TRIM(Country), ''), 'All countries') AS grp
    FROM discounts
),
win AS (                 -- Step 0b: date window of each season = 14 days before it starts, to its end
    SELECT MIN(start_date) - INTERVAL 14 DAY AS w_from,   -- (the seasons do not overlap, so no
           MAX(end_date)   + INTERVAL 1 DAY  AS w_to      --  line can be counted twice)
    FROM cal
    GROUP BY season
),
daily AS (               -- Step 1: one row per day x sub-category x country, in USD
    SELECT DATE(t.`Date`) AS sale_date, s.Country AS store_country,
           p.Category, p.Sub_Category,
           SUM(IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity))   AS units,
           SUM(t.Line_Total * er.Rate_to_USD)                                AS net_usd,
           SUM(IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)
               * IF(p.Production_Cost > 200, p.Production_Cost / 100, p.Production_Cost)
               * 1.08)                                                       AS cost_usd
    FROM win w                                  -- read ONLY the dates the sales need
    STRAIGHT_JOIN transactions t ON t.`Date` >= w.w_from AND t.`Date` < w.w_to
    JOIN products       p  ON p.Product_ID = t.Product_ID
    JOIN stores         s  ON s.Store_ID   = t.Store_ID
    JOIN exchange_rates er ON er.Currency  = t.Currency
    GROUP BY DATE(t.`Date`), s.Country, p.Category, p.Sub_Category
),
phase AS (               -- Step 2: sales inside each phase
    SELECT c.season, c.phase_no, c.grp,
           MIN(c.start_date)                                AS first_day,
           DATEDIFF(MAX(c.end_date), MIN(c.start_date)) + 1 AS days,
           SUM(d.units) AS units, SUM(d.net_usd) AS net_usd, SUM(d.cost_usd) AS cost_usd
    FROM daily d
    JOIN cal c
      ON  c.Category = d.Category AND c.Sub_Category = d.Sub_Category
      AND d.sale_date BETWEEN c.start_date AND c.end_date
      AND (c.country IS NULL OR c.country LIKE CONCAT('%', d.store_country, '%'))
    GROUP BY c.season, c.phase_no, c.grp
),
baseline AS (            -- Step 3: the 14 days before the first phase
    SELECT c.season, c.grp,
           SUM(d.units) AS units, SUM(d.net_usd) AS net_usd, SUM(d.cost_usd) AS cost_usd
    FROM daily d
    JOIN cal c
      ON  c.Category = d.Category AND c.Sub_Category = d.Sub_Category
      AND c.phase_no IN ('1', 'BF')
      AND d.sale_date BETWEEN c.start_date - INTERVAL 14 DAY AND c.start_date - INTERVAL 1 DAY
      AND (c.country IS NULL OR c.country LIKE CONCAT('%', d.store_country, '%'))
    GROUP BY c.season, c.grp
)
SELECT p.season, p.phase_no,                                   -- Step 4: compare per day
       -- English country names from your country_map table
       COALESCE((SELECT GROUP_CONCAT(DISTINCT cm.country_en ORDER BY cm.country_en SEPARATOR ', ')
                 FROM country_map cm
                 WHERE p.grp LIKE CONCAT('%', cm.raw_country, '%')), p.grp) AS countries,
       p.units,
       ROUND(p.net_usd)                                             AS net_sales_usd,
       ROUND(100 * (b.net_usd - b.cost_usd) / b.net_usd, 1)         AS gm_pct_before,
       ROUND(100 * (p.net_usd - p.cost_usd) / p.net_usd, 1)         AS gm_pct_phase,
       ROUND(100 * ((p.units / p.days) / (b.units / 14) - 1))       AS units_per_day_change_pct,
       ROUND(100 * ((p.net_usd / p.days) / (b.net_usd / 14) - 1))   AS sales_per_day_change_pct,
       ROUND(100 * (((p.net_usd - p.cost_usd) / p.days)
                  / ((b.net_usd - b.cost_usd) / 14) - 1))           AS margin_per_day_change_pct
FROM phase p
JOIN baseline b ON b.season = p.season AND b.grp = p.grp
ORDER BY p.first_day, p.grp, p.phase_no;
-- RESULT (margin per day vs the 14 days before; + = phase worth its margin):
--   Summer Sale 2023    : phase 1 +20% | phase 2 -23% | phase 3 -57%
--   Winter Sale 2023-24 : phase 1 -15% | phase 2 -56% | phase 3 -76%
--   Summer Sale 2024    : phase 1 +19% | phase 2 -23% | phase 3 -56%
--   Black Friday 2024 (US, UK): +129% (units +261%, margin 49.8% vs 60.5% before)
--   Winter Sale 2024-25 US+UK : phase 1 +20% | phase 2 -47% | phase 3 -71%
--   Winter Sale 2024-25 others: phase 1 -16% | phase 2 -55% | phase 3 -74%
--   Margin % falls from about 60% before the sale to 46-50% in phase 1,
--   40-45% in phase 2 and 31-38% in phase 3.
-- FINDING: only phase 1 (30-40% off) of the Summer Sales, and Black Friday, earn
--   more margin per day than normal trading. Phases 2 and 3 never pay for their
--   discount; phase 3 loses 55-76% of normal daily margin. (Winter phase 1 is
--   compared with busy pre-Christmas weeks, which makes it look weaker.)
 
 -- margin_per_day_change_pct > 0  -> the phase is worth its margin.
--    margin_per_day_change_pct < 0  -> volume did not make up for the markdown.
--  
--    NOTE: Winter Sale 2022-23 drops out automatically - the data starts on
--    1 Jan 2023, so there are no "two weeks before" to compare with.


-- ======================================================================
-- 4.2 BLACK FRIDAY AND THE EARLY WINTER SALE (US and UK only)
-- 2a. The dates and rates of Black Friday 2024 and the Winter Sale 2024-25.
-- ======================================================================
SELECT Description, Country, MIN(Start) AS first_day, MAX(`End`) AS last_day,
       MIN(Discont) AS min_rate, MAX(Discont) AS max_rate
FROM discounts
WHERE Description LIKE '%Black Friday%' OR Description LIKE '%Winter Sale 2024-25%'
GROUP BY Description, Country
ORDER BY first_day, Country;
-- RESULT: Black Friday 29 Nov - 2 Dec 2024, 30% off, US and UK only.
--   Winter Sale 2024-25 started 20 Dec in the US and UK, 26 Dec elsewhere.
 
-- 2b. Three weeks before Christmas (4-24 Dec): 2023 vs 2024, US+UK vs the rest
WITH xmas AS (
    SELECT YEAR(t.`Date`) AS yr,
           IF(cm.country_en IN ('United States', 'United Kingdom'), 'US + UK', 'Other 5 countries') AS region,
           SUM(IF(t.Discount = 0, t.Line_Total * er.Rate_to_USD, 0))  AS full_price_usd,
           SUM(IF(t.Discount > 0, t.Line_Total * er.Rate_to_USD, 0))  AS markdown_usd,
           SUM(t.Line_Total * er.Rate_to_USD)                         AS net_usd,
           SUM(IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)
               * IF(p.Production_Cost > 200, p.Production_Cost / 100, p.Production_Cost)
               * 1.08)                                                AS cost_usd
    FROM transactions t
    JOIN products       p  ON p.Product_ID = t.Product_ID
    JOIN stores         s  ON s.Store_ID   = t.Store_ID
    JOIN country_map    cm ON cm.raw_country  = s.Country
    JOIN exchange_rates er ON er.Currency  = t.Currency
    WHERE (t.`Date` >= '2023-12-04' AND t.`Date` < '2023-12-25')
       OR (t.`Date` >= '2024-12-04' AND t.`Date` < '2024-12-25')
    GROUP BY YEAR(t.`Date`), region
)
SELECT region,
       ROUND(SUM(IF(yr = 2023, full_price_usd, 0)))                                         AS full_price_2023,
       ROUND(SUM(IF(yr = 2024, full_price_usd, 0)))                                         AS full_price_2024,
       ROUND(100 * (SUM(IF(yr = 2024, full_price_usd, 0)) / SUM(IF(yr = 2023, full_price_usd, 0)) - 1), 1) AS full_price_change_pct,
       ROUND(SUM(IF(yr = 2023, markdown_usd, 0)))                                           AS markdown_2023,
       ROUND(SUM(IF(yr = 2024, markdown_usd, 0)))                                           AS markdown_2024,
       ROUND(100 * (SUM(IF(yr = 2024, net_usd, 0)) / SUM(IF(yr = 2023, net_usd, 0)) - 1), 1) AS total_change_pct,
       ROUND(100 * (SUM(IF(yr = 2023, net_usd - cost_usd, 0)) / SUM(IF(yr = 2023, net_usd, 0))), 1) AS gm_pct_2023,
       ROUND(100 * (SUM(IF(yr = 2024, net_usd - cost_usd, 0)) / SUM(IF(yr = 2024, net_usd, 0))), 1) AS gm_pct_2024
FROM xmas
GROUP BY region
ORDER BY region DESC;
-- RESULT (4-24 Dec):
--   US + UK : full price 1,247,641 -> 1,068,097 (-14.4%) | markdown 0 -> 273,727 |
--             total +7.5% | margin % 60.9% -> 57.1%
--   Other 5 : full price 3,201,309 -> 3,289,992 (+2.8%)  | markdown 0 -> 0 |
--             total +2.8% | margin % 59.8% -> 59.9%
-- FINDING: in the US and UK, full-price sales fell 14% while the rest grew 3%;
--   the extra total came from markdown at a lower margin. The events mostly
--   moved sales earlier at a lower price rather than adding them.
 
-- 2c. Week by week, Nov-Dec: where did the sales move? (ISO weeks 44-52)
WITH weekly AS (
    SELECT YEAR(t.`Date`) AS yr, WEEK(t.`Date`, 3) AS iso_week,
           IF(cm.country_en IN ('United States', 'United Kingdom'), 'US + UK', 'Other 5 countries') AS region,
           SUM(IF(t.Discount = 0, t.Line_Total * er.Rate_to_USD, 0)) AS full_price_usd,
           SUM(IF(t.Discount > 0, t.Line_Total * er.Rate_to_USD, 0)) AS markdown_usd
    FROM transactions t
    JOIN stores         s  ON s.Store_ID  = t.Store_ID
    JOIN country_map    cm ON cm.raw_country = s.Country
    JOIN exchange_rates er ON er.Currency = t.Currency
    WHERE (t.`Date` >= '2023-10-30' AND t.`Date` < '2024-01-01')
       OR (t.`Date` >= '2024-10-28' AND t.`Date` < '2025-01-01')
    GROUP BY YEAR(t.`Date`), WEEK(t.`Date`, 3), region
)
SELECT region, iso_week,
       ROUND(SUM(IF(yr = 2023, full_price_usd, 0))) AS full_price_2023,
       ROUND(SUM(IF(yr = 2024, full_price_usd, 0))) AS full_price_2024,
       ROUND(SUM(IF(yr = 2023, markdown_usd, 0)))   AS markdown_2023,
       ROUND(SUM(IF(yr = 2024, markdown_usd, 0)))   AS markdown_2024
FROM weekly
WHERE iso_week BETWEEN 44 AND 52
GROUP BY region, iso_week
ORDER BY region DESC, iso_week;
-- RESULT (US + UK full price by ISO week, 2023 -> 2024):
--   weeks 44-47: +9% to +15% (normal growth, no promotion yet)
--   week 48 (Black Friday): 389,784 -> 372,057, plus 327,379 on markdown
--   weeks 49-50: -9% and -3%  |  week 51 (early sale): 403,151 -> 313,191 (-22%)
-- FINDING: Black Friday pulled demand out of the first half of December, and
--   the early sale cut full-price sales in the last week before Christmas.
 
-- Compare the two rows. If full_price_change_pct is much lower for
  -- US + UK than for Other 5 countries, while markdown_change_pct is much
  -- higher, sales were pulled forward at a lower price, not added.



 

-- ======================================================================
-- 4.3 MONTHLY TREND WITH LAG(): month-on-month and year-on-year
-- Also: how much of each month's net sales came from marked-down lines.
-- ======================================================================
WITH monthly AS (        -- Step 1: one row per month, in USD
    SELECT DATE_FORMAT(t.`Date`, '%Y-%m')                                AS month,
           SUM(t.Line_Total * er.Rate_to_USD)                            AS net_usd,
           SUM(IF(t.Discount > 0, t.Line_Total * er.Rate_to_USD, 0))     AS markdown_usd,
           SUM(IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)
               * IF(p.Production_Cost > 200, p.Production_Cost / 100, p.Production_Cost)
               * 1.08)                                                   AS cost_usd
    FROM transactions t
    JOIN products       p  ON p.Product_ID = t.Product_ID
    JOIN exchange_rates er ON er.Currency  = t.Currency
    GROUP BY DATE_FORMAT(t.`Date`, '%Y-%m')
),
last_month AS (          -- the partial month at the end of the data
    SELECT DATE_FORMAT(MAX(`Date`), '%Y-%m') AS month FROM transactions
)
SELECT m.month,                                                          -- Steps 2 and 3
       ROUND(m.net_usd)                                         AS net_sales_usd,
       ROUND(100 * (m.net_usd - m.cost_usd) / m.net_usd, 1)     AS gm_pct,
       ROUND(100 * m.markdown_usd / m.net_usd, 1)               AS markdown_share_pct,
       IF(m.month = lm.month, NULL,
          ROUND(100 * (m.net_usd / LAG(m.net_usd, 1)  OVER (ORDER BY m.month) - 1), 1)) AS mom_pct,
       IF(m.month = lm.month, NULL,
          ROUND(100 * (m.net_usd / LAG(m.net_usd, 12) OVER (ORDER BY m.month) - 1), 1)) AS yoy_pct
FROM monthly m
CROSS JOIN last_month lm
ORDER BY m.month;
-- RESULT (highlights):
--   Peak months: Dec 2023 7.18M (markdown 15.1%, margin 57.1%) | Dec 2024 7.39M
--     (markdown 22.4%, margin 55.9%, YoY +3.0%).
--   Sale months: Jan 2024 markdown 58.9%, margin 41.5% | Jul 2024 52.8%, 47.0% |
--     Jan 2025 58.9%, 40.3% (lowest margin month).
--   Nov 2024 YoY +12.8% (Black Friday); Feb is the weakest month every year.
-- FINDING: December is the peak, and in 2024 a larger share of it (22% vs 15%)
--   came from markdown because of Black Friday and the early sale. January and
--   July are mostly markdown and run at 40-47% margin instead of about 60%.
  -- Months with a high markdown_share_pct and a lower gm_pct are the peaks
--    that cost margin. Compare gm_pct in those months with full-price months.
--    The last month in the data (March 2025) is partial (it stops on the 18th),
--    so its month-on-month and year-on-year are left blank on purpose.

-- ======================================================================
-- 5. PRODUCTS
-- 5.1 TOP 10 PRODUCTS BY NET SALES IN EACH CATEGORY (RANK() OVER PARTITION)
-- ======================================================================
WITH product_sales AS (  -- Step 1: net sales per product, in USD
    SELECT p.Product_ID, p.Category, p.Sub_Category, p.Description_EN, p.Color,
           SUM(t.Line_Total * er.Rate_to_USD)                              AS net_usd,
           SUM(IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)) AS units
    FROM transactions t
    JOIN products       p  ON p.Product_ID = t.Product_ID
    JOIN exchange_rates er ON er.Currency  = t.Currency
    GROUP BY p.Product_ID, p.Category, p.Sub_Category, p.Description_EN, p.Color
),
ranked AS (              -- Step 2: rank inside each category
    SELECT ps.*,
           RANK() OVER (PARTITION BY Category ORDER BY net_usd DESC) AS rank_in_category
    FROM product_sales ps
)
SELECT Category, rank_in_category AS `rank`, Product_ID, Description_EN, Color, Sub_Category,
       ROUND(net_usd) AS net_sales_usd, units
FROM ranked
WHERE rank_in_category <= 10                                    -- Step 3
ORDER BY Category, rank_in_category;
-- RESULT (no. 1 and no. 10 in each category):
--   Woman: 1817 ZW COLLECTION PUFFER COAT, white, 1.72M ... no. 10 0.41M
--   Man:   803 BASIC CARDIGAN, red, 1.17M ... no. 10 0.43M
--   Kids:  2088 KNIT SKIRT, camel, 0.35M ... no. 10 0.11M
-- FINDING: Woman depends most on a few hero products (no. 1 sells 4x no. 10);
--   coats and knitwear lead, the same collections that are overbought (3.4).
 -- 30 rows: the 10 best products of Woman, Man and Kids. Compare net_sales_usd
--    down each list - a steep drop means the category depends on a few styles.

-- ======================================================================
-- 5.2 PARETO: what share of products makes up 80% of net sales?
-- How: running SUM() OVER (ORDER BY net sales DESC) against the total.
-- ======================================================================
WITH product_sales AS (  -- Step 1
    SELECT t.Product_ID, SUM(t.Line_Total * er.Rate_to_USD) AS net_usd
    FROM transactions t
    JOIN exchange_rates er ON er.Currency = t.Currency
    GROUP BY t.Product_ID
),
running AS (             -- Steps 2 and 3
    SELECT Product_ID, net_usd,
           ROW_NUMBER() OVER (ORDER BY net_usd DESC, Product_ID)             AS product_rank,
           SUM(net_usd) OVER (ORDER BY net_usd DESC, Product_ID
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_usd,
           SUM(net_usd) OVER ()                                              AS total_usd
    FROM product_sales
)
SELECT MIN(product_rank)                                              AS products_making_80pct,   -- Step 4
       (SELECT COUNT(*) FROM product_sales)                           AS products_sold,
       ROUND(100 * MIN(product_rank) / (SELECT COUNT(*) FROM product_sales), 1) AS pct_of_sold_products,
       (SELECT COUNT(*) FROM products)                                AS products_in_catalogue,
       ROUND(100 * MIN(product_rank) / (SELECT COUNT(*) FROM products), 1)      AS pct_of_catalogue
FROM running
WHERE running_usd >= 0.8 * total_usd;
-- RESULT: 1,826 of 7,163 sold products (25.5%) make 80% of net sales
--         (25.4% of the 7,199-product catalogue).
-- FINDING: close to the classic 80/20 pattern - about a quarter of the range
--   carries the business, so buying depth should follow these styles.

  --  pct_of_sold_products is the answer: the share of sold products that makes
--    up 80% of net sales. The closer to 20%, the more "classic" the pattern;
--    a much higher number means sales are spread across the range.

-- ======================================================================
-- 5.3 RETURNS: return rate (units returned / units sold) by sub-category,
-- size, country and full price vs markdown - in one scan.
-- ======================================================================
WITH r AS (              -- one scan: units sold / returned for every combination
    SELECT p.Sub_Category, t.Size, cm.country_en AS country,
           IF(t.Discount = 0, 'full price', 'markdown') AS price_type,
           SUM(IF(t.Transaction_Type = 'Sale',   t.Quantity, 0)) AS sold,
           SUM(IF(t.Transaction_Type = 'Return', t.Quantity, 0)) AS returned
    FROM transactions t
    JOIN products    p  ON p.Product_ID = t.Product_ID
    JOIN stores      s  ON s.Store_ID   = t.Store_ID
    JOIN country_map cm ON cm.raw_country  = s.Country
    GROUP BY p.Sub_Category, t.Size, cm.country_en, IF(t.Discount = 0, 'full price', 'markdown')
)
SELECT 'sub-category' AS breakdown, Sub_Category AS value, SUM(sold) AS units_sold, SUM(returned) AS units_returned,
       ROUND(100 * SUM(returned) / SUM(sold), 1) AS return_rate_pct FROM r GROUP BY Sub_Category
UNION ALL
SELECT 'size', Size, SUM(sold), SUM(returned), ROUND(100 * SUM(returned) / SUM(sold), 1) FROM r GROUP BY Size
UNION ALL
SELECT 'country', country, SUM(sold), SUM(returned), ROUND(100 * SUM(returned) / SUM(sold), 1) FROM r GROUP BY country
UNION ALL
SELECT 'price type', price_type, SUM(sold), SUM(returned), ROUND(100 * SUM(returned) / SUM(sold), 1) FROM r GROUP BY price_type
ORDER BY breakdown, return_rate_pct DESC;
-- RESULT:
--   Sub-category: Dresses 17.4% | Jeans 16.9% | Trousers 13.3% | Shoes 13.2% ...
--     lowest Perfumes 1.0% | Accessories 2.9% | Bags 3.7%
--   Size: 36 is highest at 21.4%, then 32 17.8% and 44 17.2%; kids and baby
--     sizes 5-7%; one-size items 3.3%
--   Country: Germany 13.9% | UK 11.9% | France 11.1% | US 10.9% | Spain 9.2% |
--     Portugal 8.3% | China 3.8%
--   Price type: full price 10.6% | markdown 6.6%
-- FINDING: fitted clothing (dresses, jeans, trousers) comes back most, Germany
--   returns almost four times as much as China, and markdown items are returned
--   LESS than full-price ones.
 
 
-- 6e. Products whose return rate is far above their sub-category's
WITH prod AS (           -- units sold and returned per product
    SELECT p.Product_ID, p.Description_EN, p.Color, p.Sub_Category,
           SUM(IF(t.Transaction_Type = 'Sale',   t.Quantity, 0)) AS sold,
           SUM(IF(t.Transaction_Type = 'Return', t.Quantity, 0)) AS returned
    FROM transactions t
    JOIN products p ON p.Product_ID = t.Product_ID
    GROUP BY p.Product_ID, p.Description_EN, p.Color, p.Sub_Category
),
rated AS (               -- add each product's own rate and its sub-category's rate
    SELECT prod.*,
           100 * returned / sold AS return_rate,
           100 * SUM(returned) OVER (PARTITION BY Sub_Category)
               / SUM(sold)     OVER (PARTITION BY Sub_Category) AS sub_rate
    FROM prod
)
SELECT Product_ID, Description_EN, Color, Sub_Category,
       sold                         AS units_sold,
       ROUND(return_rate, 1)        AS return_rate_pct,
       ROUND(sub_rate, 1)           AS sub_category_rate_pct,
       ROUND(return_rate / sub_rate, 1) AS times_sub_category
FROM rated
WHERE sold >= 300                       -- enough sales to trust the rate
  AND return_rate >= 2 * sub_rate       -- at least twice the sub-category rate
  AND return_rate - sub_rate >= 5       -- and at least 5 points higher
ORDER BY return_rate / sub_rate DESC
LIMIT 20;
-- RESULT: 7 products, all the same style - Z1975 HIGH-WAIST STRAIGHT JEANS in
--   7 colours (6202, 3598, 4732, 6800, 6281, 1242, 6031): 33.9-36.2% returned
--   vs 16.9% for jeans, about 2.1x.
-- FINDING: one pattern in every colour means a fit or sizing problem with that
--   cut, not a colour or batch issue. Check the size chart and fit block.

-- ======================================================================
-- 6. REUSABLE REPORT: STORED PROCEDURE promo_report(start, end, country)
-- Returns net sales, units and margin for the period and for the period of
-- the same length just before it, with the % change.
-- Country = English name, or 'All' / NULL for every country.
-- Example: CALL promo_report('2024-11-29', '2024-12-02', 'United States');
-- ======================================================================
DROP PROCEDURE IF EXISTS promo_report;
 
DELIMITER $$
CREATE PROCEDURE promo_report(IN p_start DATE, IN p_end DATE, IN p_country VARCHAR(60))
BEGIN
    DECLARE v_days       INT;
    DECLARE v_prev_start DATE;
 
    IF p_start > p_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_start must be on or before p_end';
    END IF;
 
    SET v_days  = DATEDIFF(p_end, p_start) + 1;      -- length of the promotion
    SET v_prev_start = p_start - INTERVAL v_days DAY;     -- same length, right before it
 
    WITH x AS (          -- totals for the promotion period and the period before
        SELECT
            SUM(IF(t.`Date` >= p_start, t.Line_Total * er.Rate_to_USD, 0))                      AS net_now,
            SUM(IF(t.`Date` <  p_start, t.Line_Total * er.Rate_to_USD, 0))                      AS net_prev,
            SUM(IF(t.`Date` >= p_start, IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity), 0)) AS units_now,
            SUM(IF(t.`Date` <  p_start, IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity), 0)) AS units_prev,
            SUM(IF(t.`Date` >= p_start, IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)
                   * IF(p.Production_Cost > 200, p.Production_Cost / 100, p.Production_Cost) * 1.08, 0)) AS cost_now,
            SUM(IF(t.`Date` <  p_start, IF(t.Transaction_Type = 'Return', -t.Quantity, t.Quantity)
                   * IF(p.Production_Cost > 200, p.Production_Cost / 100, p.Production_Cost) * 1.08, 0)) AS cost_prev
        FROM transactions t
        JOIN products       p  ON p.Product_ID = t.Product_ID
        JOIN stores         s  ON s.Store_ID   = t.Store_ID
        JOIN country_map    cm ON cm.Raw_Country = s.Country
        JOIN exchange_rates er ON er.Currency  = t.Currency
        WHERE t.`Date` >= v_prev_start
          AND t.`Date` <  p_end + INTERVAL 1 DAY
          AND (p_country IS NULL OR p_country = 'All' OR cm.country_en = p_country)
    )
    SELECT p_start                                              AS period_start,
           p_end                                                AS period_end,
           v_prev_start                                         AS prev_start,
           p_start - INTERVAL 1 DAY                             AS prev_end,
           ROUND(net_now)                                       AS net_sales_usd,
           ROUND(net_prev)                                      AS prev_net_sales_usd,
           ROUND(100 * (net_now / NULLIF(net_prev, 0) - 1), 1)  AS sales_change_pct,
           units_now                                            AS units,
           units_prev                                           AS prev_units,
           ROUND(100 * (units_now / NULLIF(units_prev, 0) - 1), 1) AS units_change_pct,
           ROUND(net_now - cost_now)                            AS margin_usd,
           ROUND(net_prev - cost_prev)                          AS prev_margin_usd,
           ROUND(100 * ((net_now - cost_now) / NULLIF(net_prev - cost_prev, 0) - 1), 1) AS margin_change_pct,
           ROUND(100 * (net_now - cost_now) / NULLIF(net_now, 0), 1)    AS gm_pct,
           ROUND(100 * (net_prev - cost_prev) / NULLIF(net_prev, 0), 1) AS prev_gm_pct
    FROM x;
END$$
DELIMITER ;
 show create procedure promo_report
-- RESULT of the example (US Black Friday vs 25-28 Nov 2024):
--   net sales 391,207 vs 95,430 (+309.9%) | units 9,367 vs 1,799 (+420.7%) |
--   margin 201,264 vs 58,803 (+242.3%) | margin % 51.4% vs 61.6%
-- FINDING: Black Friday quadrupled US sales in its four days at a 10-point
--   lower margin; the procedure lets any market test its own promotion.
