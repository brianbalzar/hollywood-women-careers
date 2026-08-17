# Deployment checklist

Local deployment preparation is complete. What remains is to initialize the
repository, authenticate GitHub CLI, create the remote, push, and enable Pages.

`PUBLISHING.md` has the longer reasoning (OneDrive, license choices, repo size).
This file is the ordered checklist.

---

## Status

| | |
|---|---|
| Release files | ✅ written (`README`, `LICENSE`, `LICENSE-CONTENT`, `CITATION.cff`, `.gitignore`) |
| Design system | ✅ `tokens.css` → `R/theme_hwc.R` + `reports/hwc.scss`, generated and verified |
| Fonts | ✅ self-hosted in `fonts/`, inlined, OFL licenses included |
| Previews + social cards | ✅ built and audited, light and dark |
| Build chain | ✅ runs from any working directory against the repo layout |
| Git repository | ❌ **does not exist yet** |
| `pages.yml` | ✅ present at `.github/workflows/pages.yml`; publishes static files only |
| GitHub URLs | ✅ set to `brianbalzar` |
| Report using the new theme | ✅ `reports/index.qmd` uses `[cosmo, hwc.scss]` |

---

## 1. Completed: point the report at the theme

This is the only change to a file Codex has been working in, which is why it was
left for you. In `reports/index.qmd`, the YAML header currently reads:

```yaml
    theme: cosmo
```

Change it to:

```yaml
    theme: [cosmo, hwc.scss]
```

That is the whole change. `hwc.scss` sits beside `index.qmd` in `reports/`, so
the relative name resolves. Without it the report still renders — it just renders
in stock Bootstrap and none of the design work shows.

**Wait for Codex to finish this file first.**

## 2. Completed: place the Pages workflow

Download `pages.yml` from the chat and put it at `.github\workflows\pages.yml`:

```powershell
New-Item -ItemType Directory -Force -Path .github\workflows
# then move pages.yml into it
```

GitHub Actions workflow files are deliberately protected from remote writes — an
assistant that can silently add a workflow can silently run code in your CI. Read
it before committing; it checks out the repo, copies `reports/index.html`, the
design-system previews and the social PNGs into a `_site` folder, and hands that
to GitHub's own Pages actions. It runs no project code and installs nothing.

## 3. Completed: fill in the GitHub username

`README.md` and `CITATION.cff` contain the literal string `GITHUB_USER`, four
times between them:

```powershell
Get-ChildItem README.md, CITATION.cff | ForEach-Object {
  (Get-Content $_ -Raw) -replace 'GITHUB_USER', 'your-username' |
    Set-Content $_ -NoNewline
}
```

Tell me your handle and I can stamp it, and re-render the social cards with the
live URL in the footer.

## 4. Re-render with the bundled fonts

The report theme now registers the bundled Newsreader and IBM Plex Sans WOFF2
files with `systemfonts`. `systemfonts` and `ragg` are installed, so no separate
operating-system font installation is required on this machine.

```powershell
# Install Newsreader and IBM Plex Sans from fonts.google.com
# ("Install for all users"), then restart R and:
install.packages(c("systemfonts", "ragg"))
```

`theme_hwc()` warns once per session if a family is missing rather than falling
back silently. Then:

```r
source("R/theme_hwc.R")
ggplot2::theme_set(theme_hwc()); hwc_set_geom_defaults()
# re-run scripts/05, 07, 08, 13 to regenerate outputs/figures/
```

```powershell
quarto render reports/index.qmd
```

`reports/index.html` is currently **stale** — it was rendered before `hwc.scss`
existed, so it does not reflect any of the design work. Pages publishes that file
directly (CI cannot render it, because rendering needs the IMDb and Billboard
source data that deliberately is not in the repo), so this step is required, not
optional.

---

## 5. Initialise, verify, commit

```powershell
git init -b main
git add -A
git status --short
```

**Verify the exclusions held before committing.** These must produce no output:

```powershell
git ls-files | Select-String "\.rds$"                      # no 38 MB model
git ls-files | Select-String "data/raw/(?!.*manifest)"     # no source data
git ls-files | Select-String "node_modules|__pycache__"    # no build junk
```

Check the largest files:

```powershell
git ls-files | ForEach-Object { [PSCustomObject]@{
  MB = [math]::Round((Get-Item $_).Length/1MB,2); Path = $_ } } |
  Sort-Object MB -Descending | Select-Object -First 10
```

Expect `reports/index.html` at roughly 2.7 MB on top, then ten design-system
previews at about 0.26 MB each, then the social PNGs. **Total should land near
9 MB.** If you see a 38 MB `.rds`, the `.gitignore` did not replace correctly —
fix it before the first commit, because removing a large file afterwards means
rewriting history.

```powershell
git commit -m "Initial release: age and screen-acting opportunity analysis

Reproducible pipeline over IMDb non-commercial datasets and the Billboard
Hot 100, measuring how principal screen and chart opportunity change with
age by gender-coded credit class. Includes the rendered report, aggregate
result tables, figures, the token-driven design system, and social cards.

No source data is redistributed."
```

## 6. Push and enable Pages

```powershell
gh auth login
gh repo create hollywood-women-careers --public --source=. --remote=origin --push
```

Then **Settings → Pages → Build and deployment → Source: "GitHub Actions"**.

The report lands at `https://your-username.github.io/hollywood-women-careers/`,
the previews at `/design-system/`, the cards at `/social/`.

---

## Rebuilding the design system later

The build chain resolves the repo root from its own location, so it works from
any working directory:

```powershell
cd design-system\build; npm install          # once: playwright + fontsource
python design-system\build\embed_fonts.py         # fonts/ -> inlined faces
python design-system\build\derive_from_tokens.py  # tokens.css -> R + SCSS
python design-system\build\gen.py                 # -> design-system/*.html
python design-system\build\social.py              # -> social/*.html
node   design-system\build\shoot.mjs              # render + audit, writes PNGs
node   design-system\build\shoot-social.mjs
```

`gen.py` and `social.py` read `outputs/tables/*.csv` directly, so the previews
and cards always reflect whatever the pipeline last wrote. If a table is missing
they name it and stop rather than rendering something stale.

The audits fail on: JS errors, horizontal overflow, empty chart mounts, text
escaping the SVG box, colliding direct labels, a chart overflowing its container,
fallback fonts, synthesised font weights, and — on social cards — any text under
16 rendered pixels.

---

## Two things worth knowing

**Repo size is dominated by self-contained previews.** Each of the ten inlines
~215 KB of base64 font, so they account for about 2.6 MB. That is the price of
the "opens anywhere, no network" contract they were built to — they have to work
when uploaded to Claude Design, where a relative font path would not resolve. If
history growth becomes a problem later, the previews are the thing to stop
committing, not the report.

**`NOTES.md` and `tokens.css` sit at the repo root.** `NOTES.md` is Claude
Design's rationale; at the root of a public repo the name reads like generic
project notes. Consider `design-system/NOTES.md`. `tokens.css` can move to
`design-system/tokens.css` too — its own header suggests that path, and the build
chain checks there first and falls back to the root, so either works with no
further changes.
