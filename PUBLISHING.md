# Publishing this project to GitHub

There is **no git repository here yet** — `.git` does not exist. These are the
steps to create one and publish, in order. Run them from the project root.

---

## Before you start: two things to decide

### 1. OneDrive

The project currently lives under `OneDrive - Upchurch US`. Git and OneDrive
both want to manage the same files, and OneDrive has been known to corrupt
`.git` by syncing objects mid-write or by holding file locks during a rebase.
It usually works; when it fails, it fails in ways that are annoying to recover
from.

Three options, best first:

- **Move the project out of OneDrive** — e.g. to `C:\Users\BrianBalzar\Projects\hollywood-women-careers`.
  Clean, and GitHub becomes the backup that OneDrive was providing.
- **Exclude `.git` from sync** — OneDrive settings → *Choose folders*, or right-click
  the `.git` folder → *Always keep on this device* off / *Free up space*. Partial protection.
- **Leave it and accept the risk.** Push often; a corrupted local `.git` is
  recoverable from the remote.

### 2. Let Codex finish first

Codex was mid-pass on `reports/index.qmd`. Wait for it to settle before the
first commit, or the initial history captures a half-edited report. Nothing in
the design-system work touches that file.

---

## Step 1 — drop in the release files

These were prepared for you and are already written into the project:

| File | What it does |
|---|---|
| `.gitignore` | **Replaces the existing one.** Adds the 38 MB fitted model, `node_modules`, and build artefacts. Keeps the data-cache exclusions you already had, and now allows the `*_manifest.csv` provenance files through. |
| `LICENSE` | MIT, for the code. **Replaces** the previous provenance note. |
| `LICENSE-CONTENT.md` | The dual-license explanation, CC BY 4.0 for text and figures, and the IMDb/Billboard data terms — the content of the old `LICENSE` now lives here, expanded. |
| `README.md` | **Replaces** the existing one. Public-facing: findings, reproduction, limits, license. |
| `CITATION.cff` | GitHub renders a "Cite this repository" button from this. |
| `.github/workflows/pages.yml` | Publishes the rendered report and static design assets to GitHub Pages. |

### The workflow file has to be added manually

Everything in the table above was written into the project for you **except**
`.github/workflows/pages.yml`. GitHub Actions workflow files are deliberately
protected from being written by remote tooling — an assistant that can silently
add a workflow is an assistant that can silently run code in your CI. That is a
guard worth having, so this one is on you.

Download `pages.yml` from the chat and put it at:

```
.github\workflows\pages.yml
```

Create the two folders if they do not exist:

```powershell
New-Item -ItemType Directory -Force -Path .github\workflows
```

Read it before you commit it — it checks out the repo, copies
`reports/index.html`, `design-system/` and `social/` into a `_site` folder, and
hands that to GitHub's own Pages actions. It runs no project code and installs
nothing.

**Two placeholders to fill in first.** `README.md` and `CITATION.cff` both
contain the literal string `GITHUB_USER` (four occurrences total). Replace it
with your GitHub username:

```powershell
# from the project root, PowerShell
Get-ChildItem README.md, CITATION.cff | ForEach-Object {
  (Get-Content $_ -Raw) -replace 'GITHUB_USER', 'your-username' |
    Set-Content $_ -NoNewline
}
```

---

## Step 2 — render the report

Pages publishes a *pre-rendered* `reports/index.html`, because rendering needs
the IMDb and Billboard source data that deliberately is not in the repository.
So render before you commit:

```powershell
quarto render reports/index.qmd
```

Confirm `reports/index.html` exists and opens correctly. It is a ~3 MB
self-contained file (`embed-resources: true`), which is why it can be served as
a single page.

---

## Step 3 — initialise and check what git sees

```powershell
git init -b main
git add -A
git status --short
```

**Before committing, verify the exclusions held.** These must produce no
output:

```powershell
git ls-files | Select-String "data/raw/(?!.*manifest)"   # no source data
git ls-files | Select-String "\.rds$"                    # no 38 MB model
```

And check nothing large slipped through:

```powershell
git ls-files -s | ForEach-Object { $p = ($_ -split "`t")[1]; [PSCustomObject]@{
  MB = [math]::Round((Get-Item $p).Length/1MB,2); Path = $p } } |
  Sort-Object MB -Descending | Select-Object -First 10
```

The largest file should be `reports/index.html` at roughly 3 MB. Total repo
should land around 5 MB. If you see a 38 MB `.rds`, the `.gitignore` did not
replace correctly — fix it before the first commit, because removing a large
file after the fact means rewriting history.

---

## Step 4 — first commit

```powershell
git commit -m "Initial release: age and screen-acting opportunity analysis

Reproducible pipeline over IMDb non-commercial datasets and the Billboard
Hot 100, measuring how principal screen and chart opportunity change with
age by gender-coded credit class. Includes the rendered report, aggregate
result tables, figures, and the figure design system.

No source data is redistributed."
```

---

## Step 5 — create the remote and push

With the [GitHub CLI](https://cli.github.com):

```powershell
gh auth login
gh repo create hollywood-women-careers --public --source=. --remote=origin --push
```

Without it: create an empty repo named `hollywood-women-careers` on
github.com (no README, no license, no .gitignore — you have all three), then:

```powershell
git remote add origin https://github.com/your-username/hollywood-women-careers.git
git push -u origin main
```

---

## Step 6 — turn on Pages

In the repository: **Settings → Pages → Build and deployment → Source:
"GitHub Actions"**.

That is the whole setup, assuming you added `pages.yml` in Step 1. It runs on the
first push after you enable it, or you can trigger it from **Actions → Publish
report to Pages → Run workflow**.

The report will be at:

```
https://your-username.github.io/hollywood-women-careers/
```

with the design-system previews at `/design-system/` and the social cards at
`/social/`.

---

## Afterwards

**Re-publishing.** The workflow triggers on any push that touches
`reports/index.html`, `outputs/figures/`, `social/` or `design-system/`. So the
loop is: re-run the pipeline → `quarto render` → commit → push.

**Repository size over time.** `reports/index.html` is ~3 MB and every render
produces a fresh blob, so a hundred renders is a few hundred MB of history.
If that becomes a problem, either stop committing the rendered HTML and have CI
render it from cached aggregate tables, or squash the report's history
periodically. Not urgent; worth knowing.

**Topics.** Add repository topics so it is findable:
`reproducible-research`, `r`, `quarto`, `imdb`, `gender-studies`,
`survival-analysis`, `data-journalism`.

**Description.** Suggested: *How screen-acting and chart opportunity change with
age, and whether the pattern differs by gender-coded credit class. Reproducible
R + Quarto analysis of IMDb and the Billboard Hot 100.*
