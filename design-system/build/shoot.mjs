import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Resolve the repo root from this file's location, so the script works from any cwd.
const HERE = path.dirname(fileURLToPath(import.meta.url));
function findRoot(d) {
  for (let i = 0; i < 6; i++) {
    if (['R', 'scripts', 'outputs'].every(m => fs.existsSync(path.join(d, m)))) return d;
    const up = path.dirname(d); if (up === d) break; d = up;
  }
  return path.resolve(HERE, '..', '..');
}
const ROOT = findRoot(HERE);
const BUNDLE = path.join(ROOT, 'design-system');
const SHOTS = path.join(HERE, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

const files = [];
for (const dir of ['foundations', 'charts', 'components']) {
  for (const f of fs.readdirSync(path.join(BUNDLE, dir))) {
    if (f.endsWith('.html')) files.push(path.join(dir, f));
  }
}

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
let problems = 0;

for (const mode of ['light', 'dark']) {
  const ctx = await browser.newContext({
    viewport: { width: 1040, height: 900 },
    deviceScaleFactor: 2,
    colorScheme: mode,
  });
  for (const rel of files) {
    const page = await ctx.newPage();
    const errs = [];
    page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
    page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
    await page.goto('file://' + path.join(BUNDLE, rel));
    await page.waitForTimeout(400);
  await page.evaluate(() => document.fonts.ready);

    // open all table views so the disclosure content is checked too
    await page.evaluate(() => document.querySelectorAll('details').forEach(d => d.open = true));
    await page.waitForTimeout(120);

    // geometry audit
    const audit = await page.evaluate(() => {
      // document.fonts.check() returns true for any resolvable family, so measure
      // instead: a loaded webfont must render at a different width than the fallback.
      const loadedFams = new Set([...document.fonts]
        .filter(f => f.status === 'loaded')
        .map(f => f.family.replace(/["']/g, '')));
      const fontsOk = loadedFams.has('Newsreader') && loadedFams.has('IBM Plex Sans');
      // any weight without a matching @font-face is synthesised by the browser
      const HAVE = { Newsreader: [300,400,500,600], 'IBM Plex Sans': [400,500,600] };
      const synth = new Set();
      document.querySelectorAll('body *').forEach(n => {
        if (!n.textContent.trim()) return;
        const cs = getComputedStyle(n);
        const fam = cs.fontFamily.split(',')[0].replace(/["']/g, '').trim();
        if (!HAVE[fam]) return;
        const w = parseInt(cs.fontWeight, 10);
        if (!HAVE[fam].includes(w)) synth.add(fam + ' ' + w);
      });
      const out = { collide: [], overflowX: document.documentElement.scrollWidth > window.innerWidth + 1, clipped: [], empty: [] };
      document.querySelectorAll('.chart-wrap').forEach(w => {
        if (!w.querySelector('svg')) out.empty.push(w.id || '(anon)');
      });
      // any SVG text escaping the rendered svg box (client rects, so transforms count)
      document.querySelectorAll('svg.chart').forEach(svg => {
        const s = svg.getBoundingClientRect();
        svg.querySelectorAll('text').forEach(t => {
          const b = t.getBoundingClientRect();
          if (b.width === 0) return;
          if (b.left < s.left - 2 || b.right > s.right + 2 || b.bottom > s.bottom + 2 || b.top < s.top - 2) {
            out.clipped.push((svg.parentElement.id || '?') + ' :: "' + t.textContent.slice(0, 28) + '"');
          }
        });
      });
      // overlapping direct labels within a chart
      document.querySelectorAll('svg.chart').forEach(svg => {
        const labs = [...svg.querySelectorAll('text.end-label, text.annot, text.panel-title')]
          .map(t => ({ t, r: t.getBoundingClientRect() })).filter(o => o.r.width > 0);
        for (let a = 0; a < labs.length; a++) for (let b = a + 1; b < labs.length; b++) {
          const A = labs[a].r, B = labs[b].r;
          if (A.left < B.right && B.left < A.right && A.top < B.bottom && B.top < A.bottom) {
            out.collide.push(`"${labs[a].t.textContent.slice(0,20)}" x "${labs[b].t.textContent.slice(0,20)}"`);
          }
        }
      });
      out.fontsOk = fontsOk; out.synth = [...synth];
      return out;
    });

    const tag = rel.replace(/[\/]/g, '_').replace('.html', '');
    await page.screenshot({ path: path.join(SHOTS, `${tag}.${mode}.png`), fullPage: true });

    const issues = [];
    if (errs.length) issues.push('JS: ' + errs.slice(0, 3).join(' | '));
    if (!audit.fontsOk) issues.push('design fonts did NOT load — rendered in fallback');
    if (audit.synth && audit.synth.length) issues.push('synthesised weight (no matching face): ' + audit.synth.join(', '));
    if (audit.overflowX) issues.push('horizontal overflow');
    if (audit.empty.length) issues.push('empty chart mounts: ' + audit.empty.join(', '));
    if (audit.clipped.length) issues.push('text outside svg box: ' + audit.clipped.slice(0, 6).join(' ; '));
    if (audit.collide.length) issues.push('label collision: ' + [...new Set(audit.collide)].slice(0, 6).join(' ; '));
    if (issues.length) { problems++; console.log(`✗ [${mode}] ${rel}\n    ` + issues.join('\n    ')); }
    else console.log(`✓ [${mode}] ${rel}`);
    await page.close();
  }
  await ctx.close();
}
await browser.close();
console.log(problems ? `\n${problems} page(s) with issues` : '\nall pages clean');
