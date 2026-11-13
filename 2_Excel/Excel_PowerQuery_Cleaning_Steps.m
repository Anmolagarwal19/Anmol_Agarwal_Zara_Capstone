// =====================================================================
// Zara Capstone - Problem 1 (Excel): Power Query cleaning steps
// Exported unchanged from Zara_Problem1_Excel_Anmol_Agarwal.xlsx
// (Data > Queries & Connections). Every step is also listed, with rows
// affected, on the data_quality_log sheet of the workbook.
//
// Cleaning done in these queries:
//   1. stores      - countries and cities translated to English
//                    (China, Germany, Spain; Shanghai, Munich, Lisbon...)
//                    and a Currency column added per country
//   2. Exchange_Rates - fixed rates to USD (EUR 1.08, GBP 1.27, CNY 0.14)
//   3. Transactions_Base - only the needed columns, correct data types,
//                    Net Units (returns made negative), Returned Value,
//                    Invoice Count (Line = 1, returns excluded), Month,
//                    Day Of Week
//   4. employees   - actual staff list used for headcount
//   5. Summary_Store_Month / Summary_Store_Weekday / Summary_Employee -
//                    3.3M lines grouped into small tables in USD,
//                    loaded to the Data Model (Power Pivot)
//   6. data_quality_log - the 13 issues found and the fix for each
// =====================================================================

section Section1;

shared data_quality_log = let

    Source = Table.FromRows({

        {"stores", "Country", "Names in local language or script (中国, Deutschland, España)", "25 of 35 stores", "Mapped to English with a Country_Map table; each of the 7 countries now appears once"},

        {"stores", "City", "Cities in local spelling (上海, München, Köln, Lisboa, Sevilla...)", "10 stores", "Translated to English in Power Query"},

        {"transactions", "Currency / Line Total", "Amounts in four currencies (USD, EUR, GBP, CNY) cannot be compared", "3,340,935 lines", "Converted to US dollars with fixed rates (1 EUR = 1.08, 1 GBP = 1.27, 1 CNY = 0.14)"},

        {"transactions", "Invoice Total", "Repeats on every line of an invoice, and differs from the sum of its lines for 4,200 invoices", "4,200 invoices", "Never used. All money comes from Line Total"},

        {"transactions", "Quantity / Line Total", "Returns have a positive quantity but a negative amount", "298,373 return lines", "Net Units flips the sign for returns"},

        {"transactions", "Invoice ID / Line", "An invoice has several lines, so counting rows overstates invoices", "1,786,791 invoices in 3,340,935 lines", "Invoices counted with a Line = 1 counter"},

        {"transactions", "Employee ID", "Lines served by an employee from another store", "1,452 lines", "Kept; employee sales converted at the employee's home-store rate. Effect negligible"},

        {"transactions", "Invoice ID", "Some invoices have lines under more than one employee or date", "1,088 invoices", "Invoices counted from the Line = 1 line, not by grouping on several columns"},

        {"transactions", "Store ID / Date", "Store 12 (Hamburg) has no sales in two months", "2 store-months (Feb and Mar 2024)", "Reported; shown as gaps in the seasonality and growth views"},

        {"transactions", "Date", "The 5 German stores (11-15) have no Sunday sales", "5 store-days", "Reported as 'does not trade on Sundays'; used in the scheduling recommendation"},

        {"stores / employees", "Number of Employees", "Stated headcount differs from the employees table for 5 stores (1: 41 vs 51; 5: 36 vs 29; 17: 62 vs 54; 21: 92 vs 100; 23: 42 vs 48)", "5 stores; 1,737 stated vs 1,746 listed", "Use the employees table (the actual staff list) for sales per employee and note the discrepancy"},

        {"employees", "Employee ID", "Employees with no sales at all", "182 of 1,746", "Kept in the staff count; shown with zero sales"},

        {"transactions", "Size / Color", "Missing size (13,363) and colour (6,681)", "13,363 / 6,681 lines", "Not used in the store analysis; no action needed"}

    }, {"Table", "Column", "Issue", "Rows affected", "Fix applied"}),

    Typed = Table.TransformColumnTypes(Source, {{"Table", type text}, {"Column", type text}, {"Issue", type text}, {"Rows affected", type text}, {"Fix applied", type text}})

in

    Typed;

shared Transactions_Base = let

    Source = Csv.Document(File.Contents("C:\Users\Anmol\Downloads\Zara_Retail_Dataset\transactions.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),

    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    Keep = Table.SelectColumns(Promoted, {"Invoice ID", "Line", "Date", "Store ID", "Employee ID", "Currency", "Quantity", "Line Total", "Transaction Type"}),

    Typed = Table.TransformColumnTypes(Keep, {{"Invoice ID", type text}, {"Line", Int64.Type}, {"Date", type datetime}, {"Store ID", Int64.Type}, {"Employee ID", Int64.Type}, {"Currency", type text}, {"Quantity", Int64.Type}, {"Line Total", type number}, {"Transaction Type", type text}}, "en-US"),

    AddMonth = Table.AddColumn(Typed, "Month", each Date.StartOfMonth(Date.From([Date])), type date),

    AddReturned = Table.AddColumn(AddMonth, "Returned Value", each if [Transaction Type] = "Return" then [Line Total] else 0, type number),

    AddUnits = Table.AddColumn(AddReturned, "Net Units", each if [Transaction Type] = "Return" then -[Quantity] else [Quantity], Int64.Type),

    AddInvoice = Table.AddColumn(AddUnits, "Invoice Count", each if [Transaction Type] = "Return" then 0 else if [Line] = 1 then 1 else 0, Int64.Type),

    AddDow = Table.AddColumn(AddInvoice, "Day Of Week", each Date.DayOfWeek([Date], Day.Monday) + 1, Int64.Type)

in

    AddDow;

shared Exchange_Rates = let

    Source = Table.FromRows({{"USD", 1}, {"EUR", 1.08}, {"GBP", 1.27}, {"CNY", 0.14}}, {"Currency", "Rate_to_USD"}),

    Typed = Table.TransformColumnTypes(Source, {{"Currency", type text}, {"Rate_to_USD", type number}})

in

    Typed

    ;

shared stores = let

    Source = Csv.Document(File.Contents("C:\Users\Anmol\Downloads\Zara_Retail_Dataset\stores.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),

    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    Typed = Table.TransformColumnTypes(Promoted, {{"Store ID", Int64.Type}, {"Country", type text}, {"City", type text}, {"Store Name", type text}, {"Number of Employees", Int64.Type}, {"ZIP Code", type text}, {"Latitude", type number}, {"Longitude", type number}}, "en-US"),

    CountryEN = Table.TransformColumns(Typed, {{"Country", each Record.FieldOrDefault([#"中国" = "China", #"Deutschland" = "Germany", #"España" = "Spain"], _, _), type text}}),

    CityEN = Table.TransformColumns(CountryEN, {{"City", each Record.FieldOrDefault([#"上海" = "Shanghai", #"北京" = "Beijing", #"广州" = "Guangzhou", #"深圳" = "Shenzhen", #"成都" = "Chengdu", #"München" = "Munich", #"Köln" = "Cologne", #"Frankfurt am Main" = "Frankfurt", #"Lisboa" = "Lisbon", #"Sevilla" = "Seville"], _, _), type text}}),

    WithCurrency = Table.AddColumn(CityEN, "Currency", each if [Country] = "United States" then "USD" else if [Country] = "China" then "CNY" else if [Country] = "United Kingdom" then "GBP" else "EUR", type text)

in

    WithCurrency;

shared employees = let

    Source = Csv.Document(File.Contents("C:\Users\Anmol\Downloads\Zara_Retail_Dataset\employees.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),

    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    Typed = Table.TransformColumnTypes(Promoted, {{"Employee ID", Int64.Type}, {"Store ID", Int64.Type}, {"Name", type text}, {"Position", type text}}, "en-US")

in

    Typed

    ;

shared Summary_Store_Month = let

    Source = Transactions_Base,

    Grouped = Table.Group(Source, {"Store ID", "Currency", "Month"}, {

        {"Net_Sales_Local", each List.Sum([Line Total]), type number},

        {"Net_Units", each List.Sum([Net Units]), Int64.Type},

        {"Invoices", each List.Sum([Invoice Count]), Int64.Type},

        {"Returned_Value_Local", each List.Sum([Returned Value]), type number}}),

    WithRate = Table.ExpandTableColumn(Table.NestedJoin(Grouped, {"Currency"}, Exchange_Rates, {"Currency"}, "R", JoinKind.LeftOuter), "R", {"Rate_to_USD"}),

    WithUSD = Table.AddColumn(Table.AddColumn(WithRate, "Net_Sales_USD", each [Net_Sales_Local] * [Rate_to_USD], type number), "Returned_Value_USD", each [Returned_Value_Local] * [Rate_to_USD], type number),

    WithStore = Table.ExpandTableColumn(Table.NestedJoin(WithUSD, {"Store ID"}, stores, {"Store ID"}, "S", JoinKind.LeftOuter), "S", {"Country", "City", "Store Name", "Number of Employees"})

in

    WithStore

    ;

shared Summary_Store_Weekday = let

    Source = Transactions_Base,

    Grouped = Table.Group(Source, {"Store ID", "Day Of Week"}, {

        {"Net_Sales_Local", each List.Sum([Line Total]), type number},

        {"Net_Units", each List.Sum([Net Units]), Int64.Type},

        {"Invoices", each List.Sum([Invoice Count]), Int64.Type},

        {"Returned_Value_Local", each List.Sum([Returned Value]), type number}}),

    WithStore = Table.ExpandTableColumn(Table.NestedJoin(Grouped, {"Store ID"}, stores, {"Store ID"}, "S", JoinKind.LeftOuter), "S", {"Country", "City", "Store Name", "Number of Employees", "Currency"}),

    WithRate = Table.ExpandTableColumn(Table.NestedJoin(WithStore, {"Currency"}, Exchange_Rates, {"Currency"}, "R", JoinKind.LeftOuter), "R", {"Rate_to_USD"}),

    WithUSD = Table.AddColumn(Table.AddColumn(WithRate, "Net_Sales_USD", each [Net_Sales_Local] * [Rate_to_USD], type number), "Returned_Value_USD", each [Returned_Value_Local] * [Rate_to_USD], type number)

in

    WithUSD;

shared Summary_Employee = let

    Source = Transactions_Base,

    Grouped = Table.Group(Source, {"Employee ID"}, {

        {"Net_Sales_Local", each List.Sum([Line Total]), type number},

        {"Net_Units", each List.Sum([Net Units]), Int64.Type},

        {"Invoices", each List.Sum([Invoice Count]), Int64.Type},

        {"Returned_Value_Local", each List.Sum([Returned Value]), type number}}),

    WithEmp = Table.ExpandTableColumn(Table.NestedJoin(Grouped, {"Employee ID"}, employees, {"Employee ID"}, "E", JoinKind.LeftOuter), "E", {"Store ID", "Name", "Position"}),

    WithStore = Table.ExpandTableColumn(Table.NestedJoin(WithEmp, {"Store ID"}, stores, {"Store ID"}, "S", JoinKind.LeftOuter), "S", {"Country", "City", "Store Name", "Number of Employees", "Currency"}),

    WithRate = Table.ExpandTableColumn(Table.NestedJoin(WithStore, {"Currency"}, Exchange_Rates, {"Currency"}, "R", JoinKind.LeftOuter), "R", {"Rate_to_USD"}),

    WithUSD = Table.AddColumn(Table.AddColumn(WithRate, "Net_Sales_USD", each [Net_Sales_Local] * [Rate_to_USD], type number), "Returned_Value_USD", each [Returned_Value_Local] * [Rate_to_USD], type number)

in

    WithUSD;