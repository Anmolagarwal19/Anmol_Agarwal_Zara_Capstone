"""
Load the six Zara CSV files into MySQL.

Before running:
  pip install pandas mysql-connector-python
  1. Edit the CONFIG block below (host, user, password, folder).
  2. Check the file names in CSV_FILES match your unzipped files.
Column names are cleaned: spaces become underscores (Store ID -> Store_ID).
"""
import os
import pandas as pd
import mysql.connector

# ---------------- CONFIG ----------------
HOST = "localhost"
USER = "root"
PASSWORD = "your_password"
DATABASE = "zara"
FOLDER = r"C:\path\to\Zara_Retail_Dataset"   # folder holding the CSVs
CHUNK_ROWS = 50_000

# (csv file name, table name) - check these against your actual files
CSV_FILES = [
    ("stores.csv", "stores"),
    ("employees.csv", "employees"),
    ("customers.csv", "customers"),
    ("products.csv", "products"),
    ("discounts.csv", "discounts"),
    ("transactions.csv", "transactions"),
]
# ----------------------------------------

INT_COLS = {"Store_ID", "Employee_ID", "Customer_ID", "Product_ID", "Line",
            "Quantity", "Number_of_Employees"}
DECIMAL_COLS = {"Unit_Price", "Line_Total", "Invoice_Total", "Production_Cost",
                "Discount", "Discont", "Latitude", "Longitude"}
DATETIME_COLS = {"Date"}  # transactions.Date has a time part
DATE_COLS = {"Date_Of_Birth", "Launch_Date", "Start", "End"}


def clean(col):
    return col.strip().replace(" ", "_").replace("-", "_").replace(".", "_")


def sql_type(col):
    if col in INT_COLS:
        return "BIGINT"
    if col in DECIMAL_COLS:
        return "DECIMAL(16,4)"
    if col in DATETIME_COLS:
        return "DATETIME"
    if col in DATE_COLS:
        return "DATE"
    return "VARCHAR(255)"


conn = mysql.connector.connect(host=HOST, user=USER, password=PASSWORD,
                               charset="utf8mb4", allow_local_infile=False)
cur = conn.cursor()
cur.execute(f"CREATE DATABASE IF NOT EXISTS `{DATABASE}` CHARACTER SET utf8mb4")
cur.execute(f"USE `{DATABASE}`")

for csv_name, table in CSV_FILES:
    path = os.path.join(FOLDER, csv_name)
    print(f"\nLoading {csv_name} -> {table}")
    cur.execute(f"DROP TABLE IF EXISTS `{table}`")

    created = False
    total = 0
    # dtype=str keeps everything as text; MySQL converts to the column type on insert
    for chunk in pd.read_csv(path, dtype=str, keep_default_na=False,
                             encoding="utf-8-sig", chunksize=CHUNK_ROWS):
        chunk.columns = [clean(c) for c in chunk.columns]

        if not created:
            cols = ", ".join(f"`{c}` {sql_type(c)}" for c in chunk.columns)
            cur.execute(f"CREATE TABLE `{table}` ({cols}) CHARACTER SET utf8mb4")
            col_list = ", ".join(f"`{c}`" for c in chunk.columns)
            placeholders = ", ".join(["%s"] * len(chunk.columns))
            insert_sql = f"INSERT INTO `{table}` ({col_list}) VALUES ({placeholders})"
            created = True

        # empty strings become NULL
        rows = [tuple(None if v == "" else v for v in r)
                for r in chunk.itertuples(index=False, name=None)]
        cur.executemany(insert_sql, rows)
        conn.commit()
        total += len(rows)
        print(f"  {total:,} rows", end="\r")

    print(f"  done: {total:,} rows")

# indexes for fast joins and filters
print("\nCreating indexes...")
for stmt in [
    "CREATE INDEX ix_t_store ON transactions(Store_ID)",
    "CREATE INDEX ix_t_emp   ON transactions(Employee_ID)",
    "CREATE INDEX ix_t_prod  ON transactions(Product_ID)",
    "CREATE INDEX ix_t_cust  ON transactions(Customer_ID)",
    "CREATE INDEX ix_t_date  ON transactions(`Date`)",
    "CREATE INDEX ix_t_inv   ON transactions(Invoice_ID)",
    "CREATE INDEX ix_e_store ON employees(Store_ID)",
]:
    try:
        cur.execute(stmt)
    except mysql.connector.Error as e:
        print("  skipped:", e)

conn.commit()
conn.close()
print("All done.")
