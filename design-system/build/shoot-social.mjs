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
const DIR = path.join(ROOT, 'social');
const files = fs.readdirSync(DIR).filter(f => f.endsWith('.html')).sort();
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
const ctx = await browser.newContext({
  viewport: { width: 1200, height: 1200 },
  deviceScaleFactor: 2,           // 2400x2400 output; platforms downscale cleanly
  colorScheme: 'light',
});
let bad = 0;

for (const f of files) {
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(e.message));
  await page.goto('file://' + path.join(DIR, f));
  await page.waitForTimeout(400);
  await page.evaluate(() => document.fonts.ready);

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
    const card = document.querySelector('.card');
    const out = { h: card.scrollHeight, w: card.scrollWidth, over: [], clipped: [], tiny: [] };
    // anything spilling out of the 1200x1200 card
    const cb = card.getBoundingClientRect();
    document.querySelectorAll('.card *').forEach(n => {
      const b = n.getBoundingClientRect();
      if (b.width === 0 || b.height === 0) return;
      if (b.right > cb.right + 1 || b.bottom > cb.bottom + 1 || b.left < cb.left - 1) {
        out.over.push(n.tagName.toLowerCase() + (n.className.baseVal ?? n.className ?? ''));
      }
    });
    // an SVG with overflow:visible inside a flex row can spill past .plot and
    // land on the legend above or the footer below without failing any other check
    document.querySelectorAll('.plot').forEach(pl => {
      const pb = pl.getBoundingClientRect();
      pl.querySelectorAll('svg.chart').forEach(svg => {
        const sb = svg.getBoundingClientRect();
        if (sb.top < pb.top - 1 || sb.bottom > pb.bottom + 1) {
          out.over.push(`chart overflows .plot by ${Math.round(Math.max(pb.top - sb.top, sb.bottom - pb.bottom))}px`);
        }
      });
    });
    document.querySelectorAll('svg.chart').forEach(svg => {
      const s = svg.getBoundingClientRect();
      svg.querySelectorAll('text').forEach(t => {
        const b = t.getBoundingClientRect();
        if (!b.width) return;
        if (b.left < s.left - 2 || b.right > s.right + 2 || b.bottom > s.bottom + 2) {
          out.clipped.push(t.textContent.slice(0, 24));
        }
        // legibility floor at feed scale: nothing under 16 rendered px
        const fs = parseFloat(getComputedStyle(t).fontSize) * (s.width / svg.viewBox.baseVal.width);
        if (fs < 16) out.tiny.push(t.textContent.slice(0, 18) + ` (${fs.toFixed(1)}px)`);
      });
    });
    out.fontsOk = fontsOk; out.synth = [...synth];
    return out;
  });

  await page.locator('.card').screenshot({ path: path.join(DIR, f.replace('.html', '.png')) });

  const iss = [];
  if (errs.length) iss.push('JS: ' + errs[0]);
  if (!audit.fontsOk) iss.push('design fonts did NOT load — rendered in fallback');
  if (audit.synth && audit.synth.length) iss.push('synthesised weight (no matching face): ' + audit.synth.join(', '));
  if (audit.h > 1201 || audit.w > 1201) iss.push(`card is ${audit.w}x${audit.h}, not 1200x1200`);
  if (audit.over.length) iss.push('overflowing card: ' + [...new Set(audit.over)].slice(0, 4).join(', '));
  if (audit.clipped.length) iss.push('clipped text: ' + audit.clipped.slice(0, 4).join(' ; '));
  if (audit.tiny.length) iss.push('below 16px: ' + [...new Set(audit.tiny)].slice(0, 4).join(' ; '));
  if (iss.length) { bad++; console.log(`✗ ${f}\n    ` + iss.join('\n    ')); }
  else console.log(`✓ ${f}  →  ${f.replace('.html', '.png')} (2400x2400)`);
  await page.close();
}
await browser.close();
console.log(bad ? `\n${bad} card(s) with issues` : '\nall cards clean');
