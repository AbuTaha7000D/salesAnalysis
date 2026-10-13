# Superstore Sales & Profitability Analysis

Analysis of the Tableau Superstore sample dataset, focusing on sales performance
and profitability across regions, categories, and customer segments.

## Dataset source

Tableau's official sample dataset:

- https://public.tableau.com/app/sample-data/sample_-_superstore.xls

The workbook is stored at `data/raw/sample_-_superstore.xls` and is not tracked by
Git. It contains three sheets: `Orders`, `People`, and `Returns`.

## Project scope

- Profile and clean the Superstore orders, people, and returns data.
- Explore sales and profit trends by time, region, category, and segment.
- Identify drivers of low/negative profit and assess return patterns.
- Produce summary tables, visualizations, and a written report of findings.

## Planned tools

- **Python / Pandas** — data loading, cleaning, and exploratory analysis
- **SQL / SQLite** — structured querying of the cleaned dataset
- **Power BI** — interactive dashboarding and reporting

## Repository layout

```
data/raw/         # Original source data (ignored by Git)
data/processed/   # Cleaned/derived data and the SQLite database (ignored by Git)
notebooks/        # Jupyter notebooks
sql/              # SQL schema and validation queries
scripts/          # Reproducible setup scripts
reports/          # Written reports and exported figures
```

## Database setup (SQLite)

Run the steps below in order, from the repository root:

1. Generate the processed CSV files by executing the cleaning notebook:

   ```bash
   .venv/bin/jupyter nbconvert --to notebook --execute --inplace notebooks/02_data_cleaning.ipynb
   ```

2. Create or rebuild the database. The loader uses only the Python standard
   library and is safe to re-run (tables are dropped and recreated first):

   ```bash
   .venv/bin/python scripts/load_superstore_db.py
   ```

3. Inspect the validation results with SQLite:

   ```bash
   sqlite3 -header -column data/processed/superstore.db < sql/02_validate_database.sql
   ```

Relevant files:

- `scripts/load_superstore_db.py` — loads the processed CSVs into the database
- `sql/01_create_database.sql` — schema (grain, types, keys, foreign key)
- `sql/02_validate_database.sql` — read-only validation queries
- `data/processed/superstore.db` — generated database (ignored by Git)
