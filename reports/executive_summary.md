# Executive Summary — Superstore Sales & Profitability Analysis

## About this report

This summary consolidates the read-only SQL analyses in `sql/03`–`sql/10`, executed against the SQLite database built by `sql/01` and `sql/02` (`data/processed/superstore.db`), which is loaded from the raw workbook `data/raw/sample_-_superstore.xls` by `scripts/load_superstore_db.py`. Every figure below was produced directly from that database.

**The dataset is fictitious.** The "Superstore" dataset is a synthetic sample commonly used for analytics practice; it does not describe a real company, market, or population, so absolute figures should be read as illustrative rather than representative of any real business.

Throughout this document:

- **Observed facts** are reported as query results.
- **Interpretations** are labelled and explain what the facts may suggest.
- **Recommendations** are labelled and are proposed actions, not proven outcomes.

All findings are **descriptive, not causal**. Observed associations between, for example, discounts and profit do not establish that one caused the other.

---

## 1. Executive Overview

### Scope
| Dimension | Value |
|---|---|
| Order lines (rows analyzed) | 10,194 |
| Distinct orders | 5,111 |
| Customers | 804 distinct customer IDs (800 distinct names) |
| Products | 1,862 distinct product IDs |
| Categories / sub-categories | 3 / 17 |
| Countries / regions / states-provinces | 2 / 4 / 59 |
| Cities | 542 |
| Ship modes | 4 |

### Period
Order dates run from **2023-01-03 to 2026-12-30**; ship dates run to 2027-01-05. The analysis date is **2026-10-13**. The data is retained in full: no rows are removed, no deduplication is performed, and no date filter is applied.

### Key limitations
- **Fictitious data.** Results illustrate analytical method, not a real business.
- **2026 is incomplete.** 2026 includes 1,106 order lines dated after the analysis date (see Section 3); 2026 totals are therefore year-to-date-plus-future, not a completed actual year.
- **Returns are order-level flags.** The `returns` table flags orders that appear as returned; it carries no refund amount or return date. Sales attributed to those orders are **not** confirmed refunds or confirmed losses (see Section 6).
- **Shipping duration is order-to-ship time**, measured as `Ship Date − Order Date` for an order. It is **not** delivery or transit time, and it does not describe how long a parcel took to reach the customer.
- **No cost, marketing, or inventory detail** is available, so profit here is the dataset's reported profit, and margin is a profit-to-sales ratio (`SUM(Profit) / SUM(Sales)`).
- **Grain matters.** The source is order-line level. Line measures (units, sales, profit) are additive; distinct order counts are not additive across overlapping groups, because one order can contain lines that fall into more than one group.

---

## 2. KPI Summary

| KPI | Value |
|---|---|
| Total sales | **$2,326,534.35** |
| Total profit | **$292,296.81** |
| Profit margin (`SUM(Profit) / SUM(Sales)`) | **12.56%** |
| Distinct orders | **5,111** |
| Units sold | **38,654** |
| Average order value (`SUM(Sales) / DISTINCT Orders`) | **$455.20** |
| Order return rate (returned orders / distinct orders) | **5.79%** (296 of 5,111) |

These totals reconcile exactly to the source table (10,194 lines, $2,326,534.35 sales, $292,296.81 profit, 38,654 units), and every grouping in `sql/03`–`sql/10` reproduces them.

**Observation.** The business is profitable overall at 12.56%, but that headline is a blend of strongly profitable and clearly unprofitable segments.

---

## 3. Sales Trends

| Year | Orders | Units | Sales | Profit | Margin | AOV |
|---|---|---|---|---|---|---|
| 2023 | 995 | 7,813 | $494,040.21 | $51,684.30 | 10.46% | $496.52 |
| 2024 | 1,053 | 8,086 | $472,993.03 | $62,020.97 | 13.11% | $449.19 |
| 2025 | 1,340 | 10,018 | $613,933.58 | $82,665.20 | 13.46% | $458.16 |
| 2026 | 1,723 | 12,737 | $745,567.53 | $95,926.35 | 12.87% | $432.71 |

**Observed facts.** Orders and units rose in every year of the period, and margin improved from 10.46% (2023) to roughly 13% by 2024–2025. Sales grew overall but did **not** rise every year: they dipped in 2024 to $472,993.03 from $494,040.21 in 2023 (a fall of $21,047.18), then climbed in 2025 and 2026. Average order value has drifted down slightly, from $496.52 (2023) to $432.71 (2026). The strongest sales months on record are **2026-11 ($118,454.51)**, **2025-12 ($97,502.28)**, and **2026-09 ($88,064.53)**; the weakest are **2023-02 ($4,519.89)**, **2024-02 ($11,951.41)**, and **2023-01 ($14,518.06)** (48 months in total).

**⚠ 2026 is not a completed actual year.** Of 2026's 3,379 lines, **1,106 lines (32.7%) are dated after the 2026-10-13 analysis date** (October–December 2026). These future-dated records are retained deliberately, not treated as invalid. As a result, 2026 figures include records beyond the reporting date and should **not** be compared to full prior years without this caveat. Note also that the single highest-sales month (2026-11) falls entirely in the future-dated window.

**Interpretation.** The multi-year growth in orders and units is genuine within these records, and sales finished 2026 above 2023 despite the 2024 dip; even so, year-over-year comparisons involving 2026 are distorted by future-dated entries and ought to be treated cautiously until 2026 is complete.

---

## 4. Product Profitability

### Category performance
| Category | Orders | Sales | Profit | Margin | Loss-making lines |
|---|---|---|---|---|---|
| Technology | 1,560 | $839,893.28 | $146,543.38 | 17.45% | 271 |
| Office Supplies | 3,812 | $731,893.31 | $126,023.44 | 17.22% | 898 |
| Furniture | 1,819 | $754,747.76 | $19,730.00 | 2.61% | 732 |

*Note: the `Orders` values in this table are not additive — an order can contain products from more than one category, so they sum to more than the 5,111 distinct orders overall (verified: 1,748 orders span multiple categories).*

**Observed facts.** Technology and Office Supplies both earn margins near 17%, while Furniture earns only 2.61% despite comparable sales. Furniture also accounts for a disproportionate share of loss-making lines.

### Sub-category performance (weakest first)
| Sub-category | Sales | Profit | Margin |
|---|---|---|---|
| Tables | $208,020.18 | **−$17,753.21** | −8.53% |
| Bookcases | $115,361.20 | **−$3,632.07** | −3.15% |
| Supplies | $46,725.50 | **−$1,171.39** | −2.51% |
| Machines | $189,925.03 | $3,461.98 | 1.82% |
| Chairs | $335,768.25 | $27,223.53 | 8.11% |
| Copiers (highest profit) | $150,745.29 | $56,093.94 | 37.21% |

**Notable loss-making products** (highest losses):
- Cubify CubeX 3D Printer, Double Head Print — $11,099.96 sales, **−$8,879.97** profit
- Lexmark MX611dhe Monochrome Laser Printer — $16,829.90 sales, **−$4,589.97**
- Cubify CubeX 3D Printer, Triple Head Print — $7,999.98 sales, **−$3,839.99**
- Chromcraft Bull-Nose Wood Oval Conference Tables & Bases — $9,917.64 sales, **−$2,876.12**
- GBC DocuBind P400 Electric Binding System — $17,965.07 sales, **−$1,878.17**

**Interpretation.** The drag on profitability is concentrated in high-ticket furniture (**Tables**, **Bookcases**) and a small set of expensive technology/office items. These associations are descriptive; the dataset does not reveal the underlying cost or pricing mechanics.

---

## 5. Discount Analysis

| Discount band | Lines | Sales | Profit | Margin | Loss-making lines |
|---|---|---|---|---|---|
| 0.00 (none) | 4,925 | $1,105,323.79 | $326,718.59 | **29.56%** | 0.0% |
| (0.00, 0.10] | 96 | $54,952.50 | $9,099.97 | 16.56% | 4.2% |
| (0.10, 0.20] | 3,758 | $801,497.92 | $92,498.94 | 11.54% | 14.0% |
| (0.20, 0.30] | 230 | $104,474.07 | −$10,513.45 | **−10.06%** | 91.7% |
| (0.30, 0.40] | 234 | $130,991.22 | −$25,477.51 | **−19.45%** | 88.9% |
| (0.40, 0.50] | 77 | $64,403.51 | −$22,999.54 | −35.71% | 100% |
| (0.50, 0.60] | 149 | $7,105.94 | −$6,164.35 | −86.75% | 100% |
| (0.60, 0.70] | 424 | $40,805.27 | −$40,300.57 | −98.76% | 100% |
| (0.70, 0.80] | 301 | $16,980.15 | −$30,565.27 | **−180.01%** | 100% |

**Observed facts.** About 51.7% of order lines carry a discount. Undiscounted lines are comfortably the most profitable (29.56% margin). Profitability declines steadily as the discount band rises, and **every band above 20% has a negative aggregate margin**; every band above 40% discount consists **entirely (100%) of loss-making lines**. Taken together, lines discounted more than 20% show an aggregate margin of about **−37.29%**.

**Interpretation (not causation).** Higher discount bands are associated with lower — and eventually negative — profitability. The data cannot show whether deep discounts *cause* losses, whether unprofitable products are discounted more heavily to move them, or whether some other factor drives both. The association is strong and consistent, but it is not proof of cause.

---

## 6. Customer, Regional, Geographic, Returns, and Shipping Insights

### Customers (`sql/08`)
- **804 distinct customer IDs** map to 800 distinct names; one name ("Harry Olson") is split across 5 customer IDs, so customers are grouped by ID, not name.
- **159 of 804 customers (about 20%) are loss-making** on an aggregate basis.
- Highest revenue customer **SM-20320** generated $25,043.05 in sales but **−$1,980.74** profit (−7.91%) — high volume does not guarantee profitability.
- The most profitable customers (e.g., **TC-20980** at $8,981.32 profit on $19,052.22 sales, 47.14% margin; **RB-19360** at $6,976.10, 46.15%) show that a small group contributes outsized profit.

### Regions and segments (`sql/06`)
| Region | Sales | Profit | Margin |
|---|---|---|---|
| West | $739,813.61 | $110,798.82 | **14.98%** |
| East | $691,828.17 | $94,883.26 | 13.71% |
| South | $391,721.91 | $46,749.43 | 11.93% |
| Central | $503,170.67 | $39,865.31 | **7.92%** |

By customer segment, **Home Office (14.02%)** and **Corporate (13.17%)** are more profitable than **Consumer (11.65%)**.

**Observation.** Central is the weakest region by margin despite solid sales volume, and Consumer is the least profitable segment.

### Geography (`sql/10`)
- **United States:** $2,297,200.86 sales, $286,397.02 profit (12.47%).
- **Canada:** $29,333.49 sales, $5,899.79 profit (**20.11%**). Canada is small but the most profitable country grouping.

Weakest states (loss-making):
| State | Sales | Profit | Margin |
|---|---|---|---|
| Texas | $170,188.05 | **−$25,729.36** | −15.12% |
| Ohio | $78,258.14 | **−$16,971.38** | −21.69% |
| Pennsylvania | $116,511.91 | **−$15,559.96** | −13.35% |
| Illinois | $80,166.10 | −$12,607.89 | −15.73% |
| North Carolina | $55,603.16 | −$7,490.91 | −13.47% |
| Colorado | $32,108.12 | −$6,527.86 | −20.33% |

Strongest states: **California** ($76,381.39 profit, 16.69%), **New York** ($74,038.55, 23.82%), **Washington** ($33,402.65), **Michigan** ($24,463.19, 32.07%).

**Observation.** A small number of states drive outsized losses — Texas and Ohio alone account for roughly $42,700 of negative profit — while a few large states carry the profitability.

### Returns (`sql/07`)
- **296 orders (5.79%)** appear in the returns table.
- Those orders cover **800 order lines** and **$180,504.28 in sales (7.76% of total sales)**, with $23,232.36 of the reported profit on those lines.
- **Return rate varies sharply by region:** West **11.56%** versus Central **3.31%**, East **2.98%**, and South **2.92%**.
- Among lines within returned orders, **Binders** (−$1,802.28 profit) are the largest loss-making sub-category.

**Interpretation and important caveat.** These are orders *flagged as returned*, not confirmed refunds. The dataset contains no refund amount, so sales and profit in returned orders should **not** be described as confirmed refunds or confirmed losses — only as activity associated with orders that appear in the returns table. The West's elevated return rate is a strong descriptive signal worth investigating operationally.

### Shipping (`sql/09`)
| Ship mode | Orders | Avg order-to-ship time |
|---|---|---|
| Standard Class | 3,068 | 4.99 days |
| Second Class | 982 | 3.23 days |
| First Class | 795 | 2.19 days |
| Same Day | 266 | 0.05 days |

Order-to-ship time is tightly grouped: 254 orders ship same day, 874 in 1–2 days, 1,950 in 3–4 days, 2,032 in 5–7 days, and only 1 order takes 8+ days. Regional medians are all 4 days.

**Interpretation.** "Order-to-ship" is the warehouse's processing time, not delivery time, so it cannot be used to assess customer-facing delivery speed. Median processing time is consistent across regions (4 days), while the average is pulled up by Standard Class.

---

## 7. Recommendations

*Ranked by expected value. All are interpretations built on the descriptive findings above and carry the caveats noted.*

1. **Investigate deep-discount lines (>20% off) as the first priority.** Every band above 20% runs at a negative aggregate margin, and every band above 40% is made up entirely (100%) of loss-making lines. *Action:* review pricing approval rules for high discounts and identify which products are routinely sold this way. *Caveat:* the data shows association, not causation — confirm whether removing deep discounts would protect margin without sacrificing volume.

2. **Address Furniture, and Tables/Bookcases specifically.** Furniture earns a 2.61% margin versus ~17% for the other categories, and Tables (−$17,753) and Bookcases (−$3,632) are the largest sub-category losses. *Action:* review sourcing, pricing, and discounting for high-ticket furniture, and evaluate the specific loss-making products listed in Section 4. *Caveat:* Furniture may still generate valuable order volume, so changes should be tested.

3. **Target the weakest regions and states.** Central (7.92%) trails other regions, and Texas, Ohio, and Pennsylvania concentrate losses. *Action:* run location-level margin reviews and align discount policy to regional profitability. *Caveat:* order counts are not additive across groups, and small locations can show volatile margins.

4. **Examine the West's elevated return rate (11.56%).** It is roughly 3.5–4 times the rate of the other regions (Central 3.31%, East 2.98%, South 2.92%). *Action:* investigate product mix, fulfillment, and customer expectations in the West. *Caveat:* returns are order-level flags with no refund value, so this should be treated as a signal to investigate, not a quantified loss.

5. **Protect and grow the most profitable customers and segments.** A small set of customers contributes outsized profit, and Home Office/Corporate segments outperform Consumer. *Action:* prioritize retention and expansion for high-margin accounts. *Caveat:* customer profitability is whole-period and unadjusted for returns.

6. **Improve average order value, which is trending down.** AOV fell from $496.52 (2023) to $432.71 (2026) even as order counts rose. *Action:* test bundling and cross-sell for low-AOV orders. *Caveat:* the 2026 AOV figure includes future-dated records.

7. **Re-run the 2026 analysis once the year is complete.** 32.7% of 2026 lines are future-dated relative to 2026-10-13, including the highest-sales month (2026-11). *Action:* re-baseline annual comparisons after year-end. *Caveat:* no records were excluded here, so current 2026 figures are provisional.

---

## Reproduction

| Item | Location |
|---|---|
| Schema | `sql/01_create_database.sql` |
| Validation checks | `sql/02_validate_database.sql` |
| Trend / product / discount / regional / returns / customer / shipping / geography queries | `sql/03` … `sql/10` |
| Database builder | `scripts/load_superstore_db.py` |
| Database (generated, Git-ignored) | `data/processed/superstore.db` |
| Data understanding / cleaning | `notebooks/01_data_understanding.ipynb`, `notebooks/02_data_cleaning.ipynb` |

All queries in `sql/03`–`sql/10` are read-only `SELECT` statements. Metrics use the shared definitions `sales = SUM("Sales")`, `profit = SUM("Profit")`, `profit_margin = SUM("Profit") / NULLIF(SUM("Sales"), 0)`, `orders = COUNT(DISTINCT "Order ID")`, `units_sold = SUM("Quantity")`, and `avg_order_value = SUM("Sales") / NULLIF(COUNT(DISTINCT "Order ID"), 0)`.
