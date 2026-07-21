#!/usr/bin/env python3
"""
nano-color-mapper — atmosphera post-hook that generates nano's UI color
settings from the wallpaper-derived Material palette.

Reads atmosphera's ~/.config/atmosphera/colors.json for the current
palette, then prepends a marker-delimited `set *color` block to the
passed nanorc. The rest of the file (editor defaults, syntax include)
is preserved between runs via BEGIN/END sentinels.

Design (final, after iteration with the user):
  titlecolor      : black,white           — FIXED dark-on-cream, theme-independent.
  functioncolor   : black,white           — FIXED, matches title.
  keycolor        : bold,<PRIMARY_HUE>,black   — LIGHT fg on DARK bg, hue-based fg
                                                so the shortcut color tracks the
                                                theme's dominant hue family.
                                                Falls back to `bold,white,black`
                                                if primary is too dark to see.
  numbercolor     : <PRIMARY_HUE>          — same hue family as shortcuts,
                                              no bold so the two are distinguishable
                                              by weight. Falls back to `white`.
  errorcolor      : bold,white,<error>    — always red-family (slot-aware).
  spotlightcolor  : black,<tertiary>      — search hit distinct from key/function.
  scrollercolor   : <PRIMARY_HUE>,brightblack
  Other settings  : sensible subtle defaults (brightblack backgrounds).

Two naming strategies mixed on purpose:

  slot-aware (token_name): For error/tertiary — the color's *semantic role*
    must be preserved (error must ACTUALLY be red-slot), and ghostty's
    atmosphera template guarantees that mapping. Names in the output config
    file will look 'weird' (e.g. tertiary → `brightblue`) but the color
    always renders correctly.

  hue-based (classify_by_hue): For primary (keycolor + numbercolor). The
    goal is a config file that *reads* naturally per theme — in a pink
    palette the config says `brightred`; in a blue palette it says
    `brightcyan`. The rendered color goes through whatever ghostty slot
    that name resolves to; on a themed terminal the visible hue family
    matches, on an unthemed terminal you get standard ANSI colors.

Two thresholds, one for each direction of the pair:
  bright_enough_fg (Y > 0.15): color can be a visible fg on a dark bg
  light_enough_bg  (Y > 0.35): color can be a bg for dark fg text

Uses WCAG relative luminance (not HSL lightness) because HSL lies about
perceived brightness of blues.
"""

import json
import re
import sys
from pathlib import Path


def _hex_rgb01(hex_str):
    h = hex_str.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in range(0, 6, 2))


def _hsl(hex_str):
    r, g, b = _hex_rgb01(hex_str)
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2.0
    d = mx - mn
    if d == 0:
        return 0.0, 0.0, l
    s = d / (mx + mn) if l <= 0.5 else d / (2.0 - mx - mn)
    if mx == r:
        h = ((g - b) / d) % 6.0
    elif mx == g:
        h = (b - r) / d + 2.0
    else:
        h = (r - g) / d + 4.0
    return h * 60.0, s, l


def wcag_luminance(hex_str):
    r, g, b = _hex_rgb01(hex_str)

    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


TOKEN_SLOT_NAMES = {
    "surface_variant":    ("black",       "black"),
    "on_surface_variant": ("brightblack", "brightblack"),
    "error":              ("red",         "brightred"),
    "primary":            ("green",       "brightgreen"),
    "secondary":          ("yellow",      "brightyellow"),
    "tertiary":           ("blue",        "brightblue"),
    "on_surface":         ("white",       "brightwhite"),
}


def token_name(token, hex_str):
    slots = TOKEN_SLOT_NAMES.get(token)
    if slots is None:
        return classify_by_hue(hex_str)
    base, bright = slots
    return bright if wcag_luminance(hex_str) > 0.35 else base


def classify_by_hue(hex_str):
    h, s, _ = _hsl(hex_str)
    y = wcag_luminance(hex_str)
    if y < 0.03:
        return "black"
    if s < 0.35:
        if y < 0.20:
            return "brightblack"
        if y < 0.55:
            return "white"
        return "brightwhite"
    if h < 30 or h >= 330:
        family = "red"
    elif h < 90:
        family = "yellow"
    elif h < 150:
        family = "green"
    elif h < 210:
        family = "cyan"
    elif h < 270:
        family = "blue"
    else:
        family = "magenta"
    return "bright" + family if y > 0.35 else family


def bright_enough_fg(hex_str):
    return wcag_luminance(hex_str) > 0.15


def light_enough_bg(hex_str):
    return wcag_luminance(hex_str) > 0.35


def load_atmosphera_palette():
    p = Path.home() / '.config' / 'atmosphera' / 'colors.json'
    if not p.is_file():
        return {}
    try:
        data = json.loads(p.read_text())
    except Exception as e:
        print(f"nano-color-mapper: could not parse {p}: {e}", file=sys.stderr)
        return {}
    result = {}
    for k, v in data.items():
        if isinstance(v, str) and k.startswith('m') and len(k) > 1 and k[1].isupper():
            snake = re.sub(r'(?<!^)(?=[A-Z])', '_', k[1:]).lower()
            result[snake] = v.lower()
    return result


def build_color_settings(palette):
    primary   = palette.get("primary")
    secondary = palette.get("secondary")
    tertiary  = palette.get("tertiary")
    error     = palette.get("error")

    secondary_name = token_name("secondary", secondary) if secondary else "brightyellow"
    tertiary_name  = token_name("tertiary",  tertiary)  if tertiary  else "brightblue"
    error_name     = token_name("error",     error)     if error     else "brightred"

    primary_hue_name = classify_by_hue(primary) if primary else "brightgreen"

    primary_ok_as_fg   = bright_enough_fg(primary)    if primary   else True

    titlecolor    = "black,white"
    functioncolor = "black,white"

    if primary_ok_as_fg:
        keycolor = f"bold,{primary_hue_name},black"
    else:
        keycolor = "bold,white,black"

    numbercolor = primary_hue_name if primary_ok_as_fg else "white"

    errorcolor = f"bold,white,{error_name}"

    spotlightcolor = f"black,{tertiary_name}"

    return [
        ("titlecolor",     titlecolor),
        ("statuscolor",    "bold,brightwhite,brightblack"),
        ("errorcolor",     errorcolor),
        ("spotlightcolor", spotlightcolor),
        ("selectedcolor",  ",brightblack"),
        ("numbercolor",    numbercolor),
        ("keycolor",       keycolor),
        ("functioncolor",  functioncolor),
        ("stripecolor",    ",brightblack"),
        ("scrollercolor",  f"{primary_hue_name},brightblack"),
        ("promptcolor",    titlecolor),
        ("minicolor",      "bold,brightwhite,brightblack"),
    ]


BEGIN = "# >>> atmosphera nano-color-mapper >>>"
END   = "# <<< atmosphera nano-color-mapper <<<"


def strip_previous_block(text):
    pattern = re.compile(
        rf'^{re.escape(BEGIN)}.*?{re.escape(END)}\n*', re.DOTALL | re.MULTILINE
    )
    return pattern.sub('', text, count=1)


def build_generated_block(palette, settings):
    lines = [BEGIN,
             "# Auto-generated from the current atmosphera palette. Do not hand-edit;",
             "# changes here get overwritten on every wallpaper/scheme regeneration.",
             "#"]
    lines.append("# nano ANSI slots map to ghostty's atmosphera palette as:")
    lines.append("#   green=primary  yellow=secondary  blue=tertiary  red=error")
    lines.append("#   black=surface_variant  white=on_surface  brightblack=on_surface_variant")
    lines.append("#")
    for tok in ("primary", "secondary", "tertiary", "error"):
        v = palette.get(tok, "?")
        if v and v != "?":
            y = wcag_luminance(v)
            lines.append(
                f"#   {tok:<10} = {v}  Y={y:.2f}  fg?={'y' if bright_enough_fg(v) else 'n'}"
                f"  slot={token_name(tok, v):<12}  hue={classify_by_hue(v)}"
            )
        else:
            lines.append(f"#   {tok:<10} = (missing; falling back)")
    lines.append("")
    for setting, value in settings:
        lines.append(f"set {setting} {value}")
    lines.append(END)
    return "\n".join(lines) + "\n\n"


def main():
    if len(sys.argv) != 2:
        print("Usage: nano-color-mapper <nanorc>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1]).expanduser()
    if not path.is_file():
        print(f"nano-color-mapper: file not found: {path}", file=sys.stderr)
        return 1

    palette = load_atmosphera_palette()
    settings = build_color_settings(palette)
    block = build_generated_block(palette, settings)

    existing = strip_previous_block(path.read_text())
    path.write_text(block + existing)
    return 0


if __name__ == '__main__':
    sys.exit(main())
