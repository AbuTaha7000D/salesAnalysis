#!/usr/bin/env python3
"""Render the analytical charts embedded in the Markdown reports.

Reproducibility. The charts are **not** driven by hand-typed KPI values. Every
data point is read from the same read-only SQL statements that produced the
verified results published in ``reports/``:

* ``sql/03_sales_trends.sql`` statement 1      -> monthly sales and profit
* ``sql/04_product_profitability.sql`` stmt 1  -> profit margin by category
* ``sql/05_discount_analysis.sql`` statement 1 -> profitability by discount band
* ``sql/07_returns_analysis.sql`` statement 2  -> return rate by region

Those statements are read from the ``sql/`` files, stripped of their comment
lines and split on ``;``, then executed against the generated SQLite database.
Nothing is recomputed with a different definition, so a chart can never disagree
with the report tables built from the same queries.

The database is opened read-only (``mode=ro``) and this script never writes to
``data/``: it only produces PNG files in ``reports/figures/``.

All paths are resolved relative to the repository (based on this file's
location), so the script can be run from any working directory.

Usage:
    python scripts/generate_figures.py
"""

from __future__ import annotations

import sqlite3
import sys
import textwrap
from pathlib import Path

try:
    import matplotlib

    matplotlib.use("Agg")  # render to files; no display is required

    import matplotlib.pyplot as plt
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    from matplotlib.ticker import FuncFormatter, PercentFormatter
except ImportError as error:  # pragma: no cover - environment setup only
    print(
        "ERROR: Matplotlib is required to render the report charts but could not be "
        f"imported ({error}).\n"
        "Install it with `pip install matplotlib`, or follow the 'Reproducible setup' "
        "section of README.md.",
        file=sys.stderr,
    )
    sys.exit(1)

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
SQL_DIRECTORY = REPO_ROOT / "sql"
DATABASE_PATH = REPO_ROOT / "data" / "processed" / "superstore.db"
FIGURES_DIRECTORY = REPO_ROOT / "reports" / "figures"

# The project's fixed reporting date. Never derived from the wall clock.
ANALYSIS_DATE = pd.Timestamp("2026-10-13")

# Published figures used to guard the chart inputs against silent drift.
EXPECTED_TOTAL_LINES = 10_194
EXPECTED_TOTAL_ORDERS = 5_111
EXPECTED_SALES = 2_326_534.35
EXPECTED_PROFIT = 292_296.81
EXPECTED_FUTURE_LINES = 1_106
EXPECTED_RETURNED_ORDERS = 296
EXPECTED_CATEGORY_MARGIN = {"Technology": 0.1745, "Office Supplies": 0.1722, "Furniture": 0.0261}
EXPECTED_BAND_MARGIN = [0.2956, 0.1656, 0.1154, -0.1006, -0.1945, -0.3571, -0.8675, -0.9876, -1.8001]
EXPECTED_REGION_RATE = {"West": 0.1156, "Central": 0.0331, "East": 0.0298, "South": 0.0292}

# Discount bands are defined in sql/05_discount_analysis.sql as nine fixed
# categories: no discount, then eight 10-percentage-point half-open intervals.
# The labels below are the documented band definitions, used to validate both
# the SQL output and the labels rendered on the chart.
DISCOUNT_BAND_WIDTH = 0.10
EXPECTED_BAND_SQL_LABELS = [
    "0.00 (no discount)",
    "(0.00, 0.10]",
    "(0.10, 0.20]",
    "(0.20, 0.30]",
    "(0.30, 0.40]",
    "(0.40, 0.50]",
    "(0.50, 0.60]",
    "(0.60, 0.70]",
    "(0.70, 0.80]",
]
EXPECTED_BAND_LABELS = [
    "0% (none)",
    "(0%, 10%]",
    "(10%, 20%]",
    "(20%, 30%]",
    "(30%, 40%]",
    "(40%, 50%]",
    "(50%, 60%]",
    "(60%, 70%]",
    "(70%, 80%]",
]

# Shared palette: keeps the four charts visually consistent.
COLOR_POSITIVE = "#2f7d4f"
COLOR_NEGATIVE = "#c0392b"
COLOR_PRIMARY = "#1f4e79"
COLOR_SECONDARY = "#e67e22"
COLOR_REFERENCE = "#6b7280"
COLOR_TITLE = "#111827"
COLOR_BODY = "#374151"
COLOR_MUTED = "#4b5563"

SOURCE_FOOTER = (
    "Source: Tableau Superstore sample (synthetic data). Order-line grain, n=10,194 lines / 5,111 "
    "orders; no rows removed, no de-duplication, no date filter. Analysis date 2026-10-13. "
    "Regenerate: python scripts/generate_figures.py  |  Queries: sql/03, sql/04, sql/05, sql/07."
)

TITLE_POINTSIZE = 15.0
BODY_POINTSIZE = 9.6
FOOTER_POINTSIZE = 7.6

plt.rcParams.update(
    {
        "figure.dpi": 150,
        "savefig.dpi": 150,
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.labelsize": 10.5,
        "axes.edgecolor": "#4b5563",
        "axes.linewidth": 0.9,
        "axes.grid": True,
        "grid.color": "#9ca3af",
        "grid.alpha": 0.35,
        "grid.linestyle": "--",
        "axes.axisbelow": True,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "xtick.color": "#111827",
        "ytick.color": "#111827",
        "legend.frameon": False,
        "legend.fontsize": 9,
        "figure.facecolor": "white",
        "axes.unicode_minus": False,
    }
)


class FigureDataError(RuntimeError):
    """Raised when a chart input no longer matches the published results."""


# ---------------------------------------------------------------------------
# Data access (read-only)
# ---------------------------------------------------------------------------
def load_statements(sql_path: Path) -> list[str]:
    """Return the executable statements of a SQL file, in file order.

    Comment lines are dropped (SQL comments in this repository always occupy a
    full line) and the remainder is split on ``;``.
    """
    text = sql_path.read_text(encoding="utf-8")
    code_lines = [line for line in text.splitlines() if not line.lstrip().startswith("--")]
    return [statement.strip() for statement in "\n".join(code_lines).split(";") if statement.strip()]


def read_statement(connection: sqlite3.Connection, sql_name: str, index: int) -> pd.DataFrame:
    """Execute statement ``index`` of ``sql/`` file ``sql_name`` read-only."""
    statements = load_statements(SQL_DIRECTORY / sql_name)
    if index >= len(statements):
        raise FigureDataError(
            f"{sql_name}: expected at least {index + 1} statements, found {len(statements)}. "
            "Statement numbering in scripts/generate_figures.py needs updating."
        )
    return pd.read_sql_query(statements[index], connection)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FigureDataError(message)


# ---------------------------------------------------------------------------
# Layout helpers -- measured wrapping and explicit space reservation
# ---------------------------------------------------------------------------
def wrap_width(width_in: float, font_pointsize: float, margin: float = 0.96) -> int:
    """Characters that fit on one line at ``font_pointsize`` inside ``width_in``.

    Calibrated at 150 dpi for DejaVu Sans: average advance width is ~0.52 of the
    point size, so chars = width_in * dpi * margin / (font_pt * dpi / 72 * 0.52)
    = width_in * 134 * margin / font_pt (dpi cancels out).
    """
    return max(24, int(width_in * 134.0 * margin / font_pointsize))


def place_header(figure: plt.Figure, title: str, blocks: list[dict]) -> float:
    """Draw the title block and return the figure fraction the axes may start at.

    Each block is ``{"text": ..., "fontsize": ..., "color": ..., "style": ...}``.
    Text is wrapped to the figure width so the canvas never has to grow, and the
    returned value already includes the drawn height plus a gap.
    """
    width_in, height_in = figure.get_size_inches()
    margin_left = 0.008
    y = 1.0 - 0.012
    figure.text(margin_left, y, title, ha="left", va="top",
                fontsize=TITLE_POINTSIZE, fontweight="bold", color=COLOR_TITLE)
    y -= (TITLE_POINTSIZE * 1.30) / 72 / height_in
    y -= 0.055 / height_in

    for block in blocks:
        pointsize = block.get("fontsize", BODY_POINTSIZE)
        lines = textwrap.fill(block["text"], wrap_width(width_in, pointsize)).split("\n")
        line_height = pointsize * 1.36 / 72 / height_in
        for line in lines:
            figure.text(margin_left, y, line, ha="left", va="top", fontsize=pointsize,
                        color=block.get("color", COLOR_BODY),
                        style=block.get("style", "normal"))
            y -= line_height
        y -= 0.022 / height_in

    return max(y - 0.030 / height_in, 0.5)


def place_footer(figure: plt.Figure, text: str) -> float:
    """Draw the source note at the bottom and return the fraction it occupies."""
    width_in, height_in = figure.get_size_inches()
    lines = textwrap.fill(text, wrap_width(width_in, FOOTER_POINTSIZE, margin=0.985)).split("\n")
    line_height = FOOTER_POINTSIZE * 1.34 / 72 / height_in
    top = 0.012 + line_height * len(lines)
    y = top
    for line in lines:
        figure.text(0.008, y, line, ha="left", va="top",
                    fontsize=FOOTER_POINTSIZE, color=COLOR_MUTED)
        y -= line_height
    return top


def dollars(value: float) -> str:
    return f"${value:,.0f}"


def discount_band_label(band_order: int) -> str:
    """Compact axis label for a half-open discount band (lower bound exclusive).

    Boundaries come from the fixed band definition (10-point intervals starting
    at zero), never from the observed minimum/maximum discount in each band.
    """
    if band_order == 0:
        return "0% (none)"
    lower = (band_order - 1) * DISCOUNT_BAND_WIDTH
    upper = band_order * DISCOUNT_BAND_WIDTH
    return f"({lower:.0%}, {upper:.0%}]"


def provisional_breakdown(rows: list[tuple[str, int]]) -> str:
    """Compact '(2026-10 / 11 / 12: 164 / 460 / 482)' text from query rows.

    The year is shown once when every month shares it, matching the chart's
    existing callout style; otherwise each month keeps its full ``YYYY-MM``.
    """
    if not rows:
        return ""
    months = [month for month, _ in rows]
    counts = " / ".join(f"{count:,}" for _, count in rows)
    if len({month[:4] for month in months}) == 1:
        month_text = f"{months[0][:4]}-" + " / ".join(month[5:] for month in months)
    else:
        month_text = " / ".join(months)
    return f"({month_text}: {counts})"


def money_tick(value: float, _position: int) -> str:
    """Axis value in thousands, with the sign placed before the dollar sign."""
    sign = "-" if value < 0 else ""
    return f"{sign}${abs(value) / 1000:,.0f}k"


def money_axis() -> FuncFormatter:
    return FuncFormatter(money_tick)


def save_figure(figure: plt.Figure, filename: str) -> Path:
    FIGURES_DIRECTORY.mkdir(parents=True, exist_ok=True)
    destination = FIGURES_DIRECTORY / filename
    figure.savefig(destination, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    print(f"  wrote {destination.relative_to(REPO_ROOT)}")
    return destination


# ---------------------------------------------------------------------------
# Chart 1 -- monthly sales and profit trends, cutoff-aware
# ---------------------------------------------------------------------------
def chart_monthly_trends(
    monthly: pd.DataFrame, future_lines: int, future_by_month: list[tuple[str, int]]
) -> Path:
    data = monthly.copy()
    data["date"] = pd.to_datetime(data["month"] + "-01")
    provisional_month = ANALYSIS_DATE.to_period("M").to_timestamp()
    is_provisional = data["date"] >= provisional_month
    plot_end = data["date"].max() + pd.Timedelta(days=45)

    figure, (axis_sales, axis_profit) = plt.subplots(2, 1, figsize=(11, 8.2), sharex=True)

    panels = (
        (axis_sales, "sales", "Monthly sales (USD)", COLOR_PRIMARY),
        (axis_profit, "profit", "Monthly profit (USD)", COLOR_SECONDARY),
    )

    for axis, column, label, color in panels:
        axis.plot(data["date"], data[column], color=color, lw=1.7, marker="o", ms=3.8, zorder=4)
        # Overlay the months that contain records dated after the analysis date.
        flagged = data[is_provisional]
        axis.plot(
            flagged["date"],
            flagged[column],
            color=COLOR_NEGATIVE,
            lw=1.7,
            ls="--",
            marker="s",
            ms=6,
            mfc="white",
            mew=1.5,
            zorder=5,
        )
        axis.axvspan(ANALYSIS_DATE, plot_end, color=COLOR_NEGATIVE, alpha=0.07, zorder=1)
        axis.axvline(ANALYSIS_DATE, color=COLOR_NEGATIVE, ls=":", lw=1.5, zorder=3)
        axis.axhline(0, color="#111827", lw=0.9, zorder=3)
        axis.set_ylabel(label, fontsize=10.5)
        axis.yaxis.set_major_formatter(money_axis())

    # The callout sits in the empty upper-left of the sales panel: 2023 sales
    # peak at $82.7k, so nothing is drawn above ~82% of the axis height there.
    callout = (
        "Provisional window\n"
        f"{future_lines:,} order lines dated after {ANALYSIS_DATE.date().isoformat()}"
    )
    breakdown = provisional_breakdown(future_by_month)
    if breakdown:
        callout += f"\n{breakdown}"
    axis_sales.annotate(
        callout,
        xy=(0.015, 0.985),
        xycoords="axes fraction",
        ha="left",
        va="top",
        fontsize=8.8,
        color=COLOR_NEGATIVE,
        linespacing=1.45,
        bbox={"boxstyle": "round,pad=0.4", "fc": "white", "ec": COLOR_NEGATIVE, "alpha": 0.95, "lw": 1.0},
        zorder=6,
    )

    axis_profit.set_xlabel("Order month (48 months, 2023-01 to 2026-12)", fontsize=10.5)
    axis_profit.tick_params(axis="x", rotation=45, labelsize=8.6)

    top = place_header(
        figure,
        "Monthly sales and profit, with the 2026-10-13 analysis cutoff",
        [
            {
                "text": "Sales recovered after the 2024 dip and 2025-2026 run above 2023, but the "
                        "shaded months are provisional: they contain future-dated records kept on "
                        "purpose, so 2026 is not a completed year.",
            },
            {
                "text": "Solid line + filled dot = recorded month.   Dashed line + open square = "
                        "month also holds records dated after the cutoff.   Dotted rule = analysis date 2026-10-13.",
                "fontsize": 8.6,
                "color": COLOR_MUTED,
            },
        ],
    )

    footer_top = place_footer(figure, SOURCE_FOOTER)
    legend_bottom = footer_top + 0.010
    legend_height = 0.030
    figure.legend(
        handles=[
            Line2D([], [], color=COLOR_PRIMARY, lw=1.7, marker="o", ms=4.5, label="monthly sales (top panel)"),
            Line2D([], [], color=COLOR_SECONDARY, lw=1.7, marker="o", ms=4.5, label="monthly profit (bottom panel)"),
            Line2D([], [], color=COLOR_NEGATIVE, lw=1.5, ls=":", label="analysis date 2026-10-13"),
        ],
        loc="lower center",
        bbox_to_anchor=(0.5, legend_bottom),
        ncol=3,
        fontsize=8.6,
    )
    # Reserve: footer + legend + rotated month labels + axis label.
    figure.subplots_adjust(top=top, bottom=legend_bottom + legend_height + 0.115)
    return save_figure(figure, "01_monthly_sales_profit.png")


# ---------------------------------------------------------------------------
# Chart 2 -- profit margin by category
# ---------------------------------------------------------------------------
def chart_category_margin(category: pd.DataFrame) -> Path:
    data = category.sort_values("profit_margin").reset_index(drop=True)
    # Overall margin, recomputed from the same query output (never typed in).
    overall = category["profit"].sum() / category["sales"].sum()

    figure, axis = plt.subplots(figsize=(9.4, 6.2))
    colors = [COLOR_NEGATIVE if margin < overall else COLOR_POSITIVE for margin in data["profit_margin"]]
    axis.bar(data["category"], data["profit_margin"] * 100, color=colors, width=0.55, zorder=3)

    for position, row in data.iterrows():
        margin = row["profit_margin"] * 100
        axis.text(
            position,
            margin + 1.6,
            f"{margin:.2f}%\n{dollars(row['profit'])}",
            ha="center",
            va="bottom",
            fontsize=9.8,
            fontweight="bold",
            color=COLOR_TITLE,
            linespacing=1.3,
        )

    axis.axhline(overall * 100, color=COLOR_REFERENCE, ls="--", lw=1.4, zorder=4)
    axis.text(0.015, overall * 100 + 0.5, f"overall {overall:.2%}",
              transform=axis.get_yaxis_transform(),
              ha="left", va="bottom", fontsize=9, color=COLOR_REFERENCE)

    axis.set_ylim(0, 26)
    axis.set_ylabel("Profit margin  (SUM(Profit) / SUM(Sales))", fontsize=10.5)
    axis.yaxis.set_major_formatter(PercentFormatter(xmax=100, decimals=0))
    axis.legend(
        handles=[
            Patch(facecolor=COLOR_POSITIVE, label=f"above the {overall:.2%} overall margin"),
            Patch(facecolor=COLOR_NEGATIVE, label=f"below the {overall:.2%} overall margin"),
        ],
        loc="upper left",
        ncol=1,
    )

    top = place_header(
        figure,
        "Profit margin by category",
        [
            {
                "text": "Furniture earns a fraction of the other categories' margin on comparable "
                        "sales: 2.61% against ~17% for Technology (17.45%) and Office Supplies "
                        "(17.22%), while the three categories are similar in sales.",
            },
            {
                "text": "Margin is a whole-period group ratio over order lines; it is descriptive, "
                        "not causal. Category order counts are non-additive (1,748 orders span "
                        "categories), so only line-level sums should be added.",
                "fontsize": 8.8,
                "color": COLOR_MUTED,
            },
        ],
    )
    footer_top = place_footer(figure, SOURCE_FOOTER)
    figure.subplots_adjust(top=top, bottom=footer_top + 0.075, left=0.095, right=0.985)
    return save_figure(figure, "02_profit_margin_by_category.png")


# ---------------------------------------------------------------------------
# Chart 3 -- profitability by discount band
# ---------------------------------------------------------------------------
def chart_discount_bands(bands: pd.DataFrame) -> Path:
    data = bands.reset_index(drop=True)
    margins = data["profit_margin"] * 100
    colors = [COLOR_POSITIVE if value >= 0 else COLOR_NEGATIVE for value in margins]

    figure, axis = plt.subplots(figsize=(11, 6.8))
    positions = list(range(len(data)))
    axis.bar(positions, margins, color=colors, width=0.66, zorder=3)

    for position, (_, row) in enumerate(data.iterrows()):
        margin = row["profit_margin"] * 100
        axis.text(
            position,
            margin + (6 if margin >= 0 else -6),
            f"{margin:.1f}%\nn={int(row['order_lines']):,}",
            ha="center",
            va="bottom" if margin >= 0 else "top",
            fontsize=8.8,
            fontweight="bold",
            linespacing=1.35,
        )

    axis.axhline(0, color="#111827", lw=1.0, zorder=4)
    axis.set_xticks(positions)
    axis.set_xticklabels(
        [discount_band_label(int(row.band_order)) for row in data.itertuples()],
        fontsize=9.5,
    )
    axis.set_ylim(-215, 55)
    axis.set_xlabel("Discount band (half-open: lower bound exclusive, upper bound inclusive)", fontsize=10.5)
    axis.set_ylabel("Aggregate profit margin", fontsize=10.5)
    axis.yaxis.set_major_formatter(PercentFormatter(xmax=100, decimals=0))
    axis.legend(
        handles=[
            Patch(facecolor=COLOR_POSITIVE, label="positive aggregate margin"),
            Patch(facecolor=COLOR_NEGATIVE, label="negative aggregate margin"),
        ],
        loc="upper right",
        ncol=1,
    )

    top = place_header(
        figure,
        "Profit margin by discount band",
        [
            {
                "text": "Margin falls monotonically with discount depth: every band above 20% is "
                        "loss-making, and every band above 40% is made up entirely of loss-making "
                        "lines (100%). Undiscounted lines carry 29.56%.",
            },
            {
                "text": "Association, not causation: discounts are not assigned at random and may be "
                        "applied to already weak products, so the data cannot show whether discounts "
                        "cause the losses. Sparse high-discount bands (n=77 to n=424) are volatile - "
                        "read n with every bar.",
                "fontsize": 9.0,
                "color": COLOR_NEGATIVE,
                "style": "italic",
            },
        ],
    )
    footer_top = place_footer(figure, SOURCE_FOOTER)
    figure.subplots_adjust(top=top, bottom=footer_top + 0.085, left=0.075, right=0.985)
    return save_figure(figure, "03_discount_band_margin.png")


# ---------------------------------------------------------------------------
# Chart 4 -- return rate by region
# ---------------------------------------------------------------------------
def chart_region_returns(regions: pd.DataFrame) -> Path:
    data = regions.sort_values("return_rate", ascending=False).reset_index(drop=True)
    values = data["return_rate"] * 100
    colors = [COLOR_NEGATIVE if value == values.max() else COLOR_PRIMARY for value in values]

    figure, axis = plt.subplots(figsize=(9.4, 6.2))
    axis.bar(data["group_value"], values, color=colors, width=0.58, zorder=3)

    for position, row in data.iterrows():
        axis.text(
            position,
            row["return_rate"] * 100 + 0.3,
            f"{row['return_rate']:.2%}\n{int(row['returned_orders']):,} of {int(row['orders']):,} orders",
            ha="center",
            va="bottom",
            fontsize=9.6,
            fontweight="bold",
            linespacing=1.35,
        )

    axis.set_ylim(0, 15)
    axis.set_ylabel("Return rate  (returned orders / orders)", fontsize=10.5)
    axis.yaxis.set_major_formatter(PercentFormatter(xmax=100, decimals=0))
    axis.legend(
        handles=[
            Patch(facecolor=COLOR_NEGATIVE, label="West: 3.5-4x every other region"),
            Patch(facecolor=COLOR_PRIMARY, label="Central, East, South"),
        ],
        loc="upper right",
        ncol=1,
    )

    top = place_header(
        figure,
        "Return rate by region",
        [
            {
                "text": "Returns concentrate sharply in the West at 11.56% (189 of 1,635 orders), "
                        "against 2.9-3.3% in Central, East and South.",
            },
            {
                "text": "Caveat: returns are order-level flags, not confirmed refunds. The dataset "
                        "carries no refund amount and no return date, so this is a signal to "
                        "investigate operationally, not a measured loss. Return status applies to "
                        "the whole order, not to individual lines.",
                "fontsize": 9.0,
                "color": COLOR_NEGATIVE,
                "style": "italic",
            },
        ],
    )
    footer_top = place_footer(figure, SOURCE_FOOTER)
    figure.subplots_adjust(top=top, bottom=footer_top + 0.075, left=0.095, right=0.985)
    return save_figure(figure, "04_return_rate_by_region.png")


# ---------------------------------------------------------------------------
# Validation -- guard every chart input against the published results
# ---------------------------------------------------------------------------
def validate(
    connection: sqlite3.Connection,
    monthly: pd.DataFrame,
    category: pd.DataFrame,
    bands: pd.DataFrame,
    regions: pd.DataFrame,
) -> tuple[int, list[tuple[str, int]]]:
    totals = connection.execute(
        'SELECT COUNT(*), COUNT(DISTINCT "Order ID"), ROUND(SUM("Sales"), 2), ROUND(SUM("Profit"), 2) FROM orders'
    ).fetchone()
    require(totals == (EXPECTED_TOTAL_LINES, EXPECTED_TOTAL_ORDERS, EXPECTED_SALES, EXPECTED_PROFIT),
            f"database totals drifted: {totals}")

    future_lines = connection.execute(
        'SELECT COUNT(*) FROM orders WHERE "Order Date" > ?', (ANALYSIS_DATE.date().isoformat(),)
    ).fetchone()[0]
    require(future_lines == EXPECTED_FUTURE_LINES,
            f"future-dated line count drifted: {future_lines} != {EXPECTED_FUTURE_LINES}")

    # Per-month breakdown of the future-dated lines, so the chart callout is
    # built from the query rather than typed into the figure.
    future_by_month = connection.execute(
        'SELECT substr("Order Date", 1, 7) AS month, COUNT(*) AS lines FROM orders '
        'WHERE "Order Date" > ? GROUP BY month ORDER BY month',
        (ANALYSIS_DATE.date().isoformat(),),
    ).fetchall()
    require(sum(count for _, count in future_by_month) == future_lines,
            "monthly future-dated breakdown does not reconcile to the total line count")

    require(len(monthly) == 48, f"expected 48 months, found {len(monthly)}")
    # The SQL rounds each month to 2 decimals before returning it, so summing the
    # series can drift by up to half a cent per month from the whole-period total.
    tolerance = 0.005 * len(monthly)
    sales_gap = abs(round(monthly["sales"].sum(), 2) - EXPECTED_SALES)
    profit_gap = abs(round(monthly["profit"].sum(), 2) - EXPECTED_PROFIT)
    require(sales_gap <= tolerance,
            f"monthly sales do not reconcile to the total (gap {sales_gap:.2f} > {tolerance:.2f})")
    require(profit_gap <= tolerance,
            f"monthly profit does not reconcile to the total (gap {profit_gap:.2f} > {tolerance:.2f})")

    observed_categories = dict(zip(category["category"], category["profit_margin"]))
    require(observed_categories == EXPECTED_CATEGORY_MARGIN,
            f"category margins drifted: {observed_categories}")

    require(len(bands) == 9, f"expected 9 discount bands, found {len(bands)}")
    require(list(bands["band_order"]) == list(range(9)),
            f"unexpected discount band order: {list(bands['band_order'])}")
    observed_band_labels = list(bands["discount_band"])
    require(observed_band_labels == EXPECTED_BAND_SQL_LABELS,
            f"discount band definitions drifted: {observed_band_labels}")
    rendered_band_labels = [discount_band_label(int(order)) for order in bands["band_order"]]
    require(rendered_band_labels == EXPECTED_BAND_LABELS,
            f"rendered discount band labels do not match the documented bands: {rendered_band_labels}")
    require(int(bands["order_lines"].sum()) == EXPECTED_TOTAL_LINES, "discount bands do not cover every line")
    observed_bands = bands["profit_margin"].tolist()
    require(observed_bands == EXPECTED_BAND_MARGIN, f"discount band margins drifted: {observed_bands}")

    require(int(regions["returned_orders"].sum()) == EXPECTED_RETURNED_ORDERS,
            "regional returned orders do not reconcile to 296")
    observed_rates = dict(zip(regions["group_value"], regions["return_rate"]))
    require(observed_rates == EXPECTED_REGION_RATE, f"regional return rates drifted: {observed_rates}")

    print("  validation: all chart inputs match the published results")
    return future_lines, future_by_month


def main() -> int:
    if not DATABASE_PATH.exists():
        raise FigureDataError(
            f"database not found at {DATABASE_PATH}. "
            "Rebuild it first: python scripts/load_superstore_db.py"
        )

    print(f"Reading {DATABASE_PATH.relative_to(REPO_ROOT)} (read-only)")
    connection = sqlite3.connect(f"file:{DATABASE_PATH}?mode=ro", uri=True)
    try:
        monthly = read_statement(connection, "03_sales_trends.sql", 0)
        category = read_statement(connection, "04_product_profitability.sql", 0)
        bands = read_statement(connection, "05_discount_analysis.sql", 0)
        region_segment = read_statement(connection, "07_returns_analysis.sql", 1)
        # sql/07 statement 2 returns rows labelled by dimension (region, segment);
        # this chart plots the region rows only.
        regions = region_segment[region_segment["dimension"] == "region"].reset_index(drop=True)

        future_lines, future_by_month = validate(connection, monthly, category, bands, regions)
    finally:
        connection.close()

    print("Rendering figures")
    chart_monthly_trends(monthly, future_lines, future_by_month)
    chart_category_margin(category)
    chart_discount_bands(bands)
    chart_region_returns(regions)
    print("Done.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except FigureDataError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
