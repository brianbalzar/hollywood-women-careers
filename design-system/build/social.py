#!/usr/bin/env python3
"""Render square 1200x1200 social cards from the project's result tables.

Same tokens, same palette, same accuracy rules as the report figures — but
composed for a feed: the headline carries the finding, type is sized to survive
a phone-sized thumbnail, and every card names its source.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import TOKENS_CSS, CHART_JS

import paths as P

ROOT = P.ROOT
OUT = P.SOCIAL                 # cards live at <repo>/social/
os.makedirs(OUT, exist_ok=True)
D = P.load_tables()            # straight from <repo>/outputs/tables/*.csv

role = {}
for r in D["women_role_share"]:
    role.setdefault(r["scope"], []).append([int(r["age"]), float(r["women_coded_share"])])
for k in role:
    role[k].sort()
hz = sorted([[int(r["age"]), float(r["women_exit_hazard"]), float(r["men_exit_hazard"]),
              float(r["exit_hazard_ratio"])] for r in D["adjusted_exit_hazard_ratio"]])
bshare = sorted([[int(r["age"]), float(r["women_share"])] for r in D["billboard_women_share_by_age"]])

sa = lambda s, a: next(v for x, v in role[s] if x == a)
hr30 = next(r[3] for r in hz if r[0] == 30)

# --------------------------------------------------------------- card styling
SOCIAL_CSS = """
*, *::before, *::after { box-sizing: border-box; }
body { margin: 0; font-family: var(--font-sans); background: var(--page-plane); }
.card {
  width: 1200px; height: 1200px; background: var(--surface-1);
  display: flex; flex-direction: column;
  padding: 74px 76px 60px; position: relative;
}
.kicker {
  font-size: 21px; font-weight: var(--fw-label); letter-spacing: .13em; text-transform: uppercase;
  color: var(--series-1); margin: 0 0 26px;
}
h1 {
  font-family: var(--font-serif);
  font-size: 62px; font-weight: var(--fw-label); letter-spacing: -0.028em; line-height: 1.1;
  color: var(--text-primary); margin: 0 0 22px; max-width: 20ch;
}
h1.tight { font-size: 56px; }
.sub {
  font-size: 25px; line-height: 1.42; color: var(--text-secondary);
  margin: 0 0 30px; max-width: 40ch;
}
.legend {
  display: flex; gap: 30px; margin: 0 0 12px; padding: 0; list-style: none;
  font-size: 23px; color: var(--text-secondary); font-weight: var(--fw-medium);
}
.legend li { display: flex; align-items: center; gap: 11px; }
.legend .key { width: 26px; height: 5px; border-radius: 3px; }
.legend .key.ghost { background: var(--series-ghost); }
.plot { flex: 1 1 auto; display: flex; align-items: center;
  justify-content: center; min-height: 0; }
.chart-wrap { width: 100%; max-height: 100%; display: flex; }
.chart { width: 100%; height: auto; max-height: 100%; display: block; overflow: visible; }
.chart text { font-family: var(--font-sans); }
.ax-label { font-size: 21px; fill: var(--text-muted); font-variant-numeric: tabular-nums; }
.ax-title { font-size: 22px; fill: var(--text-secondary); font-weight: var(--fw-medium); }
.grid { stroke: var(--gridline); stroke-width: 1.5; shape-rendering: crispEdges; }
.axis-rule { stroke: var(--baseline); stroke-width: 1.5; shape-rendering: crispEdges; }
.ref-rule { stroke: var(--text-muted); stroke-width: 1.5; opacity: .55; }
.ref-label { font-size: 20px; fill: var(--text-muted);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 6px; stroke-linejoin: round; }
.series-line { fill: none; stroke-width: 4.5; stroke-linejoin: round; stroke-linecap: round; }
.series-band { stroke: none; opacity: .13; }
.ghost-line { fill: none; stroke: var(--series-ghost); stroke-width: 3; stroke-linejoin: round; }
.end-dot { stroke: var(--surface-1); stroke-width: 4; }
.end-label { font-size: 25px; font-weight: var(--fw-label); fill: var(--text-primary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 7px; stroke-linejoin: round; }
.mark-value { font-size: 28px; font-weight: var(--fw-label); fill: var(--text-primary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 8px; stroke-linejoin: round; }
.mark-label { font-size: 21px; font-weight: var(--fw-medium); fill: var(--text-secondary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 8px; stroke-linejoin: round; }
.annot { font-size: 21px; fill: var(--text-secondary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 7px; stroke-linejoin: round; }
.annot-rule { stroke: var(--text-muted); stroke-width: 1.5; opacity: .5; }
.panel-title { font-size: 24px; font-weight: var(--fw-label); fill: var(--text-primary); }
.hit, .crosshair, .tip { display: none; }
footer {
  border-top: 1px solid var(--hairline); padding-top: 22px; margin-top: 26px;
  display: flex; justify-content: space-between; align-items: flex-end; gap: 34px;
}
footer .note { font-size: 18px; line-height: 1.45; color: var(--text-muted); max-width: 62ch; margin: 0; }
footer .mark { font-size: 18px; color: var(--text-secondary); font-weight: var(--fw-label);
  text-align: right; white-space: nowrap; line-height: 1.45; }
footer .mark span { display: block; font-weight: var(--fw-body); color: var(--text-muted); }
.hero-num {
  font-family: var(--font-serif);
  font-size: 300px; font-weight: var(--fw-serif); letter-spacing: -0.05em; line-height: .92;
  color: var(--series-1); margin: 10px 0 0;
}
"""

WORDMARK = ("Women’s Career Lifespans<span>in U.S. Entertainment</span>")


def card(name, kicker, head, sub, note, legend_items=None, chart_js="",
         body_extra="", head_class=""):
    leg = ""
    if legend_items:
        leg = '<ul class="legend">' + "".join(
            f'<li><span class="key{" ghost" if c=="ghost" else ""}"'
            f'{"" if c=="ghost" else f" style=background:{c}"}></span>{lab}</li>'
            for lab, c in legend_items) + "</ul>"
    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<style>{TOKENS_CSS}{SOCIAL_CSS}</style></head>
<body class="viz-root"><div class="card">
  <p class="kicker">{kicker}</p>
  <h1 class="{head_class}">{head}</h1>
  <p class="sub">{sub}</p>
  {leg}
  {body_extra or '<div class="plot"><div class="chart-wrap" id="c"></div></div>'}
  <footer>
    <p class="note">{note}</p>
    <p class="mark">{WORDMARK}</p>
  </footer>
</div>
<script>{CHART_JS}{chart_js}</script>
</body></html>"""
    open(os.path.join(OUT, name + ".html"), "w", encoding="utf-8").write(html)
    print("wrote social/" + name + ".html")


DATA_JS = "const D = " + json.dumps({
    "role": role, "hz": hz, "bshare": bshare}) + ";\n"

SRC_IMDB = ("Source: IMDb non-commercial datasets, U.S.-market titles, 2000 onward. "
            "“Women-coded” and “men-coded” are predominant IMDb credit-metadata classes, "
            "not self-identified gender. Public credits measure observed opportunity — not who "
            "was available, auditioned, declined, or retired.")
SRC_SHORT = ("Source: IMDb non-commercial datasets, U.S.-market titles, 2000 onward. "
             "“Women-coded” and “men-coded” are IMDb credit-metadata classes, not "
             "self-identified gender; credits measure observed opportunity, not availability.")
SRC_BB = ("Source: Billboard Hot 100, 1995–2025, matched to MusicBrainz solo artists with "
          "birth-year and gender metadata (49.8% of chart rows classified). Groups and ambiguous "
          "names are excluded rather than assigned a gender. Line stops at 45 where the sample thins.")

# ---------------------------------------------------------------- 1. the spine
card("01-share-film", "Screen roles by age",
     f"Women hold half of U.S. film roles at 28. By 50, a quarter.",
     "Share of principal film opportunity units credited to women-coded performers, "
     "by performer age.",
     SRC_IMDB,
     chart_js=DATA_JS + """
lineChart({
  mount: document.getElementById("c"),
  w: 1048, h: 560, m: {t: 40, r: 40, b: 74, l: 96},
  x: {dom: [18, 80], step: 10, title: "Performer age"},
  y: {dom: [0.15, 0.6], step: 0.1, fmt: (v,d) => (v*100).toFixed(0) + "%"},
  refs: [{y: 0.5, label: "parity"}],
  series: [{label: "Film", color: "var(--series-1)",
            values: D.role.film, endLabel: false}],
  markers: [
    {x: 28, value: "51%", label: "age 28", dy: -30},
    {x: 50, value: "25%", label: "age 50", dy: 46}
  ]
});""")

# --------------------------------------------------------------- 2. the hazard
card("02-interruption", "Career interruption",
     f"At 30, a woman’s screen career is {100*(hr30-1):.0f}% more likely to stall for five years",
     "Adjusted probability that a credited year is the last before a five-year career "
     "interruption, among established performers.",
     "28% <em>higher</em> than the men-coded hazard — not a 28% chance. At 30, 7.9% of "
     "credited years for women-coded performers begin such an interruption, against 6.2% "
     "for men-coded (95% CI: 22–34% higher). A confirmed interruption is not retirement; "
     "a performer can return. " + SRC_SHORT,
     legend_items=[("Women-coded", "var(--series-1)"), ("Men-coded", "var(--series-2)")],
     head_class="tight",
     chart_js=DATA_JS + """
lineChart({
  mount: document.getElementById("c"),
  w: 1048, h: 500, m: {t: 34, r: 40, b: 72, l: 96},
  x: {dom: [20, 55], step: 5, title: "Performer age"},
  y: {dom: [0, 0.09], step: 0.02, fmt: (v,d) => (v*100).toFixed(0) + "%"},
  series: [
    {label: "Women-coded", color: "var(--series-1)", values: D.hz.map(r=>[r[0],r[1]]),
     endLabel: false, labelAt: 34, labelDy: -24},
    {label: "Men-coded", color: "var(--series-2)", values: D.hz.map(r=>[r[0],r[2]]),
     endLabel: false, labelAt: 24, labelDy: 42}
  ]
});""")

# ------------------------------------------------------------ 4. the billboard
card("04-billboard", "A parallel case: the Hot 100",
     "On the charts, women’s share falls a decade earlier than on screen",
     "Share of classified solo Billboard Hot 100 artist-years credited to women-coded "
     "artists, by artist age.",
     SRC_BB,
     chart_js=DATA_JS + """
lineChart({
  mount: document.getElementById("c"),
  w: 1048, h: 540, m: {t: 40, r: 40, b: 74, l: 96},
  x: {dom: [16, 45], step: 5, title: "Artist age"},
  y: {dom: [0.1, 0.7], step: 0.2, fmt: (v,d) => (v*100).toFixed(0) + "%"},
  refs: [{y: 0.5, label: "parity"}],
  series: [{label: "Women-coded share", color: "var(--series-1)",
            values: D.bshare.filter(r => r[0] >= 16 && r[0] <= 45), endLabel: false}],
  markers: [{x: 21, value: "50%", label: "age 21", dy: -26}]
});""")

# --------------------------------------------------------------- 5. hero number
card("05-hero", "The headline number",
     "The age women stop holding half of U.S. screen roles — and never hold half again",
     "",
     SRC_IMDB,
     head_class="tight",
     body_extra="""<div class="plot" style="flex-direction:column;align-items:flex-start;justify-content:center">
  <p class="hero-num">29</p>
  <div class="chart-wrap" id="c" style="margin-top:18px"></div>
</div>""",
     chart_js=DATA_JS + """
lineChart({
  mount: document.getElementById("c"),
  w: 1048, h: 300, m: {t: 26, r: 40, b: 66, l: 96},
  x: {dom: [18, 80], step: 10, title: "Performer age"},
  y: {dom: [0.2, 0.6], step: 0.2, fmt: (v,d) => (v*100).toFixed(0) + "%"},
  refs: [{y: 0.5, label: "parity"}],
  series: [{label: "All U.S.-market titles", color: "var(--series-1)",
            values: D.role.overall, endLabel: false}],
  markers: [{x: 29, value: "29", label: "", dy: -22, r: 9}]
});""")
