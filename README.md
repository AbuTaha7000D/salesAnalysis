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
data/processed/   # Cleaned/derived data (ignored by Git)
notebooks/        # Jupyter notebooks
sql/              # SQL queries and schema
reports/          # Written reports and exported figures
```
