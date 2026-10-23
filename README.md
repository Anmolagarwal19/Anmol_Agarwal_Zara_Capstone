<h1 align="center">Zara — Global Retail Analytics Capstone</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Excel-Power_Query_%2B_Power_Pivot-217346?style=flat-square&logo=microsoftexcel&logoColor=white">
  <img src="https://img.shields.io/badge/SQL-MySQL-4479A1?style=flat-square&logo=mysql&logoColor=white">
  <img src="https://img.shields.io/badge/Power_BI-Dashboard-F2C811?style=flat-square&logo=powerbi&logoColor=black">
  <img src="https://img.shields.io/badge/Transactions-3.34M-2E5CA8?style=flat-square">
  <img src="https://img.shields.io/badge/Stores-35-6C4FA1?style=flat-square">
  <img src="https://img.shields.io/badge/Countries-7-3F8F58?style=flat-square">
  <img src="https://img.shields.io/badge/Status-In_Progress-C9922B?style=flat-square">
</p>

<p align="center">
  <img src="cover.png" alt="Zara Global Retail Analytics Capstone — Cover" width="100%">
</p>

## Overview

An end-to-end business analytics capstone built on a simulated Zara retail dataset: **35 stores, 7 countries, 3.34 million invoice lines, 1 January 2023 to 18 March 2025**. Sales are growing, but leadership is worried about uneven store performance, margin lost to discounting, and whether customers keep coming back. Three business owners each brought one problem, and each is solved end to end in a different tool:

- **Store performance and workforce productivity** — Head of Store Operations, solved in Excel
- **Pricing, promotions and margin** — Head of Merchandising, solved in SQL
- **Customer and sales performance** — Chief Commercial Officer, solved in Power BI

Every problem follows the same three parts: **Part A** business framing before touching the data, **Part B** analysis in the assigned tool, and **Part C** recommendations with the metric that will show whether they worked.

---

## The Dataset

Six relational tables, about 3.9 million rows in total:

| Table | Rows | Description |
|---|---|---|
| `stores` | 35 | Store name, city, country, number of employees, coordinates |
| `employees` | 1,746 | Store staff and their positions |
| `customers` | 591,159 | City, country, gender, date of birth |
| `products` | 7,199 | Woman, Man and Kids products with colour, sizes, production cost (EUR), launch date |
| `discounts` | 513 | Markdown calendar: Winter Sale, Summer Sale and Black Friday phases, rate, category, countries |
| `transactions` | 3,340,935 | One row per invoice line: product, size, price, quantity, discount, store, employee, payment, sale or return |

*The data is simulated for teaching. It does not represent Zara's or Inditex's actual stores, customers, figures or events.*

---

## Data Handling Rules

Rules applied consistently across Excel, SQL and Power BI so the three tools reconcile:

| Rule | Treatment |
|---|---|
| Money | Sum `Line Total`, never `Invoice Total` (it repeats on every line of an invoice) |
| Invoices | Counted with a distinct count of `Invoice ID` |
| Returns | Separate `RET-` invoices with negative totals; net sales = sales + returns |
| Currency | Converted to USD at fixed rates: 1 EUR = 1.08 USD, 1 GBP = 1.27 USD, 1 CNY = 0.14 USD |
| Production cost | Stored in EUR, converted at 1.08 |
| Gross margin | Net sales minus production cost × quantity, both in USD |
| Partial year | 2025 runs to 18 March only, so it is compared with the same dates in 2024, never a full year |
| Local-language names | Countries and cities such as 中国 and Deutschland translated to English so each country appears once |

---

## Problem Statements

| # | Problem | Business Owner | Tool |
|---|---|---|---|
| 1 | Store performance and workforce productivity | Head of Store Operations | Excel (Power Query, Power Pivot, dashboard) |
| 2 | Pricing, promotions and margin | Head of Merchandising | SQL (MySQL) |
| 3 | Customer and sales performance | Chief Commercial Officer | Power BI |

### 1. Store Performance and Workforce Productivity (Excel)

Some stores sell several times more per employee than others, headcount does not seem to follow sales, and Spain barely grows while the United States grows fast and China shrinks.

- Ranking of countries and stores by net sales in USD for 2023 and 2024
- Sales per employee and per sales associate, and whether headcount follows sales
- Traffic versus basket: invoices, average basket value and units per invoice for the strongest and weakest stores
- Day-of-week trading patterns, Sunday closures and what they mean for scheduling
- Seasonality by country, return-rate outliers and the spread of sales per associate
- One-page dashboard with KPI cards, store ranking, day-of-week chart, country × month heatmap and slicers

### 2. Pricing, Promotions and Margin (SQL)

About one sale line in five is sold on markdown, and in 2024 the US and UK ran Zara's first Black Friday and an early Winter Sale.

- Data trust checks: invoice total mismatches, missing sizes and colours, impossible production costs, cross-store employees, never-sold products
- Yearly KPIs and gross margin % by category and sub-category
- Markdown depth bands and the depth at which a sale starts losing money
- Share of units sold on markdown per sub-category, to find overbought collections
- Sale-phase performance against the two weeks before, and a Black Friday / early sale comparison with the other countries as a control
- Monthly trend with `LAG()`, top products with `RANK()`, Pareto analysis with a running `SUM() OVER`
- Return rates by sub-category, size, country and price type, plus outlier products
- A reusable stored procedure, `promo_report`, taking a start date, end date and country

### 3. Customer and Sales Performance (Power BI)

Almost 600,000 identified customers, but the commercial team only reports total sales.

- Growth by country for 2023 vs 2024, and 1 Jan to 18 Mar 2025 vs the same dates in 2024
- New vs returning customers by month and quarterly cohort retention
- Customers whose first purchase was on markdown compared with full-price first buyers
- RFM segmentation and the revenue share of the top 20% of customers
- Category mix by gender and age band, tourist customers, and payment behaviour by country

Dashboard pages: **Executive Overview**, **Countries and Stores**, **Customers and Cohorts**, **Segments and Demographics**, **Seasonality and Payments**.

---

## Approach

1. **Business Framing (Part A)** — SCQ, issue trees, causal loop diagrams, stakeholder maps, personas, metric trees, AARRR funnel, opportunity solution tree, hypotheses and user stories written before any analysis.
2. **Analysis (Part B)** — Data cleaning and a Data Quality Log, a modelled dataset in each tool, and every business question answered with documented logic.
3. **Recommendations (Part C)** — Prioritised actions (impact–effort 2×2 and RICE scoring) each tied to the metric that will show whether it worked.
4. **Executive Summary** — An 8 to 10 slide deck with the top insight from each problem, prioritised recommendations and the metrics leadership should track.

---

## Tech Stack

```
Zara Capstone
├── Excel
│   ├── Power Query    → Group By summaries of 3.3M rows, currency conversion, translation
│   ├── Power Pivot    → Relational model with DAX measures
│   └── Dashboard      → Pivot charts, slicers, heatmap
├── MySQL
│   ├── Views          → USD sales and margin layer
│   ├── Window funcs   → LAG, RANK, ROW_NUMBER, running SUM
│   └── Procedures     → promo_report
└── Power BI
    ├── Power Query    → Translation, USD conversion, age bands
    ├── Star Schema    → transactions fact + customers, products, stores, employees, Date
    └── DAX            → Customer, retention, YoY / MoM / YTD and rolling measures
```

---

## Repository Structure

```
Anmol_Agarwal_Zara_Capstone
├── 01_framing/
│   ├── P1_Store_Operations_Framing.pdf
│   ├── P2_Merchandising_Framing.pdf
│   └── P3_Customer_Framing.pdf
├── 02_excel/
│   └── Zara_Store_Performance.xlsx         ← Power Query, Data Quality Log, model, dashboard
├── 03_sql/
│   ├── zara_pricing_margin.sql             ← Every query commented
│   └── Zara_SQL_Output_Slides.pptx         ← Each output with its takeaway
├── 04_powerbi/
│   ├── Zara_Customer_Dashboard.pbix        ← Five-page report
│   └── screenshots/                        ← Annotated page screenshots
├── 05_exec_deck/
│   └── Zara_Executive_Summary.pptx         ← 8 to 10 slide Demo Day deck
├── cover.png
└── README.md
```

---

## How to Use

1. Clone or download this repository.
2. The raw CSVs are not included because of file size. Download `Zara_Retail_Dataset.zip` separately.
3. Load the CSVs into MySQL, then run the queries in `03_sql/`.
4. Open the Excel workbook in Microsoft Excel (Power Pivot required) and use the slicers on the Dashboard sheet.
5. Open the `.pbix` file in Power BI Desktop and navigate the five report pages.

<!--
ADD AFTER THE ANALYSIS IS DONE (template conventions: real numbers only):

## Key Metrics at a Glance
| Metric | Value |
|---|---|
| Net sales 2024 (USD) | ... |
| Gross margin % | ... |
| Repeat customer rate | ... |

## Key Insights
1. **Problem 1 headline** — detail with numbers.
2. **Problem 2 headline** — detail with numbers.
3. **Problem 3 headline** — detail with numbers.

## Key Recommendations
| # | Recommendation |
|---|---|
| 01 | ... |
-->

---

## About Me

**Anmol Agarwal**
Business Analyst

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/anmol-agarwal123/)
[![GitHub](https://img.shields.io/badge/GitHub-Follow-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/Anmolagarwal19)
[![Email](https://img.shields.io/badge/Email-Contact-D14836?style=flat-square&logo=gmail&logoColor=white)](mailto:gungunagarwal763@gmail.com)

*If this project was useful, a star on the repo is appreciated — feel free to reach out for feedback, questions, or opportunities.*
