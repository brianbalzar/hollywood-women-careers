import os as _os
import sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import paths as _p

# The token block is NOT defined here. tokens.css is the contract handed back by
# Claude Design; previews, social cards, the R theme and the Quarto SCSS all read
# it, so a token change propagates everywhere from one edit.
with open(_p.tokens_path(), encoding="utf-8") as _f:
    TOKENS_CSS = _f.read()

# tokens.css names a Google Fonts URL in its header comment. A remote @import
# would break the "self-contained, no network" contract these previews are built
# on, so the faces are self-hosted and inlined as base64 woff2 instead. Sources:
# @fontsource/newsreader and @fontsource/ibm-plex-sans (both SIL OFL).
# Regenerate with: python3 design-system/build/embed_fonts.py
_FACES = _os.path.join(_p.FONTS, "faces-embedded.css")
if not _os.path.exists(_FACES):
    raise SystemExit("fonts/faces-embedded.css missing — run: "
                     "python3 design-system/build/embed_fonts.py")
with open(_FACES, encoding="utf-8") as _f:
    FONT_FACES = _f.read()
TOKENS_CSS = FONT_FACES + "\n" + TOKENS_CSS

BASE_CSS = r"""
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  font-family: var(--font-sans);
  font-size: var(--fs-body);
  line-height: var(--lh-body);
  color: var(--text-primary);
  background: var(--page-plane);
  padding: var(--sp-6) var(--sp-5) var(--sp-8);
}
.wrap { max-width: 940px; margin: 0 auto; }

/* ---------- figure frame ---------- */
.figure {
  background: var(--surface-1);
  border: 1px solid var(--hairline);
  border-radius: 10px;
  padding: var(--sp-5) var(--sp-5) var(--sp-4);
  margin: 0 0 var(--sp-6);
}
.figure + .figure { margin-top: var(--sp-6); }
.fig-kicker {
  font-size: var(--fs-micro); font-weight: var(--fw-label); letter-spacing: .07em;
  text-transform: uppercase; color: var(--text-muted);
  margin: 0 0 var(--sp-2);
}
.fig-title {
  font-family: var(--font-serif);
  font-size: var(--fs-h3); font-weight: var(--fw-serif-reg);
  line-height: var(--lh-title); letter-spacing: var(--tr-h3);
  color: var(--text-primary);
  margin: 0 0 var(--sp-2); max-width: 46ch;
}
.fig-sub {
  font-size: var(--fs-small); color: var(--text-secondary);
  margin: 0 0 var(--sp-4); max-width: 60ch;
}
.fig-note, .fig-source {
  font-size: var(--fs-micro); color: var(--text-muted);
  margin: var(--sp-3) 0 0; max-width: 74ch;
}
.fig-source { margin-top: var(--sp-2); }

/* ---------- legend ---------- */
.legend {
  display: flex; flex-wrap: wrap; gap: var(--sp-4);
  margin: 0 0 var(--sp-3); padding: 0; list-style: none;
  font-size: var(--fs-small); color: var(--text-secondary);
}
.legend li { display: flex; align-items: center; gap: var(--sp-2); }
.legend .key {
  width: 18px; height: 3px; border-radius: 2px; flex: none;
}
.legend .key.dot { width: 10px; height: 10px; border-radius: 50%; }
.legend .key.dash { height: 0; border-top: 2px dotted var(--series-ghost); }

/* ---------- svg chart ---------- */
.chart { width: 100%; height: auto; display: block; overflow: visible; }
.chart text { font-family: var(--font-sans); }  /* chart text is never serif */
.ax-label { font-size: 12px; fill: var(--text-muted); font-variant-numeric: tabular-nums; }
.ax-title { font-size: 12.5px; fill: var(--text-secondary); font-weight: var(--fw-medium); }
.grid { stroke: var(--gridline); stroke-width: 1; shape-rendering: crispEdges; }
.axis-rule { stroke: var(--baseline); stroke-width: 1; shape-rendering: crispEdges; }
.ref-rule { stroke: var(--text-muted); stroke-width: var(--chart-rule);
  stroke-dasharray: 1 3; opacity: .7; }
.ref-label { font-size: var(--fs-parity); fill: var(--text-muted);
  text-transform: uppercase; letter-spacing: var(--tr-parity); font-weight: var(--fw-label);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 3.5px; stroke-linejoin: round; }
.series-line { fill: none; stroke-width: var(--chart-stroke); stroke-linejoin: round; stroke-linecap: round; }
.series-band { stroke: none; opacity: .13; }
.ghost-line { fill: none; stroke: var(--series-ghost); stroke-width: var(--chart-ghost);
  stroke-dasharray: 2 3.5; stroke-linejoin: round; }
.end-dot { stroke: var(--surface-1); stroke-width: 2; }
.end-label { font-size: 12.5px; font-weight: var(--fw-label); fill: var(--text-primary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 3.5px; stroke-linejoin: round; }
.end-label.sub { font-weight: var(--fw-medium); fill: var(--text-secondary); }
.mark-value { font-size: 15px; font-weight: var(--fw-label); fill: var(--text-primary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 4px; stroke-linejoin: round; }
.mark-label { font-size: 13px; font-weight: var(--fw-medium); fill: var(--text-secondary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 4px; stroke-linejoin: round; }
.panel-title { font-size: 13px; font-weight: var(--fw-label); fill: var(--text-primary); }
.annot { font-size: 12px; fill: var(--text-secondary);
  paint-order: stroke; stroke: var(--surface-1); stroke-width: 3.5px; stroke-linejoin: round; }
.annot-rule { stroke: var(--text-muted); stroke-width: 1; stroke-dasharray: none; opacity: .5; }

/* ---------- hover layer ---------- */
.hit { fill: transparent; cursor: crosshair; }
.crosshair { stroke: var(--text-muted); stroke-width: 1; opacity: 0; pointer-events: none; }
.crosshair[data-on="1"] { opacity: .5; }
.tip {
  position: absolute; pointer-events: none; z-index: 5;
  background: var(--surface-1);
  border: 1px solid var(--hairline);
  border-radius: 8px;
  box-shadow: 0 6px 20px rgba(0,0,0,.13);
  padding: 8px 10px; font-size: var(--fs-micro);
  color: var(--text-primary); min-width: 132px;
  opacity: 0; transition: opacity .09s ease;
}
.tip[data-on="1"] { opacity: 1; }
.tip .tip-h { font-weight: var(--fw-label); margin-bottom: 4px; }
.tip .tip-r { display: flex; align-items: center; gap: 7px; justify-content: space-between; }
.tip .tip-r span:last-child { font-variant-numeric: tabular-nums; font-weight: var(--fw-label); }
.tip .swatch { width: 9px; height: 9px; border-radius: 50%; flex: none; }
.chart-wrap { position: relative; }

/* ---------- table view ---------- */
details.tableview { margin-top: var(--sp-3); }
details.tableview > summary {
  cursor: pointer; font-size: var(--fs-micro); color: var(--text-secondary);
  font-weight: var(--fw-medium); list-style: none; display: inline-flex; gap: 6px;
  padding: 4px 0;
}
details.tableview > summary::-webkit-details-marker { display: none; }
details.tableview > summary::before { content: "▸"; color: var(--text-muted); }
details.tableview[open] > summary::before { content: "▾"; }
table.data {
  width: 100%; border-collapse: collapse; margin-top: var(--sp-3);
  font-size: var(--fs-micro); font-variant-numeric: tabular-nums;
}
table.data caption {
  text-align: left; font-size: var(--fs-micro); color: var(--text-muted);
  padding-bottom: var(--sp-2); font-variant-numeric: normal;
}
table.data th, table.data td {
  padding: 7px 10px; text-align: right; border-bottom: 1px solid var(--gridline);
}
table.data th:first-child, table.data td:first-child { text-align: left; }
table.data thead th {
  color: var(--text-secondary); font-weight: var(--fw-label); font-variant-numeric: normal;
  border-bottom: 1px solid var(--baseline); white-space: nowrap;
}
table.data tbody tr:last-child td { border-bottom: none; }
table.data tbody tr:hover { background: color-mix(in srgb, var(--text-primary) 3.5%, transparent); }
table.data .num-neg { color: var(--text-primary); }

/* ---------- stat tiles ---------- */
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: var(--sp-3); }
.tile {
  background: var(--surface-1); border: 1px solid var(--hairline);
  border-radius: 10px; padding: var(--sp-4);
}
.tile .t-label { font-size: var(--fs-micro); color: var(--text-secondary); margin-bottom: var(--sp-2); }
.tile .t-value { font-family: var(--font-serif); font-size: var(--fs-tile);
  font-weight: var(--fw-serif-reg); letter-spacing: var(--tr-title); line-height: 1.05; }
.tile .t-meta { font-size: var(--fs-micro); color: var(--text-muted); margin-top: var(--sp-2); }
.hero-figure { font-family: var(--font-serif); font-size: var(--fs-hero);
  font-weight: var(--fw-serif); letter-spacing: var(--tr-hero);
  line-height: var(--lh-hero); }

/* ---------- callouts ---------- */
.callout {
  border-left: 3px solid var(--series-1);
  background: color-mix(in srgb, var(--series-1) 6%, var(--surface-1));
  border-radius: 0 8px 8px 0;
  padding: var(--sp-4) var(--sp-5);
  margin: var(--sp-5) 0;
  font-size: var(--fs-small);
}
.callout.boundary { border-left-color: var(--text-muted);
  background: color-mix(in srgb, var(--text-muted) 8%, var(--surface-1)); }
.callout.caution { border-left-color: var(--status-serious);
  background: color-mix(in srgb, var(--status-serious) 8%, var(--surface-1)); }
.callout h4 {
  margin: 0 0 var(--sp-2); font-size: var(--fs-micro); font-weight: var(--fw-label);
  letter-spacing: .07em; text-transform: uppercase; color: var(--text-secondary);
  display: flex; align-items: center; gap: 7px;
}
.callout p { margin: 0 0 var(--sp-2); color: var(--text-secondary); }
.callout p:last-child { margin-bottom: 0; }

/* ---------- design-system page chrome ---------- */
.ds-head { max-width: var(--measure); margin: 0 auto var(--sp-6); }
.ds-head h1 { font-family: var(--font-serif); font-size: var(--fs-h1);
  font-weight: var(--fw-serif-reg); letter-spacing: var(--tr-title);
  line-height: var(--lh-title); margin: 0 0 var(--sp-2); }
.ds-head p { color: var(--text-secondary); font-size: var(--fs-small); margin: 0; }
.ds-sec { margin: 0 0 var(--sp-7); }
.ds-sec > h2 {
  font-size: var(--fs-micro); font-weight: var(--fw-label); letter-spacing: .08em;
  text-transform: uppercase; color: var(--text-muted);
  margin: 0 0 var(--sp-3); padding-bottom: var(--sp-2);
  border-bottom: 1px solid var(--hairline);
}
.spec {
  font-size: var(--fs-micro); color: var(--text-muted);
  margin: var(--sp-2) 0 0; font-variant-numeric: tabular-nums;
}
strong, b, th { font-weight: var(--fw-label); }  /* 700 has no static face */
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .92em; }

@media (max-width: 640px) {
  body { padding: var(--sp-5) var(--sp-4) var(--sp-7); }
  .fig-title { font-size: 18px; }
}
@media print {
  body { background: #fff; }
  .figure { break-inside: avoid; border-color: #ccc; }
  details.tableview { display: none; }
}
@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; }
}
"""

# ---------------------------------------------------------------- chart js
CHART_JS = r"""
/* Minimal SVG chart helpers. No dependencies. */
const NS = "http://www.w3.org/2000/svg";
const el = (n, a = {}) => { const e = document.createElementNS(NS, n);
  for (const k in a) if (a[k] !== null && a[k] !== undefined) e.setAttribute(k, a[k]); return e; };
const fmtPct = (v, d = 0) => (v * 100).toFixed(d) + "%";
const fmtNum = (v, d = 2) => Number(v).toFixed(d);

function scaleLinear(d0, d1, r0, r1) {
  const f = v => r0 + (v - d0) / (d1 - d0) * (r1 - r0);
  f.invert = p => d0 + (p - r0) / (r1 - r0) * (d1 - d0);
  return f;
}

/* Ticks rounded to clean numbers. */
function ticks(d0, d1, step) {
  const out = []; const s = Math.ceil(d0 / step) * step;
  for (let v = s; v <= d1 + 1e-9; v += step) out.push(+v.toFixed(10));
  return out;
}

function linePath(pts) {
  return pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(2) + " " + p[1].toFixed(2)).join(" ");
}
function areaPath(pts, lo, hi) {
  const up = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(2) + " " + hi[i].toFixed(2));
  const dn = pts.map((p, i) => "L" + p[0].toFixed(2) + " " + lo[i].toFixed(2)).reverse();
  return up.join(" ") + " " + dn.join(" ") + " Z";
}

/* Tooltip attached to a .chart-wrap. */
function makeTip(wrap) {
  const t = document.createElement("div");
  t.className = "tip"; t.setAttribute("role", "status");
  wrap.appendChild(t); return t;
}
function showTip(tip, wrap, x, y, html) {
  tip.innerHTML = html; tip.dataset.on = "1";
  const w = wrap.getBoundingClientRect(), tb = tip.getBoundingClientRect();
  let left = x + 14; if (left + tb.width > w.width) left = x - tb.width - 14;
  let top = y - tb.height / 2; top = Math.max(0, Math.min(top, w.height - tb.height));
  tip.style.left = left + "px"; tip.style.top = top + "px";
}
const hideTip = tip => { tip.dataset.on = "0"; };

/*
 * lineChart — one or more series over a shared numeric x.
 * cfg: {mount, w, h, m, x:{dom,step,title}, y:{dom,step,title,fmt},
 *       series:[{key,label,color,values:[[x,y]],band?:[[x,lo,hi]],endLabel?}],
 *       ghost:[{values,label}], refs:[{y,label}] , annots:[{x,label,sub}]}
 */
function lineChart(cfg) {
  const wrap = cfg.mount, W = cfg.w, H = cfg.h, m = cfg.m;
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`,
    role: "img", "aria-label": cfg.aria || "" });
  const x = scaleLinear(cfg.x.dom[0], cfg.x.dom[1], m.l, m.l + iw);
  const y = scaleLinear(cfg.y.dom[0], cfg.y.dom[1], m.t + ih, m.t);
  const yf = cfg.y.fmt || (v => fmtPct(v));

  // grid + y labels
  ticks(cfg.y.dom[0], cfg.y.dom[1], cfg.y.step).forEach(v => {
    svg.appendChild(el("line", { class: "grid", x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
    const t = el("text", { class: "ax-label", x: m.l - 9, y: y(v) + 4, "text-anchor": "end" });
    t.textContent = yf(v); svg.appendChild(t);
  });
  // x axis rule + labels
  svg.appendChild(el("line", { class: "axis-rule", x1: m.l, x2: m.l + iw, y1: m.t + ih, y2: m.t + ih }));
  ticks(cfg.x.dom[0], cfg.x.dom[1], cfg.x.step).forEach(v => {
    const t = el("text", { class: "ax-label", x: x(v), y: m.t + ih + 19, "text-anchor": "middle" });
    t.textContent = cfg.x.fmt ? cfg.x.fmt(v) : v; svg.appendChild(t);
  });
  if (cfg.x.title) {
    const t = el("text", { class: "ax-title", x: m.l + iw / 2, y: H - 12, "text-anchor": "middle" });
    t.textContent = cfg.x.title; svg.appendChild(t);
  }
  if (cfg.y.title) {
    const t = el("text", { class: "ax-title", x: -(m.t + ih / 2), y: 14,
      transform: "rotate(-90)", "text-anchor": "middle" });
    t.textContent = cfg.y.title; svg.appendChild(t);
  }
  // reference rules
  (cfg.refs || []).forEach(r => {
    svg.appendChild(el("line", { class: "ref-rule", x1: m.l, x2: m.l + iw, y1: y(r.y), y2: y(r.y) }));
    if (r.label) {
      const t = el("text", { class: "ref-label", x: m.l + iw, y: y(r.y) - 7, "text-anchor": "end" });
      t.textContent = r.label; svg.appendChild(t);
    }
  });
  // ghost context lines (non-identity)
  (cfg.ghost || []).forEach(g => {
    svg.appendChild(el("path", { class: "ghost-line", d: linePath(g.values.map(p => [x(p[0]), y(p[1])])) }));
  });
  // annotations (vertical marks)
  (cfg.annots || []).forEach(a => {
    svg.appendChild(el("line", { class: "annot-rule", x1: x(a.x), x2: x(a.x), y1: m.t + 4, y2: m.t + ih }));
    const t = el("text", { class: "annot", x: x(a.x) + 7, y: m.t + 15 });
    t.textContent = a.label; svg.appendChild(t);
    if (a.sub) { const s = el("text", { class: "annot", x: x(a.x) + 7, y: m.t + 31 });
      s.setAttribute("opacity", ".8"); s.textContent = a.sub; svg.appendChild(s); }
  });
  // bands then lines
  cfg.series.forEach(s => {
    if (s.band) {
      const px = s.band.map(p => x(p[0])), lo = s.band.map(p => y(p[1])), hi = s.band.map(p => y(p[2]));
      svg.appendChild(el("path", { class: "series-band", fill: s.color,
        d: areaPath(px.map((v, i) => [v, hi[i]]), lo, hi) }));
    }
  });
  const ends = [];
  cfg.series.forEach(s => {
    svg.appendChild(el("path", { class: "series-line", stroke: s.color,
      d: linePath(s.values.map(p => [x(p[0]), y(p[1])])) }));
    if (s.endLabel !== false) {
      const last = s.values[s.values.length - 1];
      svg.appendChild(el("circle", { class: "end-dot", cx: x(last[0]), cy: y(last[1]), r: 4.5, fill: s.color }));
      ends.push({ text: s.endLabel || s.label, ex: x(last[0]), ey: y(last[1]), ly: y(last[1]) });
    } else if (s.labelAt !== undefined) {
      const pt = s.values.find(p => p[0] === s.labelAt) || s.values[0];
      const t = el("text", { class: "end-label", x: x(pt[0]), y: y(pt[1]) + (s.labelDy || -12),
        "text-anchor": "middle" });
      t.textContent = s.label; svg.appendChild(t);
    }
  });
  /* Converging end-labels get leader lines, never a silent stack:
     resolve to a minimum vertical spacing, then connect each label to its own line-end. */
  if (ends.length > 1) {
    const MINGAP = 17;
    ends.sort((a, b) => a.ly - b.ly);
    for (let k = 1; k < ends.length; k++) {
      if (ends[k].ly - ends[k - 1].ly < MINGAP) ends[k].ly = ends[k - 1].ly + MINGAP;
    }
    const overflow = ends[ends.length - 1].ly - (m.t + ih);
    if (overflow > 0) ends.forEach(e => e.ly -= overflow);
    const under = m.t + 8 - ends[0].ly;
    if (under > 0) ends.forEach(e => e.ly += under);
  }
  ends.forEach(e => {
    if (Math.abs(e.ly - e.ey) > 1.5) {
      svg.appendChild(el("path", { fill: "none", stroke: "var(--baseline)", "stroke-width": 1,
        d: `M${(e.ex + 6).toFixed(1)} ${e.ey.toFixed(1)} L${(e.ex + 13).toFixed(1)} ${e.ly.toFixed(1)} L${(e.ex + 19).toFixed(1)} ${e.ly.toFixed(1)}` }));
      const t = el("text", { class: "end-label", x: e.ex + 23, y: e.ly + 4 });
      t.textContent = e.text; svg.appendChild(t);
    } else {
      const t = el("text", { class: "end-label", x: e.ex + 9, y: e.ly + 4 });
      t.textContent = e.text; svg.appendChild(t);
    }
  });

  // point markers — a dot plus a value callout at named x positions
  (cfg.markers || []).forEach(mk => {
    const s = cfg.series[mk.series || 0];
    const pt = s.values.find(p => p[0] === mk.x);
    if (!pt) return;
    const px = x(pt[0]), py = y(pt[1]);
    svg.appendChild(el("circle", { class: "end-dot", cx: px, cy: py, r: mk.r || 7, fill: s.color }));
    const dy = mk.dy === undefined ? -20 : mk.dy;
    const anch = mk.anchor || "middle";
    const t = el("text", { class: "mark-value", x: px + (mk.dx || 0), y: py + dy, "text-anchor": anch });
    t.textContent = mk.value; svg.appendChild(t);
    if (mk.label) {
      const l = el("text", { class: "mark-label", x: px + (mk.dx || 0), y: py + dy + (dy < 0 ? -34 : 34),
        "text-anchor": anch });
      l.textContent = mk.label; svg.appendChild(l);
    }
  });

  // hover: crosshair + nearest-x tooltip
  const cross = el("line", { class: "crosshair", y1: m.t, y2: m.t + ih });
  svg.appendChild(cross);
  const dots = cfg.series.map(s => {
    const c = el("circle", { class: "end-dot", r: 5, fill: s.color, opacity: 0 });
    svg.appendChild(c); return c;
  });
  const hit = el("rect", { class: "hit", x: m.l, y: m.t, width: iw, height: ih });
  svg.appendChild(hit);
  const tip = makeTip(wrap);
  const onMove = ev => {
    const r = svg.getBoundingClientRect(), sx = (ev.clientX - r.left) * (W / r.width);
    const xv = Math.round(x.invert(sx));
    const rows = []; let anyY = null;
    cfg.series.forEach((s, i) => {
      const pt = s.values.find(p => p[0] === xv);
      if (!pt) { dots[i].setAttribute("opacity", 0); return; }
      dots[i].setAttribute("cx", x(pt[0])); dots[i].setAttribute("cy", y(pt[1]));
      dots[i].setAttribute("opacity", 1); anyY = anyY === null ? y(pt[1]) : anyY;
      rows.push(`<div class="tip-r"><span><span class="swatch" style="display:inline-block;background:${s.color}"></span> ${s.label}</span><span>${yf(pt[1], 1)}</span></div>`);
    });
    if (!rows.length) { hideTip(tip); cross.removeAttribute("data-on"); return; }
    cross.setAttribute("x1", x(xv)); cross.setAttribute("x2", x(xv)); cross.setAttribute("data-on", "1");
    const wr = wrap.getBoundingClientRect();
    showTip(tip, wrap, ev.clientX - wr.left, ev.clientY - wr.top,
      `<div class="tip-h">${cfg.tipHead ? cfg.tipHead(xv) : xv}</div>${rows.join("")}`);
  };
  hit.addEventListener("pointermove", onMove);
  hit.addEventListener("pointerleave", () => {
    hideTip(tip); cross.removeAttribute("data-on"); dots.forEach(d => d.setAttribute("opacity", 0));
  });
  wrap.appendChild(svg);
  return svg;
}

/*
 * dumbbell — paired point estimates with CI whiskers across ordered bands.
 * cfg: {mount,w,h,m,bands:[label], y:{dom,step,fmt,title},
 *       series:[{label,color,points:[{i,v,lo,hi}]}]}
 */
function dumbbell(cfg) {
  const wrap = cfg.mount, W = cfg.w, H = cfg.h, m = cfg.m;
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img",
    "aria-label": cfg.aria || "" });
  const n = cfg.bands.length, bw = iw / n;
  const cx = i => m.l + bw * (i + 0.5);
  const y = scaleLinear(cfg.y.dom[0], cfg.y.dom[1], m.t + ih, m.t);
  const yf = cfg.y.fmt || (v => fmtPct(v));
  ticks(cfg.y.dom[0], cfg.y.dom[1], cfg.y.step).forEach(v => {
    svg.appendChild(el("line", { class: "grid", x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
    const t = el("text", { class: "ax-label", x: m.l - 9, y: y(v) + 4, "text-anchor": "end" });
    t.textContent = yf(v); svg.appendChild(t);
  });
  svg.appendChild(el("line", { class: "axis-rule", x1: m.l, x2: m.l + iw, y1: m.t + ih, y2: m.t + ih }));
  cfg.bands.forEach((b, i) => {
    const t = el("text", { class: "ax-label", x: cx(i), y: m.t + ih + 19, "text-anchor": "middle" });
    t.textContent = b; svg.appendChild(t);
  });
  if (cfg.y.title) {
    const t = el("text", { class: "ax-title", x: -(m.t + ih / 2), y: 14,
      transform: "rotate(-90)", "text-anchor": "middle" });
    t.textContent = cfg.y.title; svg.appendChild(t);
  }
  if (cfg.x && cfg.x.title) {
    const t = el("text", { class: "ax-title", x: m.l + iw / 2, y: H - 12, "text-anchor": "middle" });
    t.textContent = cfg.x.title; svg.appendChild(t);
  }
  // connector between the two series at each band
  if (cfg.series.length === 2) {
    cfg.bands.forEach((_, i) => {
      const a = cfg.series[0].points.find(p => p.i === i), b = cfg.series[1].points.find(p => p.i === i);
      if (!a || !b) return;
      svg.appendChild(el("line", { x1: cx(i), x2: cx(i), y1: y(a.v), y2: y(b.v),
        stroke: "var(--baseline)", "stroke-width": 1.5 }));
    });
  }
  const tip = makeTip(wrap);
  cfg.series.forEach((s, si) => {
    const off = (si - (cfg.series.length - 1) / 2) * 13;
    s.points.forEach(p => {
      const px = cx(p.i) + off;
      if (p.lo !== undefined) svg.appendChild(el("line", { x1: px, x2: px, y1: y(p.lo), y2: y(p.hi),
        stroke: s.color, "stroke-width": 2, "stroke-linecap": "round", opacity: .42 }));
      const c = el("circle", { class: "end-dot", cx: px, cy: y(p.v), r: 5.5, fill: s.color,
        tabindex: "0", role: "img",
        "aria-label": `${s.label}, ${cfg.bands[p.i]}: ${yf(p.v, 1)}` });
      const html = `<div class="tip-h">${cfg.bands[p.i]}</div>` +
        `<div class="tip-r"><span><span class="swatch" style="display:inline-block;background:${s.color}"></span> ${s.label}</span><span>${yf(p.v, 1)}</span></div>` +
        (p.lo !== undefined ? `<div class="tip-r"><span>95% CI</span><span>${yf(p.lo, 1)}–${yf(p.hi, 1)}</span></div>` : "");
      const show = () => { const r = svg.getBoundingClientRect(), wr = wrap.getBoundingClientRect();
        showTip(tip, wrap, (px / W) * r.width + (r.left - wr.left), (y(p.v) / H) * r.height + (r.top - wr.top), html); };
      c.addEventListener("pointerenter", show); c.addEventListener("focus", show);
      c.addEventListener("pointerleave", () => hideTip(tip)); c.addEventListener("blur", () => hideTip(tip));
      svg.appendChild(c);
      if (p.label) { const t = el("text", { class: "end-label sub", x: px, y: y(p.hi !== undefined ? p.hi : p.v) - 11,
        "text-anchor": "middle" }); t.textContent = p.label; svg.appendChild(t); }
    });
  });
  wrap.appendChild(svg);
  return svg;
}

/*
 * quantileBars — median + IQR + whisker per group, grouped by period.
 * cfg: {mount,w,h,m,groups:[{period, items:[{label,color,q1,med,q3}]}], y:{dom,step,title}}
 */
function quantileChart(cfg) {
  const wrap = cfg.mount, W = cfg.w, H = cfg.h, m = cfg.m;
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const svg = el("svg", { class: "chart", viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": cfg.aria || "" });
  const y = scaleLinear(cfg.y.dom[0], cfg.y.dom[1], m.t + ih, m.t);
  ticks(cfg.y.dom[0], cfg.y.dom[1], cfg.y.step).forEach(v => {
    svg.appendChild(el("line", { class: "grid", x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
    const t = el("text", { class: "ax-label", x: m.l - 9, y: y(v) + 4, "text-anchor": "end" });
    t.textContent = v; svg.appendChild(t);
  });
  svg.appendChild(el("line", { class: "axis-rule", x1: m.l, x2: m.l + iw, y1: m.t + ih, y2: m.t + ih }));
  const gw = iw / cfg.groups.length;
  const tip = makeTip(wrap);
  cfg.groups.forEach((g, gi) => {
    const gx = m.l + gw * gi;
    const t = el("text", { class: "ax-label", x: gx + gw / 2, y: m.t + ih + 19, "text-anchor": "middle" });
    t.textContent = g.period; svg.appendChild(t);
    const bw = 22, gap = 2;
    g.items.forEach((it, ii) => {
      const cxp = gx + gw / 2 + (ii - (g.items.length - 1) / 2) * (bw + 14 + gap);
      // IQR box, 2px surface gap handled by the +gap spacing between neighbours
      const r = el("rect", { x: cxp - bw / 2, y: y(it.q3), width: bw, height: Math.max(2, y(it.q1) - y(it.q3)),
        fill: it.color, rx: 3, opacity: .9, tabindex: "0", role: "img",
        "aria-label": `${g.period} ${it.label}: median ${it.med}, IQR ${it.q1} to ${it.q3}` });
      svg.appendChild(r);
      // median rule, drawn in surface color so it reads as a gap, not extra ink
      svg.appendChild(el("line", { x1: cxp - bw / 2, x2: cxp + bw / 2, y1: y(it.med), y2: y(it.med),
        stroke: "var(--surface-1)", "stroke-width": 2.5 }));
      const lab = el("text", { class: "end-label sub", x: cxp, y: y(it.q3) - 9, "text-anchor": "middle" });
      lab.textContent = it.med; svg.appendChild(lab);
      const html = `<div class="tip-h">${g.period} · ${it.label}</div>` +
        `<div class="tip-r"><span>Median age</span><span>${it.med}</span></div>` +
        `<div class="tip-r"><span>IQR</span><span>${it.q1}–${it.q3}</span></div>` +
        `<div class="tip-r"><span>Artist-years</span><span>${it.n}</span></div>`;
      const show = () => { const rr = svg.getBoundingClientRect(), wr = wrap.getBoundingClientRect();
        showTip(tip, wrap, (cxp / W) * rr.width + (rr.left - wr.left), (y(it.med) / H) * rr.height + (rr.top - wr.top), html); };
      r.addEventListener("pointerenter", show); r.addEventListener("focus", show);
      r.addEventListener("pointerleave", () => hideTip(tip)); r.addEventListener("blur", () => hideTip(tip));
    });
  });
  if (cfg.y.title) {
    const t = el("text", { class: "ax-title", x: -(m.t + ih / 2), y: 14, transform: "rotate(-90)", "text-anchor": "middle" });
    t.textContent = cfg.y.title; svg.appendChild(t);
  }
  wrap.appendChild(svg);
  return svg;
}
"""


def page(title, card, body, extra_css="", extra_js="", data_js=""):
    """Emit a self-contained design-system preview file.

    `card` is the first-line @dsCard marker dict: name/group/subtitle/viewport.
    """
    marker = (
        f'<!-- @dsCard group="{card["group"]}" name="{card["name"]}" '
        f'subtitle="{card.get("subtitle","")}" width="{card.get("width",1000)}" '
        f'height="{card.get("height",700)}" -->'
    )
    return f"""{marker}
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
{TOKENS_CSS}
{BASE_CSS}
{extra_css}
</style>
</head>
<body class="viz-root ds-root">
<div class="wrap">
{body}
</div>
<script>
{data_js}
{CHART_JS}
{extra_js}
</script>
</body>
</html>
"""
