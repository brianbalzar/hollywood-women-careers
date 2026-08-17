#!/usr/bin/env python3
"""Generate the Claude Design bundle for hollywood-women-careers.

Every emitted HTML file is self-contained and carries a first-line @dsCard
marker so the Design System pane can index it.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import page

import paths as P

ROOT = P.ROOT
OUT = P.DESIGN                 # previews live at <repo>/design-system/
D = P.load_tables()            # straight from <repo>/outputs/tables/*.csv

f = float
i = int

# ------------------------------------------------------------------ data prep
role = {}
for r in D["women_role_share"]:
    role.setdefault(r["scope"], []).append([i(r["age"]), f(r["women_coded_share"]),
                                            i(r["women_coded_roles"]), i(r["total_roles"])])
for k in role:
    role[k].sort()

cps = {r["scope"]: r for r in D["role_share_change_points"]}

hz = sorted([[i(r["age"]), f(r["women_exit_hazard"]), f(r["men_exit_hazard"]),
              f(r["exit_hazard_ratio"]), f(r["ratio_conf_low"]), f(r["ratio_conf_high"])]
             for r in D["adjusted_exit_hazard_ratio"]])

bshare = sorted([[i(r["age"]), f(r["women_share"]), i(r["total_artist_years"])]
                 for r in D["billboard_women_share_by_age"]])

bret = {}
bands = []
for r in D["billboard_return_by_age"]:
    if r["age_band"] not in bands:
        bands.append((i(r["age_band_start"]), r["age_band"]))
    bret.setdefault(r["credit_group"], []).append(
        [i(r["age_band_start"]), r["age_band"], f(r["return_rate"]),
         f(r["conf_low"]), f(r["conf_high"]), i(r["artist_years"])])
bands = [b[1] for b in sorted(set(bands))]
for k in bret:
    bret[k].sort()

bage = D["billboard_age_summary"]
periods = []
for r in bage:
    if r["period"] not in periods:
        periods.append(r["period"])

# headline numbers -------------------------------------------------
def share_at(scope, age):
    return next(r[1] for r in role[scope] if r[0] == age)

def parity_age(scope):
    """First age at which women-coded share drops below 50% and stays below."""
    rows = role[scope]
    for n, r in enumerate(rows):
        if r[1] < 0.5 and all(x[1] < 0.5 for x in rows[n:n + 8]):
            return r[0]
    return None

hz30 = next(r for r in hz if r[0] == 30)
bret_w = {r[0]: r for r in bret["women-coded"]}
bret_m = {r[0]: r for r in bret["men-coded"]}

HEAD = {
    "film30": share_at("film", 30), "film50": share_at("film", 50),
    "tv50": share_at("television", 50),
    "parity_film": parity_age("film"), "parity_overall": parity_age("overall"),
    "cp_film": i(cps["film"]["estimated_change_age"]),
    "cp_lo": i(cps["film"]["bootstrap_conf_low"]), "cp_hi": i(cps["film"]["bootstrap_conf_high"]),
    "hr30": hz30[3], "hr30lo": hz30[4], "hr30hi": hz30[5],
    "bill_w_40": bret_w[40][2], "bill_m_40": bret_m[40][2],
}

DATA = {
    "role": role, "cps": cps, "hz": hz,
    "bshare": bshare, "bret": bret, "bands": bands,
    "bage": bage, "periods": periods, "head": HEAD,
}

SOURCE_IMDB = ('Source: IMDb non-commercial datasets, U.S.-market titles, release years 2000–'
               'latest complete year. Analysis: <em>Women’s Career Lifespans in U.S. Entertainment</em>.')
SOURCE_BB = ('Source: Billboard Hot 100, 1995–2025, matched to MusicBrainz solo artists with '
             'birth-year and gender metadata (49.8% of chart rows classified).')

BOUNDARY = ('“Women-coded” and “men-coded” are predominant IMDb credit-metadata '
            'classes, not self-identified gender. Public credits measure observed opportunity, '
            'not who was available, auditioned, declined, or retired.')


def legend(items):
    out = ['<ul class="legend">']
    for label, color, kind in items:
        cls = "key" + (" dot" if kind == "dot" else "")
        style = f"background:{color}" if kind != "dash" else ""
        if kind == "dash":
            out.append(f'<li><span class="key dash" style="border-top-color:{color}"></span>{label}</li>')
        else:
            out.append(f'<li><span class="{cls}" style="{style}"></span>{label}</li>')
    out.append("</ul>")
    return "\n".join(out)


def figure(kicker, title, sub, chart_id, note, source, legend_html="", table_html="", height=None):
    h = f' style="min-height:{height}px"' if height else ""
    return f"""<figure class="figure">
  <p class="fig-kicker">{kicker}</p>
  <h3 class="fig-title">{title}</h3>
  <p class="fig-sub">{sub}</p>
  {legend_html}
  <div class="chart-wrap" id="{chart_id}"{h}></div>
  <figcaption>
    <p class="fig-note">{note}</p>
    <p class="fig-source">{source}</p>
  </figcaption>
  {table_html}
</figure>"""


def tableview(summary, caption, headers, rows):
    th = "".join(f"<th scope='col'>{h}</th>" for h in headers)
    tr = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f"""<details class="tableview">
  <summary>{summary}</summary>
  <table class="data"><caption>{caption}</caption>
    <thead><tr>{th}</tr></thead><tbody>{tr}</tbody>
  </table>
</details>"""


DATA_JS = "const D = " + json.dumps(DATA) + ";\n"

os.makedirs(OUT, exist_ok=True)
for sub in ("foundations", "charts", "components"):
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)


def write(path, html):
    p = os.path.join(OUT, path)
    open(p, "w", encoding="utf-8").write(html)
    print("wrote", path, f"({len(html)//1024} KB)")


# ============================================================ 1. COLOR TOKENS
swatch_rows = [
    ("Series 1 — women-coded", "--series-1", "#2a78d6", "#3987e5",
     "Categorical slot 1. The subject of the study; also the single-series accent."),
    ("Series 2 — men-coded", "--series-2", "#eb6834", "#d95926",
     "Categorical slot 2. The comparison class."),
    ("Ghost — context line", "--series-ghost", "#c3c2b7", "#4a4a46",
     "Non-identity reference trace in small multiples. Never a series."),
    ("Sequential 400", "--seq-400", "#3987e5", "#3987e5",
     "One hue, light→dark, for magnitude (label-rate heat). Never a rainbow."),
    ("Status — caution", "--status-serious", "#ec835a", "#ec835a",
     "Reserved for interpretation cautions. Ships with an icon + label, never colour alone."),
]
rows_html = "".join(
    f"""<tr>
      <td style="text-align:left">
        <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:{lt};vertical-align:-2px;margin-right:8px;border:1px solid var(--hairline)"></span>
        {name}</td>
      <td style="text-align:left"><code>{tok}</code></td>
      <td><code>{lt}</code></td><td><code>{dk}</code></td>
      <td style="text-align:left;font-variant-numeric:normal">{desc}</td></tr>"""
    for name, tok, lt, dk, desc in swatch_rows)

color_body = f"""
<div class="ds-head">
  <h1>Colour</h1>
  <p>Two categorical hues carry the only identity dimension in this study — credit class.
  Everything else is chrome, ghost, or a single-hue ramp. Colour is never spent on scope
  (film / television), which is faceted instead.</p>
</div>

<section class="ds-sec">
  <h2>Tokens</h2>
  <table class="data">
    <thead><tr><th>Role</th><th>Token</th><th>Light</th><th>Dark</th><th>Job</th></tr></thead>
    <tbody>{rows_html}</tbody>
  </table>
  <p class="spec">Both modes are selected, not flipped: the dark column is the same two hues
  re-stepped for the dark surface (<code>#1a1a19</code>).</p>
</section>

<section class="ds-sec">
  <h2>Validation</h2>
  <div class="callout">
    <h4>All six checks pass — computed, not eyeballed</h4>
    <p><strong>Light</strong> (surface <code>#fcfcfb</code>): lightness band PASS · chroma floor PASS ·
    CVD separation ΔE&nbsp;24.7 (protan) / 32.7 (tritan) PASS · normal-vision ΔE&nbsp;33.6 PASS ·
    contrast ≥3:1 PASS.</p>
    <p><strong>Dark</strong> (surface <code>#1a1a19</code>): CVD ΔE&nbsp;26.8 · normal-vision ΔE&nbsp;31.8 ·
    all bands and contrast PASS.</p>
    <p>Blue↔orange was chosen over the conventional blue↔pink pairing: it clears the
    colour-vision gates by a wide margin and avoids encoding gender with the stereotyped
    hue it is being used to measure.</p>
  </div>
</section>

<section class="ds-sec">
  <h2>Rules</h2>
  <div class="callout boundary">
    <h4>Non-negotiable</h4>
    <p>Slot order is fixed and never cycled. Blue is always women-coded, orange always
    men-coded — across every figure in the report, and regardless of which series is
    larger at a given age.</p>
    <p>Scope (film / television / overall) never gets a hue. It is faceted into small
    multiples with a shared axis and a ghost trace, so a reader never has to hold two
    competing colour meanings at once.</p>
    <p>Status colours are reserved for interpretation cautions and never reused as a series.</p>
  </div>
</section>
"""
write("foundations/color.html", page(
    "Colour — Career Lifespans design system",
    {"group": "Foundations", "name": "Colour", "subtitle": "2 categorical hues, validated light + dark",
     "width": 1000, "height": 900},
    color_body))

# ============================================================ 2. TYPE
type_body = """
<div class="ds-head">
  <h1>Type &amp; figures</h1>
  <p>One system sans throughout, including the hero number. Headline weight does the
  hierarchy; size does the rest. No display or serif face anywhere.</p>
</div>

<section class="ds-sec">
  <h2>Scale</h2>
  <div class="figure">
    <div class="hero-figure">42</div>
    <p class="spec">Hero figure — 56px / 660 / -0.03em / proportional figures. Exactly one per view.</p>
    <hr style="border:none;border-top:1px solid var(--hairline);margin:24px 0">
    <div style="font-size:30px;font-weight:var(--fw-label);letter-spacing:-0.02em;line-height:1.2">Report title</div>
    <p class="spec">H1 — 30px / 660 / -0.02em</p>
    <div style="font-size:21px;font-weight:var(--fw-label);letter-spacing:-0.012em;line-height:1.28;margin-top:20px">Figure title that carries the finding on its own</div>
    <p class="spec">Figure title / H2 — 21px / 640 / max 46ch</p>
    <div style="font-size:16px;line-height:1.62;max-width:68ch;margin-top:20px;color:var(--text-primary)">
      Body copy sits on a 68ch measure at 16px/1.62. Long-form methodological prose is the
      bulk of this report, so the measure and leading are tuned for sustained reading rather
      than for density.</div>
    <p class="spec">Body — 16px / 1.62 / 68ch measure</p>
    <div style="font-size:14px;color:var(--text-secondary);margin-top:20px;max-width:60ch">
      Figure subtitle: states the denominator, the scope, and the unit before the reader
      reaches the chart.</div>
    <p class="spec">Subtitle — 14px / secondary ink / max 60ch</p>
    <div style="font-size:12.5px;color:var(--text-muted);margin-top:20px;max-width:74ch">
      Note and source: 12.5px muted ink. Every figure carries both.</div>
    <p class="spec">Note / source / axis — 12.5px / muted ink</p>
  </div>
</section>

<section class="ds-sec">
  <h2>Numerals</h2>
  <div class="figure">
    <div style="display:flex;gap:48px;flex-wrap:wrap">
      <div>
        <div style="font-size:34px;font-weight:var(--fw-label);letter-spacing:-0.02em">121</div>
        <p class="spec">Proportional — hero and stat-tile values</p>
      </div>
      <div>
        <div style="font-size:34px;font-weight:var(--fw-label);letter-spacing:-0.02em;font-variant-numeric:tabular-nums">121</div>
        <p class="spec">Tabular — <strong>only</strong> in table columns and axis ticks</p>
      </div>
    </div>
  </div>
</section>
"""
write("foundations/type.html", page(
    "Type — Career Lifespans design system",
    {"group": "Foundations", "name": "Type & figures", "subtitle": "System sans, 6-step scale, numeral rules",
     "width": 1000, "height": 1000},
    type_body))

# ============================================================ 3. CHART ANATOMY
anat_body = """
<div class="ds-head">
  <h1>Chart anatomy</h1>
  <p>Fixed mark specs. The data is the only thing allowed to be loud.</p>
</div>
<section class="ds-sec">
  <h2>Marks</h2>
  <table class="data">
    <thead><tr><th>Element</th><th style="text-align:left">Spec</th></tr></thead>
    <tbody>
      <tr><td style="text-align:left">Line</td><td style="text-align:left;font-variant-numeric:normal">2px, round join and cap</td></tr>
      <tr><td style="text-align:left">Uncertainty band</td><td style="text-align:left;font-variant-numeric:normal">Series hue at 13% opacity, no stroke</td></tr>
      <tr><td style="text-align:left">End dot / marker</td><td style="text-align:left;font-variant-numeric:normal">r 4.5–5.5px, filled series hue, <strong>2px surface ring</strong></td></tr>
      <tr><td style="text-align:left">Ghost trace</td><td style="text-align:left;font-variant-numeric:normal">1.5px in <code>--series-ghost</code>, no marker, no label</td></tr>
      <tr><td style="text-align:left">Gridline</td><td style="text-align:left;font-variant-numeric:normal">1px <strong>solid</strong> hairline, one step off surface — never dashed</td></tr>
      <tr><td style="text-align:left">Reference rule</td><td style="text-align:left;font-variant-numeric:normal">1px muted at 55% opacity, labelled at the right edge</td></tr>
      <tr><td style="text-align:left">Quantile box</td><td style="text-align:left;font-variant-numeric:normal">22px cap, 3px radius; median drawn as a 2.5px <em>surface-colour</em> gap</td></tr>
    </tbody>
  </table>
</section>
<section class="ds-sec">
  <h2>Labels</h2>
  <div class="callout boundary">
    <h4>Selective, never exhaustive</h4>
    <p>Label the endpoint, the extreme, or the one series the story is about. Never a
    number on every point — the axis, the legend and the tooltip carry the rest.</p>
    <p>Text always wears text tokens. Identity comes from the coloured mark <em>beside</em>
    the label, never from colouring the label itself.</p>
    <p>A legend is present whenever two or more series are plotted. A single-series chart
    gets no legend box — the title already names what is plotted.</p>
  </div>
</section>
<section class="ds-sec">
  <h2>Every chart ships with</h2>
  <div class="callout">
    <h4>The four attachments</h4>
    <p><strong>Hover layer.</strong> Crosshair plus nearest-x tooltip on lines; per-mark
    tooltip with keyboard focus on dots and boxes.</p>
    <p><strong>Table view.</strong> A disclosure twin containing every plotted value, so no
    number is reachable only through a tooltip.</p>
    <p><strong>Note.</strong> What the measure is and what it is not.</p>
    <p><strong>Source.</strong> Dataset, scope, and vintage.</p>
  </div>
</section>
"""
write("foundations/chart-anatomy.html", page(
    "Chart anatomy — Career Lifespans design system",
    {"group": "Foundations", "name": "Chart anatomy", "subtitle": "Mark specs, labels, the four attachments",
     "width": 1000, "height": 900},
    anat_body))

# ============================================================ 4. OPPORTUNITY SHARE
scope_labels = [("film", "Film"), ("television", "Television"), ("overall", "All U.S.-market titles")]
rows = []
for age in (25, 30, 35, 40, 45, 50, 60):
    rows.append([age] + [f"{share_at(s, age)*100:.1f}%" for s, _ in scope_labels])
tv = tableview("Show the data", "Women-coded share of principal opportunity units, by age and scope.",
               ["Performer age", "Film", "Television", "All titles"], rows)

panels = "".join(
    f'<div class="sm-panel"><div class="chart-wrap" id="sm-{s}"></div></div>' for s, _ in scope_labels)

share_body = f"""
<div class="ds-head">
  <h1>Opportunity share by age</h1>
  <p>The report’s spine chart. Scope is faceted, not coloured — each panel keeps the
  shared axis and a ghost trace of all titles for direct comparison.</p>
</div>

<figure class="figure">
  <p class="fig-kicker">Figure 1</p>
  <h3 class="fig-title">Women hold half of all principal screen roles at 28. By 50 they hold barely a quarter of film roles.</h3>
  <p class="fig-sub">Share of principal opportunity units credited to women-coded performers,
  by performer age. Denominator: opportunities credited to women-coded plus men-coded performers.</p>
  {legend([("Women-coded share, this scope", "var(--series-1)", "line"),
           ("All U.S.-market titles (context)", "var(--series-ghost)", "line")])}
  <div class="sm-grid">{panels}</div>
  <figcaption>
    <p class="fig-note">The dotted rule marks parity at 50%. The vertical mark is the estimated
    change point in the log-odds slope — the age at which the decline <em>slows</em>, not
    where it begins. {BOUNDARY}</p>
    <p class="fig-source">{SOURCE_IMDB}</p>
  </figcaption>
  {tv}
</figure>
"""
share_css = """
.sm-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--sp-3); }
@media (max-width: 800px) { .sm-grid { grid-template-columns: 1fr; } }
.sm-panel { min-width: 0; }
"""
share_js = """
const SCOPES = [["film","Film"],["television","Television"],["overall","All U.S.-market titles"]];
const ghost = D.role["overall"].map(r => [r[0], r[1]]);
SCOPES.forEach(([key,label]) => {
  const vals = D.role[key].map(r => [r[0], r[1]]);
  const cp = +D.cps[key].estimated_change_age;
  lineChart({
    mount: document.getElementById("sm-" + key),
    w: 320, h: 300, m: {t: 34, r: 16, b: 42, l: 44},
    x: {dom: [18, 80], step: 20, title: "Performer age"},
    y: {dom: [0.2, 0.6], step: 0.1, fmt: (v,d) => (v*100).toFixed(d||0) + "%"},
    refs: [{y: 0.5, label: "parity"}],
    ghost: key === "overall" ? [] : [{values: ghost}],
    annots: [{x: cp, label: "↓ " + cp, sub: "slope flattens"}],
    series: [{key, label: label, color: "var(--series-1)",
              values: vals, endLabel: false}],
    tipHead: a => "Age " + a,
    aria: label + ": women-coded share of principal opportunities by performer age."
  });
  const t = document.createElementNS(NS,"text");
  const svg = document.getElementById("sm-"+key).querySelector("svg");
  t.setAttribute("class","panel-title"); t.setAttribute("x", 44); t.setAttribute("y", 14);
  t.textContent = label; svg.insertBefore(t, svg.firstChild);
});
"""
write("charts/opportunity-share.html", page(
    "Opportunity share — Career Lifespans design system",
    {"group": "Charts", "name": "Opportunity share by age",
     "subtitle": "Small multiples, ghost trace, change-point annotation", "width": 1000, "height": 760},
    share_body, extra_css=share_css, extra_js=share_js, data_js=DATA_JS))

# ============================================================ 5. INTERRUPTION HAZARD
hzrows = [[r[0], f"{r[1]*100:.2f}%", f"{r[2]*100:.2f}%", f"{r[3]:.2f}",
           f"{r[4]:.2f}–{r[5]:.2f}"] for r in hz if r[0] % 5 == 0]
hz_tv = tableview("Show the data",
                  "Adjusted probability that a credited year is the last before a five-year interruption.",
                  ["Age", "Women-coded", "Men-coded", "Ratio", "95% CI"], hzrows)

hz_body = f"""
<div class="ds-head">
  <h1>Interruption hazard</h1>
  <p>Two charts, one axis each — never a dual axis. The levels chart carries identity
  (two hues, legend + end labels); the ratio chart is a single series against a 1.0 rule.</p>
</div>

{figure("Figure 2a",
        "The two hazards separate in the mid-30s and stay apart",
        "Adjusted probability that a credited year is the last before a five-year career "
        "interruption, among established performers who entered during 2000–2010.",
        "hz-levels",
        "A confirmed interruption, not permanent retirement — a performer can later return. "
        "Recent final credits are censored until five follow-up years are observable. " + BOUNDARY,
        SOURCE_IMDB,
        legend([("Women-coded", "var(--series-1)", "line"), ("Men-coded", "var(--series-2)", "line")]))}

{figure("Figure 2b",
        f"At 30, a women-coded career is {100*(HEAD['hr30']-1):.0f}% more likely to enter a five-year interruption",
        "Ratio of the two adjusted hazards, with a 95% confidence band. Values above 1.0 mean "
        "women-coded careers face the higher interruption hazard at that age.",
        "hz-ratio",
        "Read the axis as a ratio: 1.28 means 28% <em>higher</em> than the men-coded hazard at that "
        "age, not a 28% chance of interruption. The absolute hazards at 30 are 7.9% and 6.2%. "
        "The band is a cluster-robust 95% confidence interval; where it crosses 1.0 the "
        "difference is not distinguishable from none at that age.",
        SOURCE_IMDB,
        "", hz_tv)}
"""
hz_js = """
lineChart({
  mount: document.getElementById("hz-levels"),
  w: 860, h: 400, m: {t: 18, r: 132, b: 46, l: 60},
  x: {dom: [20, 55], step: 5, title: "Performer age"},
  y: {dom: [0, 0.09], step: 0.02, title: "Annual interruption hazard",
      fmt: (v,d) => (v*100).toFixed(d===undefined?0:Math.max(1,d)) + "%"},
  series: [
    {label: "Women-coded", color: "var(--series-1)", values: D.hz.map(r => [r[0], r[1]]), endLabel: false, labelAt: 30, labelDy: -14},
    {label: "Men-coded",   color: "var(--series-2)", values: D.hz.map(r => [r[0], r[2]]), endLabel: false, labelAt: 26, labelDy: 22}
  ],
  tipHead: a => "Age " + a,
  aria: "Adjusted interruption hazard by performer age for women-coded and men-coded performers."
});
lineChart({
  mount: document.getElementById("hz-ratio"),
  w: 860, h: 340, m: {t: 18, r: 132, b: 46, l: 60},
  x: {dom: [20, 55], step: 5, title: "Performer age"},
  y: {dom: [0.5, 2.1], step: 0.5, title: "Hazard ratio (women ÷ men)",
      fmt: (v,d) => v.toFixed(d===undefined?1:2)},
  refs: [{y: 1.0, label: "equal hazard"}],
  series: [{label: "Hazard ratio", color: "var(--series-1)",
            values: D.hz.map(r => [r[0], r[3]]),
            band: D.hz.map(r => [r[0], r[4], r[5]]), endLabel: false}],
  tipHead: a => "Age " + a,
  aria: "Ratio of women-coded to men-coded interruption hazard by age, with 95 percent confidence band."
});
"""
write("charts/interruption-hazard.html", page(
    "Interruption hazard — Career Lifespans design system",
    {"group": "Charts", "name": "Interruption hazard",
     "subtitle": "Two-series levels + single-series ratio with CI band", "width": 1000, "height": 900},
    hz_body, extra_js=hz_js, data_js=DATA_JS))

# ============================================================ 6. BILLBOARD
MIN_N = 15
bb_rows, bb_dropped = [], []
bw = {r[0]: r for r in bret["women-coded"]}
bm = {r[0]: r for r in bret["men-coded"]}
for start in sorted(bw):
    if start not in bm:
        continue
    if bw[start][5] < MIN_N or bm[start][5] < MIN_N:
        bb_dropped.append(f"{bw[start][1]} (n={bw[start][5]}/{bm[start][5]})")
        continue
    bb_rows.append([bw[start][1], f"{bw[start][2]*100:.1f}%",
                    f"{bw[start][3]*100:.1f}–{bw[start][4]*100:.1f}%",
                    f"{bm[start][2]*100:.1f}%",
                    f"{bm[start][3]*100:.1f}–{bm[start][4]*100:.1f}%"])
bb_caption = ("Probability of another chart-active year within five years, by age band and credit "
              f"class. Bands excluded for thin samples (&lt;{MIN_N} classified artist-years in either "
              f"group, women/men): {', '.join(bb_dropped)}.")
bb_tv = tableview("Show the data", bb_caption,
                  ["Age band", "Women-coded", "95% CI", "Men-coded", "95% CI"], bb_rows)

age_rows = [[r["period"], "Women-coded" if r["credit_group"] == "women-coded" else "Men-coded",
             r["artist_years"], f'{float(r["median_age"]):.0f}',
             f'{float(r["age_q1"]):.0f}–{float(r["age_q3"]):.0f}',
             f'{float(r["share_40_plus"])*100:.1f}%'] for r in bage]
age_tv = tableview("Show the data", "Age distribution of identifiable solo Hot 100 artists.",
                   ["Period", "Credit class", "Artist-years", "Median age", "IQR", "Share 40+"], age_rows)

bb_body = f"""
<div class="ds-head">
  <h1>Billboard extension</h1>
  <p>A parallel case in a different industry, using the same two hues so a reader carries
  one colour vocabulary across both halves of the report.</p>
</div>

{figure("Figure 4",
        "Women’s share of solo chart participation falls through the 20s — a decade earlier than on screen",
        "Share of classified solo artist-years on the Billboard Hot 100 credited to women-coded "
        "artists, by artist age.",
        "bb-share",
        "One identifiable solo artist counts once per calendar year in which they charted. "
        "Groups, unresolved collaborations and ambiguous names are excluded rather than assigned "
        "a gender. The line stops at 45: past that, fewer than 40 classified artist-years per year of "
        "age make annual estimates unstable. Chart presence measures commercial visibility, not "
        "recording employment.",
        SOURCE_BB,
        "")}

{figure("Figure 5",
        "Return rates track each other until 40 — then men’s holds and women’s falls",
        "Probability of at least one further chart-active year within five years, by age band, "
        "with 95% confidence intervals.",
        "bb-return",
        "Age bands, not single years — the classified solo sample is too thin for annual estimates "
        "past 40. Whiskers are 95% confidence intervals; they overlap at every band, so the "
        "divergence after 40 is suggestive rather than established. Bands above 54 are omitted "
        "entirely: with fewer than 15 classified artist-years per group they swing between 0% and "
        "100% and carry no information.",
        SOURCE_BB,
        legend([("Women-coded", "var(--series-1)", "dot"), ("Men-coded", "var(--series-2)", "dot")]),
        bb_tv)}

{figure("Figure 6",
        "The charting age gap has not closed in thirty years",
        "Median and interquartile range of artist age among identifiable solo Hot 100 artists, by decade.",
        "bb-age",
        "Boxes span the interquartile range; the gap across each box is the median. "
        "Chart methodology changed over this period, so cross-decade comparisons are indicative.",
        SOURCE_BB,
        legend([("Women-coded", "var(--series-1)", "dot"), ("Men-coded", "var(--series-2)", "dot")]),
        age_tv)}
"""
bb_js = """
lineChart({
  mount: document.getElementById("bb-share"),
  w: 860, h: 360, m: {t: 18, r: 60, b: 46, l: 60},
  x: {dom: [16, 45], step: 5, title: "Artist age"},
  y: {dom: [0.1, 0.7], step: 0.2, title: "Women-coded share",
      fmt: (v,d) => (v*100).toFixed(0) + "%"},
  refs: [{y: 0.5, label: "parity"}],
  series: [{label: "Women-coded share", color: "var(--series-1)",
            values: D.bshare.filter(r => r[0] >= 16 && r[0] <= 45).map(r => [r[0], r[1]]),
            endLabel: false}],
  tipHead: a => "Age " + a,
  aria: "Women-coded share of classified solo Hot 100 artist-years by age."
});

const MIN_N = 15;
const keep = D.bands.filter(b => ["women-coded","men-coded"]
  .every(g => (D.bret[g].find(r => r[1] === b) || [,,,,,0])[5] >= MIN_N));
const bandList = keep;
const mk = g => ({
  label: g === "women-coded" ? "Women-coded" : "Men-coded",
  color: g === "women-coded" ? "var(--series-1)" : "var(--series-2)",
  points: D.bret[g].map(r => ({i: bandList.indexOf(r[1]), v: r[2], lo: r[3], hi: r[4]}))
              .filter(p => p.i >= 0)
});
dumbbell({
  mount: document.getElementById("bb-return"),
  w: 860, h: 380, m: {t: 26, r: 24, b: 46, l: 60},
  bands: bandList, x: {title: "Artist age band"},
  y: {dom: [0, 0.8], step: 0.2, title: "Five-year return rate",
      fmt: (v,d) => (v*100).toFixed(d===undefined?0:1) + "%"},
  series: [mk("women-coded"), mk("men-coded")]
});

quantileChart({
  mount: document.getElementById("bb-age"),
  w: 860, h: 360, m: {t: 26, r: 24, b: 46, l: 60},
  y: {dom: [20, 45], step: 5, title: "Artist age"},
  groups: D.periods.map(p => ({
    period: p,
    items: D.bage.filter(r => r.period === p)
      .sort((a,b) => a.credit_group < b.credit_group ? -1 : 1)
      .map(r => ({
        label: r.credit_group === "women-coded" ? "Women-coded" : "Men-coded",
        color: r.credit_group === "women-coded" ? "var(--series-1)" : "var(--series-2)",
        q1: +(+r.age_q1).toFixed(1), med: +(+r.median_age).toFixed(1),
        q3: +(+r.age_q3).toFixed(1), n: r.artist_years
      })).reverse()
  })),
  aria: "Median and interquartile range of Hot 100 solo artist age by decade and credit class."
});
"""
write("charts/billboard.html", page(
    "Billboard extension — Career Lifespans design system",
    {"group": "Charts", "name": "Billboard extension",
     "subtitle": "Share line, dumbbell with CI, quantile boxes", "width": 1000, "height": 1200},
    bb_body, extra_js=bb_js, data_js=DATA_JS))

# ============================================================ 8. STAT TILES
tiles_body = f"""
<div class="ds-head">
  <h1>Figures &amp; stat tiles</h1>
  <p>When the form is a number, not a chart. One hero figure per view; tiles beneath it
  carry the supporting scale.</p>
</div>

<section class="ds-sec">
  <h2>Hero figure</h2>
  <div class="figure">
    <p class="fig-kicker">The headline number</p>
    <div class="hero-figure" style="color:var(--series-1)">{HEAD['parity_overall']}</div>
    <p class="fig-sub" style="margin-top:8px;max-width:44ch">The age at which women-coded performers
    stop holding half of U.S.-market principal screen roles — and never hold half again.</p>
    <p class="fig-source">{SOURCE_IMDB}</p>
  </div>
</section>

<section class="ds-sec">
  <h2>Stat tiles</h2>
  <div class="tiles">
    <div class="tile">
      <div class="t-label">Women-coded share of film roles, age 30</div>
      <div class="t-value">{HEAD['film30']*100:.1f}%</div>
      <div class="t-meta">Principal opportunity units</div>
    </div>
    <div class="tile">
      <div class="t-label">Women-coded share of film roles, age 50</div>
      <div class="t-value">{HEAD['film50']*100:.1f}%</div>
      <div class="t-meta" style="color:var(--status-critical);font-weight:var(--fw-label)">
        ↓ {(HEAD['film30']-HEAD['film50'])*100:.1f} pts vs age 30</div>
    </div>
    <div class="tile">
      <div class="t-label">Interruption hazard ratio at 30</div>
      <div class="t-value">{HEAD['hr30']:.2f}×</div>
      <div class="t-meta">95% CI {HEAD['hr30lo']:.2f}–{HEAD['hr30hi']:.2f}</div>
    </div>
    <div class="tile">
      <div class="t-label">Change point in film, log-odds slope</div>
      <div class="t-value">age {HEAD['cp_film']}</div>
      <div class="t-meta">Bootstrap CI {HEAD['cp_lo']}–{HEAD['cp_hi']} · 500 reps</div>
    </div>
  </div>
  <p class="spec">Tile contract: label (sentence case, no trailing colon) · value (640 weight,
  proportional figures) · optional delta, signed and against a named baseline. A delta wears a
  status colour only when direction carries meaning.</p>
</section>
"""
write("components/stat-tiles.html", page(
    "Figures & stat tiles — Career Lifespans design system",
    {"group": "Components", "name": "Figures & stat tiles",
     "subtitle": "Hero number, 4-tile row, delta rules", "width": 1000, "height": 700},
    tiles_body))

# ============================================================ 9. TABLE
tbl_rows = "".join(
    f"<tr><td>{r[0]}</td><td>{r[1]}</td><td>{r[2]}</td><td>{r[3]}</td><td>{r[4]}</td></tr>"
    for r in hzrows)
table_body = f"""
<div class="ds-head">
  <h1>Data tables</h1>
  <p>The report is table-heavy by design — every estimate is inspectable. Tables read as
  quiet, aligned, and hairline-ruled; they are never boxed.</p>
</div>

<section class="ds-sec">
  <h2>Standalone table</h2>
  <div class="figure">
    <p class="fig-kicker">Table 1</p>
    <h3 class="fig-title">Adjusted interruption hazard by age</h3>
    <p class="fig-sub">Probability that a credited year is the last before a five-year
    interruption, among established performers.</p>
    <table class="data">
      <caption>Estimates at five-year intervals. Full annual series in the report appendix.</caption>
      <thead><tr><th scope="col">Age</th><th scope="col">Women-coded</th><th scope="col">Men-coded</th>
      <th scope="col">Ratio</th><th scope="col">95% CI</th></tr></thead>
      <tbody>{tbl_rows}</tbody>
    </table>
    <p class="fig-source">{SOURCE_IMDB}</p>
  </div>
  <p class="spec">Rules: first column left-aligned, all numerics right-aligned and
  <code>tabular-nums</code>. Header rule is one step darker than the row rules. No zebra
  striping — a hover wash does the row-tracking instead. No outer border.</p>
</section>
"""
write("components/data-table.html", page(
    "Data tables — Career Lifespans design system",
    {"group": "Components", "name": "Data tables",
     "subtitle": "Hairline rules, tabular numerals, hover tracking", "width": 1000, "height": 640},
    table_body))

# ============================================================ 10. CALLOUTS
callout_body = f"""
<div class="ds-head">
  <h1>Callouts</h1>
  <p>This study’s credibility rests on saying plainly what it cannot show. Three variants,
  each with a fixed job.</p>
</div>

<section class="ds-sec">
  <h2>Definition — accent</h2>
  <div class="callout">
    <h4>How to read: women-coded opportunity share</h4>
    <p>An opportunity unit is one principal cast credit in a film, or participation in one
    television series during one calendar year. At each age, women-coded opportunity share is
    opportunities credited to women-coded performers divided by opportunities credited to
    women-coded plus men-coded performers.</p>
    <p>It is <em>not</em> the percentage of women who worked, the share of every speaking role,
    screen time, or an individual performer’s probability of being hired.</p>
  </div>
</section>

<section class="ds-sec">
  <h2>Interpretation boundary — neutral</h2>
  <div class="callout boundary">
    <h4>What this measure does not establish</h4>
    <p>{BOUNDARY}</p>
    <p>Results describe an opportunity gap; they do not by themselves identify its cause or
    prove discriminatory intent.</p>
  </div>
</section>

<section class="ds-sec">
  <h2>Caution — status</h2>
  <div class="callout caution">
    <h4><span aria-hidden="true">⚠</span> Coverage limit</h4>
    <p>Only 49.8% of Hot 100 chart rows resolve to a binary-coded solo artist with birth-year
    metadata. Bands, unresolved collaborations and ambiguous names are excluded rather than
    assigned a gender, so the music results describe identifiable solo artists only.</p>
  </div>
  <p class="spec">The caution variant is the only one that carries a status colour, and it
  always ships with the icon <em>and</em> the heading — never colour alone.</p>
</section>
"""
write("components/callouts.html", page(
    "Callouts — Career Lifespans design system",
    {"group": "Components", "name": "Callouts",
     "subtitle": "Definition, boundary, caution", "width": 1000, "height": 760},
    callout_body))

print("\nheadline numbers:", json.dumps(HEAD, indent=2))
