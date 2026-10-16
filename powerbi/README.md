# Power BI Model & DAX Library

Reference specification and DAX measure library for the
Superstore Sales & Profitability Analysis project. It reuses the verified results
in `sql/01`–`sql/10` and `reports/executive_summary.md`; no new analysis findings
are introduced.

## Contents

| File | Purpose |
|---|---|
| `model_specification.md` | Tables, grains, keys, dimensions, relationships, filter directions, date handling, and data-quality caveats. Also holds the calculated table/column DAX (Date, Customers, Products, Geography). |
| `measures.dax` | Standalone DAX measure library: core KPIs, YoY sales, order-grain order-to-ship days, return measures, and a discount helper. |

## Source of truth

The reference model is built from the cleaned data produced by the project notebooks:

- Raw workbook: `data/raw/sample_-_superstore.xls` (out of scope to modify).
- Cleaning/decisions: `notebooks/02_data_cleaning.ipynb`.
- Reproducible database: `data/processed/superstore.db` (SQLite). The schema is
  defined by `sql/01_create_database.sql`; the database is created/loaded by
  `scripts/load_superstore_db.py`; `sql/02_validate_database.sql` contains
  validation queries only.
- Verified totals: `data/processed/superstore.db` (orders 10,194 lines / 5,111
  orders; sales 2,326,534.35; profit 292,296.81).

## Setup (build a Power BI model from scratch)

Power BI Desktop is **Windows-only**. It was **not** run for this repository
(Linux environment), so no `.pbix` is committed and no desktop validation is
claimed. The steps below reproduce the documented model on Windows.

1. **Generate the data (clean checkout).** `data/` is Git-ignored, so neither the
   raw workbook nor the processed files are in the repository. Provide the raw
   workbook at `data/raw/sample_-_superstore.xls`, then run the two steps below
   from the repository root (the same workflow as the root `README.md`):

   a. Generate the processed CSV files by executing the cleaning notebook:

      ```bash
      .venv/bin/jupyter nbconvert --to notebook --execute --inplace notebooks/02_data_cleaning.ipynb
      ```

   b. Create/load the SQLite database from those CSVs with the loader:

      ```bash
      .venv/bin/python scripts/load_superstore_db.py
      ```

   This produces `data/processed/superstore.db`.

2. **Connect Power BI** to the data. Either:
   - **SQLite (recommended, single source):** install the SQLite ODBC driver on
     Windows, point `Get Data → ODBC` at `data/processed/superstore.db`, and
     import `orders`, `people`, `returns`; or
   - **CSV:** import the processed CSVs from `data/processed/`.

3. **Create the calculated tables and columns** exactly as written in
   `model_specification.md` §3:
   - `Date` (Calendar 2023-01-01 → 2027-12-31) and mark it as the date table.
   - `Customers`, `Products` (keyed by `Product ID`), `Geography`, plus the
     `Orders[GeographyKey]` calculated column.

4. **Create the relationships** in `model_specification.md` §4 — all
   **single-direction** (one → many). Confirm the Order Date relationship is
   active and the Ship Date relationship is inactive.

5. **Add the measures** from `measures.dax` (paste into the model; set the
   formats noted in the comments).

6. **Cross-check:** the core measures should reproduce sales 2,326,534.35,
   profit 292,296.81, margin 12.56%, orders 5,111, units 38,654, AOV 455.20, and
   return rate 5.79% (296 / 5,111) with no filters applied.

## Refresh

- **New data:** replace `data/raw/sample_-_superstore.xls`, then re-run the
  cleaning notebook to regenerate the processed CSV files and the loader to
  rebuild the database:

  ```bash
  .venv/bin/jupyter nbconvert --to notebook --execute --inplace notebooks/02_data_cleaning.ipynb
  .venv/bin/python scripts/load_superstore_db.py
  ```

  Then **Refresh** in Power BI (ODBC/CSV path unchanged).
- **Model-only changes:** Refresh is not required for the calculated tables, but
  re-check that the `Date` calendar still covers all order and ship dates if the
  data window changes.

## Important caveats (see `model_specification.md` §6)

- **2026 is incomplete / future-dated:** 1,106 lines are dated after 2026-10-13
  (the latest order is 2026-12-30); label 2026 as provisional and avoid
  over-reading YoY comparisons involving it.
- **Returns are flags, not refunds:** `returns` has no refund amount or return
  date.
- **Order and return counts are non-additive** across slices; always use the
  `DISTINCTCOUNT` measures and never sum distinct counts across groups.
- Names are ambiguous for 32 product IDs (and 800 customer names vs 804 IDs);
  key and group by ID.

## Report output

The interactive report lives in **Power BI Service**. Exported assets committed to this
repository:

- [`docs/screenshots/powerbi-report-overview.jpg`](../docs/screenshots/powerbi-report-overview.jpg) — 2000 px screenshot of the single report page
- [`docs/powerbi-report-superstore.pdf`](../docs/powerbi-report-superstore.pdf) — full-resolution PDF export (1 page)

The report **visuals are not part of any file in this repository's model**; they exist in
Power BI Service and in the two exports above.

## Scope and limitations

- No `.pbix` is committed; no Power BI Desktop validation was performed on Linux.
- This change does not modify the SQL analyses, the executive summary, the
  notebooks, `requirements.txt`, or the raw data.
