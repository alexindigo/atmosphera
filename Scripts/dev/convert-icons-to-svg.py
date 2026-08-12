#!/usr/bin/env python3
"""
Convert the legacy icon font (noctalia-icons-legacy) to per-icon SVG files
for the atmosphera-icons plugin.

Mapping chain:
  icons.json key -> codepoint -> TTF glyph name (Fontello preserves them)
  glyph name -> Tabler SVG (icons/outline, icons/filled) when it exists
             -> font-outline extraction (SVGPathPen) for custom/renamed glyphs

Inputs:
  --font      Plugins/noctalia-icons-legacy/assets/atmosphera-tabler-icons.ttf
  --icons     Plugins/noctalia-icons-legacy/icons.json
  --tabler    checkout of tabler-icons (pinned commit recorded in output)
  --out       output dir for the new plugin (e.g. Plugins/atmosphera-icons)

Output:
  <out>/icons.json            {"icons": {key: {"filename": "<key>.svg"}}}
  <out>/svg/<key>.svg         one per key
  <out>/CONVERSION.md         provenance: tabler commit, font-extracted list
"""

import argparse
import json
import os
import subprocess
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen


def glyph_svg(ttf, glyph_name, upm):
    """Extract a glyph's outline as an SVG, framed on the glyph's ink bbox.

    Font coords are Y-up; SVG is Y-down, so the path is Y-flipped with
    scale(1,-1) and the viewBox uses the negated-Y bounds.
    """
    glyph_set = ttf.getGlyphSet()
    glyph = glyph_set[glyph_name]

    bounds_pen = BoundsPen(glyph_set)
    glyph.draw(bounds_pen)
    if bounds_pen.bounds is None:
        return None
    x_min, y_min, x_max, y_max = bounds_pen.bounds
    width = x_max - x_min
    height = y_max - y_min
    if width <= 0 or height <= 0:
        return None

    pen = SVGPathPen(glyph_set)
    glyph.draw(pen)
    path = pen.getCommands()
    if not path:
        return None

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s">'
        '<path d="%s" transform="scale(1,-1)"/></svg>'
        % (_num(x_min), _num(-y_max), _num(width), _num(height), path)
    )


def _num(v):
    """Compact number formatting for viewBox values."""
    return str(int(v)) if float(v) == int(v) else f"{v:.2f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--icons", required=True)
    ap.add_argument("--tabler", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    ttf = TTFont(args.font)
    cmap = ttf.getBestCmap()
    upm = ttf["head"].unitsPerEm

    with open(args.icons) as fh:
        icons = json.load(fh)["icons"]

    outline_dir = os.path.join(args.tabler, "icons", "outline")
    filled_dir = os.path.join(args.tabler, "icons", "filled")
    outline = {fn[:-4] for fn in os.listdir(outline_dir) if fn.endswith(".svg")}
    filled = {fn[:-4] for fn in os.listdir(filled_dir) if fn.endswith(".svg")}

    tabler_commit = subprocess.check_output(
        ["git", "-C", args.tabler, "rev-parse", "HEAD"], text=True
    ).strip()

    svg_dir = os.path.join(args.out, "svg")
    os.makedirs(svg_dir, exist_ok=True)

    out_icons = {}
    extracted = []
    copied = 0
    failures = []

    for key, entry in sorted(icons.items()):
        cp = int(entry["codepoint"], 16)
        gname = cmap.get(cp)
        if gname is None:
            failures.append((key, "no glyph for codepoint"))
            continue

        # Tabler source selection: outline by default; "-filled" glyphs map
        # to the filled dir (without the suffix).
        src = None
        if gname in outline:
            src = os.path.join(outline_dir, gname + ".svg")
        elif gname.endswith("-filled") and gname[:-7] in filled:
            src = os.path.join(filled_dir, gname[:-7] + ".svg")
        elif gname in filled:
            src = os.path.join(filled_dir, gname + ".svg")

        if src is not None:
            with open(src) as fh:
                svg = fh.read()
            copied += 1
        else:
            svg = glyph_svg(ttf, gname, upm)
            if svg is None:
                failures.append((key, "empty outline for " + gname))
                continue
            extracted.append(key)

        filename = key + ".svg"
        with open(os.path.join(svg_dir, filename), "w") as fh:
            fh.write(svg + "\n")
        out_icons[key] = {"filename": "svg/" + filename}

    with open(os.path.join(args.out, "icons.json"), "w") as fh:
        json.dump({"icons": out_icons}, fh, indent=2)
        fh.write("\n")

    with open(os.path.join(args.out, "CONVERSION.md"), "w") as fh:
        fh.write(
            "# Icon set conversion\n\n"
            "Generated from noctalia-icons-legacy (Fontello TTF) + tabler-icons.\n\n"
            "- tabler-icons commit: `%s`\n"
            "- Tabler-sourced icons: %d\n"
            "- Font-extracted icons (custom/renamed glyphs): %d\n\n"
            "Font-extracted keys:\n\n%s\n"
            % (tabler_commit, copied, len(extracted),
               "\n".join("- " + k for k in extracted))
        )

    print("copied from tabler:", copied)
    print("extracted from font:", len(extracted))
    if failures:
        print("FAILURES:", len(failures))
        for key, why in failures[:20]:
            print("  ", key, "-", why)
        sys.exit(1)


if __name__ == "__main__":
    main()
