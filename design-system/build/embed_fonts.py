#!/usr/bin/env python3
"""Self-host the design families as inlined woff2, and record which weights exist.

tokens.css names a Google Fonts URL, but a remote @import breaks the
"self-contained, no network" contract the previews and social cards are built
on — and it would make `quarto render` depend on network access. So the faces
are vendored from npm (@fontsource/*, both SIL OFL) and inlined as base64.

Static faces only exist at the weights below. Any CSS weight that is not one of
these gets synthesised by the browser, which is why every rule in the system is
written against a --fw-* token rather than an arbitrary number.

    python3 build/embed_fonts.py
"""
import base64, json, os, shutil

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths as P

ROOT = P.ROOT
OUT = P.FONTS
os.makedirs(OUT, exist_ok=True)

# Only the weights tokens.css declares: --fw-serif 300, --fw-serif-reg 400,
# --fw-body 400, --fw-medium 500, --fw-label 600.
WANT = {
    "Newsreader": ("newsreader", [300, 400, 500, 600]),
    "IBM Plex Sans": ("ibm-plex-sans", [400, 500, 600]),
}

faces, manifest, total = [], {}, 0
for family, (pkg, weights) in WANT.items():
    got = []
    for w in weights:
        src = os.path.join(P.BUILD, "node_modules", "@fontsource", pkg, "files",
                           f"{pkg}-latin-{w}-normal.woff2")
        if not os.path.exists(src):
            print(f"  ! missing {family} {w} at {src}")
            continue
        raw = open(src, "rb").read()
        total += len(raw)
        shutil.copy(src, os.path.join(OUT, os.path.basename(src)))
        faces.append(
            "@font-face {\n"
            f"  font-family: '{family}';\n"
            "  font-style: normal;\n"
            f"  font-weight: {w};\n"
            "  font-display: swap;\n"
            f"  src: url(data:font/woff2;charset=utf-8;base64,{base64.b64encode(raw).decode()})"
            " format('woff2');\n}"
        )
        got.append(w)
    manifest[family] = got

open(os.path.join(OUT, "faces-embedded.css"), "w", encoding="utf-8").write("\n".join(faces))
json.dump(manifest, open(os.path.join(OUT, "available-weights.json"), "w"), indent=1)

size = os.path.getsize(os.path.join(OUT, "faces-embedded.css"))
print(f"{len(faces)} faces, {total/1024:.0f} KB woff2 -> {size/1024:.0f} KB inlined")
for fam, ws in manifest.items():
    print(f"  {fam}: {ws}")
