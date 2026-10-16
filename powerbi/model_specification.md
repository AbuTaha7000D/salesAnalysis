# Power BI Model Specification — Superstore Sales & Profitability Analysis

This document specifies the Power BI data model for this project: table grains,
keys, dimensions, relationships, filter directions, and date handling. It is
written to be reproducible from the cleaned data and consistent with the verified
SQL analyses in `sql/01`–`sql/10` and `reports/executive_summary.md`.

The companion measure library is `measures.dax`; setup and refresh steps are in
`README.md`.

The underlying data and analytical results in this document were verified against
`data/processed/superstore.db`. The Power BI star schema described here is a
**reference / target design**, not a verified description of the deployed Power BI
Service model: Power BI Desktop is Windows-only and was not run here (see `README.md`),
so the Service report's actual tables and relationships have not been inspected.

---

## 1. Source tables (from the SQLite database)

| Table | Grain | Rows | Key | Notes |
|---|---|---:|---|---|
| `orders` | **order line** (one row per product line) | 10,194 | `Row ID` (unique) | `Order ID` intentionally repeats (5,111 distinct). 21 columns. |
| `people` | one row per **region** | 4 | `Region` | Reference only: `Regional Manager` per `Region`. |
| `returns` | one row per **returned order** | 296 | `Order ID` (unique) | Flag table: only `Returned = "Yes"`; no amount, no return date. |

`orders` fields: `Row ID`, `Order ID`, `Order Date`, `Ship Date`, `Ship Mode`,
`Customer ID`, `Customer Name`, `Segment`, `Country/Region`, `City`,
`State/Province`, `Postal Code`, `Region`, `Product ID`, `Category`,
`Sub-Category`, `Product Name`, `Sales`, `Quantity`, `Discount`, `Profit`.

`people` fields: `Regional Manager`, `Region`.
`returns` fields: `Order ID`, `Returned`.

**Grain rule:** measures sum line rows for `Sales`/`Profit`/`Quantity`, and count
orders with `DISTINCTCOUNT` (never `COUNTROWS`), because `orders` is line-level.

---

## 2. Verified model facts

| Fact | Value |
|---|---|
| Order lines / distinct orders | 10,194 / 5,111 |
| Customers (IDs / names) | 804 / 800 |
| Products (IDs / names) | 1,862 / 1,849 |
| Product IDs with >1 name | **32** |
| Categories / sub-categories | 3 / 17 |
| Countries / regions / states / cities | 2 / 4 / 59 / 542 |
| Ship modes | 4 |
| Order date range | 2023-01-03 → 2026-12-30 |
| Ship date range | 2023-01-07 → **2027-01-05** (46 lines in 2027) |
| Future-dated lines (after 2026-10-13) | **1,106** (32.7% of 2026's 3,379 lines) |
| Discount range / distinct values | 0.0 → 0.8 / 12 |
| `Product ID` → `Category`/`Sub-Category` | functional (0 exceptions) |
| `Customer ID` → `Customer Name`/`Segment` | functional (0 exceptions) |
| `Region` constant within (`Country/Region`,`State/Province`) | yes (0 exceptions) |
| Distinct (`Country/Region`,`State/Province`,`Region`) | 59 |
| Orders spanning >1 category | 1,748 |
| Orders spanning >1 customer ID | 2 |
| Orders spanning >1 region/country/segment/ship mode | 0 |

Baseline KPIs for cross-checking measures: **sales $2,326,534.35**,
**profit $292,296.81**, **margin 12.56%**, **orders 5,111**, **units 38,654**,
**AOV $455.20**, **return rate 5.79%** (296 / 5,111).

---

## 3. Recommended model (star schema)

```
                 Date (1) ─────────┐  active: Order Date
                                   │  inactive: Ship Date (USERELATIONSHIP)
                 Customers (1) ────┤
                                   ├──< Orders (many, line grain)
                 Products (1) ─────┤
                                   │
                 Geography (1) ────┘
                 Returns (1) ──────────< Orders   (single direction)
```

- **Fact:** `Orders` (line grain; keep `Row ID`).
- **Dimensions:** `Date`, `Customers`, `Products`, `Geography`.
- **Flag table:** `Returns` (order-level membership; not a slicable dimension).

### 3.1 `Date` (calculated table)

Covers the full first year and through the last ship date, so that Ship Date
analyses never produce blank dates:

```dax
Date =
VAR MinDate = DATE ( 2023, 1, 1 )    -- earliest order is 2023-01-03
VAR MaxDate = DATE ( 2027, 12, 31 )  -- latest ship date is 2027-01-05
RETURN
ADDCOLUMNS (
    CALENDAR ( MinDate, MaxDate ),
    "Year",             YEAR ( [Date] ),
    "Quarter",          "Q" & QUARTER ( [Date] ),
    "Month",            FORMAT ( [Date], "MMM" ),
    "Month Number",     MONTH ( [Date] ),
    "Year Month",       FORMAT ( [Date], "YYYY-MM" ),
    "Year Month Sort",  YEAR ( [Date] ) * 100 + MONTH ( [Date] ),
    "Day of Week",      WEEKDAY ( [Date], 2 )
)
```

Mark `Date` as the model **date table** (Table tools → Mark as date table →
`Date[Date]`).

### 3.2 `Customers` (calculated table)

Keyed by `Customer ID` (804 unique). `Customer Name` and `Segment` are
functional per ID, so this produces no duplicate keys:

```dax
Customers =
SUMMARIZE (
    Orders,
    Orders[Customer ID],
    Orders[Customer Name],
    Orders[Segment]
)
```

Group customers by `Customer ID`, never by name: 804 IDs map to only 800 names
(one name, "Harry Olson", is split across 5 IDs).

### 3.3 `Products` (calculated table)

Keyed by `Product ID` (1,862 unique). **32 IDs carry two different names**, so a
plain `SUMMARIZE ( …, Product ID, Product Name )` would create duplicate keys.
Resolve to one representative name and keep an ambiguity flag:

```dax
Products =
SUMMARIZE (
    Orders,
    Orders[Product ID],
    Orders[Category],
    Orders[Sub-Category],
    "Product Name",       MIN ( Orders[Product Name] ),
    "Product Name Count", DISTINCTCOUNT ( Orders[Product Name] )
)
```

```dax
Products[Has Ambiguous Name] =
IF ( Products[Product Name Count] > 1, "Yes", "No" )
```

`Category` and `Sub-Category` are constant per `Product ID`, so no duplicate keys
or many-to-many relationship result. Key by `Product ID`; surface
`Has Ambiguous Name = "Yes"` where name precision matters.

### 3.4 `Geography` (calculated table)

One geography dimension that keeps `Country/Region` and `Region` as **separate**
fields, plus the regional manager folded in from `people`. Keyed by a composite
`GeographyKey` = `Country/Region | State/Province` (59 rows, unique):

```dax
Geography =
ADDCOLUMNS (
    SUMMARIZE ( Orders, Orders[Country/Region], Orders[State/Province], Orders[Region] ),
    "GeographyKey",     [Country/Region] & " | " & [State/Province],
    "Regional Manager", LOOKUPVALUE ( People[Regional Manager], People[Region], [Region] )
)
```

Add the matching key on the fact:

```dax
Orders[GeographyKey] = Orders[Country/Region] & " | " & Orders[State/Province]
```

Load `People` (4 rows) as a hidden reference table so `LOOKUPVALUE` resolves; it
is **not** related to `Orders`, which avoids a second geography path. `Region` is
a manager grouping shared across countries (Canada uses Central/East/West only),
so keep `Country/Region` and `Region` distinct. City-level analysis would extend
the key to `Country/Region | State/Province | City` (616 combinations) if needed.

---

## 4. Relationships and filter directions

| From (one) | To (many) | Cardinality | Cross-filter | Status |
|---|---|---|---|---|
| `Date[Date]` | `Orders[Order Date]` | 1 : many | Single | **Active** |
| `Date[Date]` | `Orders[Ship Date]` | 1 : many | Single | Inactive (use `USERELATIONSHIP`) |
| `Customers[Customer ID]` | `Orders[Customer ID]` | 1 : many | Single | Active |
| `Products[Product ID]` | `Orders[Product ID]` | 1 : many | Single | Active |
| `Geography[GeographyKey]` | `Orders[GeographyKey]` | 1 : many | Single | Active |
| `Returns[Order ID]` | `Orders[Order ID]` | 1 : many | **Single** | Active |

**All relationships are single-direction (one → many). No bidirectional
filtering is used.**

- `Returns` → `Orders` deliberately flows one way (Returns filters Orders).
  Return **measures are defined over `Orders`** (see `measures.dax`) so they
  inherit date/region/category/customer filters through that single direction.
  A bidirectional relationship was rejected: it is unnecessary and risks
  ambiguous filter paths once several dimensions are present.
- Do not add two active paths to `Orders` (for example a separate `Region`
  dimension alongside `Geography`). Manager is folded into `Geography`.

### Date handling

- `Date[Date]` → `Orders[Order Date]` is the **active** relationship; all default
  time intelligence uses it.
- `Date[Date]` → `Orders[Ship Date]` is **inactive**. Activate it per measure
  with `USERELATIONSHIP` for ship-date analyses:
  `CALCULATE ( [Total Sales], USERELATIONSHIP ( Orders[Ship Date], 'Date'[Date] ) )`.
- The calendar runs to **2027-12-31** so the 2027 ship dates are not blank.

---

## 5. How the known modeling issues are resolved

1. **Returned Orders** — defined as
   `CALCULATE ( DISTINCTCOUNT ( Orders[Order ID] ), Returns[Returned] = "Yes" )`.
   It counts orders from `Orders`, not from `Returns`, so it responds to
   date/region/category/customer filters. `DISTINCTCOUNT ( Returns[Order ID] )` is
   **not** used (it would be a filter-blind constant 296).
2. **Returns → Orders relationship** stays **single-direction**; no bidirectional
   cross-filter is introduced.
3. **Products** are keyed by `Product ID`; the 32 multi-name IDs are collapsed to
   a representative name via `MIN`, with `Product Name Count` and
   `Has Ambiguous Name` to avoid duplicate dimension keys.
4. **Date table** runs through **2027-12-31**; the active Order Date relationship
   and the `USERELATIONSHIP` pattern for Ship Date are documented above.
5. **One geography dimension** (`Geography`) with `Country/Region` and `Region`
   kept distinct; `People` is hidden and folded in rather than related.

---

## 6. Data-quality caveats the dashboard must preserve

- **Incomplete / future-dated 2026.** 1,106 order lines (32.7% of 2026) are dated
  after the analysis date **2026-10-13**; the latest order is 2026-12-30. Do not
  silently exclude them, and label 2026 as **provisional/incomplete**. The
  highest-sales month (2026-11) is entirely future-dated, so year-over-year
  comparisons involving 2026 are distorted.
- **Returns are flags, not refunds.** `returns` records only that an order
  appears as returned (`Returned = "Yes"`); it has **no refund amount or return
  date**. Values such as `Returned Order Sales` ($180,504.28 overall) are sales on
  lines belonging to flagged orders, and must never be presented as confirmed
  refunds or confirmed losses.
- **Return counts are non-additive.** Returned-**order** counts stack across
  slices: by category they sum to **493** vs **296** overall (1,748 orders span
  multiple categories). Returned **sales** are additive and reconcile to
  $180,504.28. Never sum distinct-return counts across groups.
- **Distinct order counts are non-additive in general.** Because `orders` is
  line-level, always use the `DISTINCTCOUNT` measures; do not add order counts
  across category/customer slices (2 orders also span customer IDs).
- **Name ambiguity.** 804 customer IDs → 800 names; 1,862 product IDs → 1,849
  names (32 IDs with two names). Key and group by ID; flag product names when
  `Has Ambiguous Name = "Yes"`.
- **`Postal Code` is text** (leading zeros preserved as-is). Keep it as a text
  attribute, never a number.
- **Do not deduplicate.** Repeated order lines (including 11 repeated
  `Order ID`+`Product ID` pairs and 4 rows duplicated ignoring `Row ID`) are
  intentional; `Row ID` is the line key.
- **Discount** is bounded 0.0–0.8; use the project's half-open bands if
  replicating `sql/05`.

---

## 7. Validation performed

The schema, fields, keys, and counts in this document were checked directly
against `data/processed/superstore.db` with read-only SQL:

- Table/row counts: `orders` 10,194; `people` 4; `returns` 296; 21 columns in
  `orders`.
- Cardinalities as listed in §2 (customers, products, geography, dates, discount,
  future-dated lines).
- Key viability: exactly **1,862** rows for `SUMMARIZE`-equivalent
  (`Product ID`,`Category`,`Sub-Category`); exactly **59** rows for
  (`Country/Region`,`State/Province`,`Region`); 0 functional-dependency
  exceptions for product category, customer name/segment, and region-per-state.
- The return DAX logic matches SQL results: overall 296 returned orders / 5.79%
  / $180,504.28, and per-year (2023: 53 / $29,219.55; 2024: 61 / $39,660.89;
  2025: 77 / $36,121.77; 2026: 105 / $75,502.06).

Limitations: DAX was not executed (no Power BI Desktop on Linux); it is written to
the documented model and cross-checked against equivalent SQL. The measures
assume the relationships and keys in §4.
