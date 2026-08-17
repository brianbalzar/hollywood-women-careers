"""Canonical repository paths for the design-system build chain.

The build scripts live at `design-system/build/`, but almost everything they
read and write lives at the repository root (`tokens.css`, `fonts/`, `R/`,
`reports/`, `outputs/tables/`, `social/`). This module finds the root once and
hands out the paths, so no script has to guess how deep it is.

It also loads the result tables straight from `outputs/tables/*.csv` — the CSVs
are the source of truth, so the previews and social cards are always built from
whatever the pipeline last wrote, not from a snapshot.
"""
import csv
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def _find_root(start):
    """Walk up until we find the repo root, identified by its own landmarks."""
    d = start
    for _ in range(6):
        if all(os.path.exists(os.path.join(d, m)) for m in ("R", "scripts", "outputs")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    # Fall back to two levels up (design-system/build -> repo root), which is
    # the layout this file is committed in.
    return os.path.abspath(os.path.join(_HERE, "..", ".."))


ROOT = _find_root(_HERE)

DESIGN = os.path.join(ROOT, "design-system")
BUILD = os.path.join(DESIGN, "build")
FONTS = os.path.join(ROOT, "fonts")
SOCIAL = os.path.join(ROOT, "social")
TABLES = os.path.join(ROOT, "outputs", "tables")
FIGURES = os.path.join(ROOT, "outputs", "figures")
SHOTS = os.path.join(BUILD, "shots")

OUT_R = os.path.join(ROOT, "R", "theme_hwc.R")
OUT_SCSS = os.path.join(ROOT, "reports", "hwc.scss")


def tokens_path():
    """tokens.css, whether it sits at the repo root or inside design-system/."""
    for candidate in (os.path.join(DESIGN, "tokens.css"),
                      os.path.join(ROOT, "tokens.css")):
        if os.path.exists(candidate):
            return candidate
    raise SystemExit(
        "tokens.css not found. Expected it at design-system/tokens.css or at the "
        f"repository root. Looked under: {ROOT}")


# Result tables the previews and social cards draw on.
NEEDED = [
    "women_role_share", "adjusted_exit_hazard_ratio",
    "role_share_change_points", "billboard_women_share_by_age",
    "billboard_return_by_age", "billboard_age_summary",
    "explicit_character_family_labels",
]


def load_tables(names=None):
    """Read result tables from outputs/tables/ as lists of dicts."""
    names = names or NEEDED
    out, missing = {}, []
    for n in names:
        p = os.path.join(TABLES, n + ".csv")
        if not os.path.exists(p):
            missing.append(n + ".csv")
            continue
        with open(p, newline="", encoding="utf-8-sig") as f:
            out[n] = list(csv.DictReader(f))
    if missing:
        raise SystemExit(
            "Missing result tables in outputs/tables/: " + ", ".join(missing) +
            "\nRun the analysis pipeline first (scripts/05, 07, 08, 13).")
    return out
