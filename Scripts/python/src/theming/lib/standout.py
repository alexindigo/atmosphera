"""Shared standout derivation from the dark reference accents (D5/D6/D8).

Wallpaper evidence enters only through the scheme's existing accents. Muted
and monochrome retain D4's source-complement exception. Perceptual distance
is a review/validation flag, never a hue-selection or colour-moving input.
"""

from dataclasses import dataclass
import math

from .color import Color
from .contrast import contrast_ratio
from .hct import Cam16, TonalPalette


# Artist's RYB wheel, clockwise: red, orange, yellow, green, blue, purple.
# Piecewise-linear perceptual hue anchors, deliberately NOT an RGB/HCT +180.
# These are a fixed hue design mapping, not a pigment-mixing simulation.
# HCT is unwrapped across red so both directions interpolate monotonically.
RYB_HCT_HUES = (
    (0, 25), (30, 40), (60, 55), (90, 80), (120, 100),
    (150, 130), (180, 155), (210, 200), (240, 265),
    (270, 295), (300, 315), (330, 350), (360, 385),
)

# D9: fixed source-complement chroma for monochrome and muted schemes.
MUTED_STANDOUT_CHROMA = 24.0

# Euclidean CAM16-UCS J*/a*/b* distance under hct.py's standard sRGB viewing
# conditions (not Material Utilities' 1.41*d**0.63 remapping). A review flag
# below 12 gives a clear-difference margin, not a universal visibility/JND
# guarantee. D5's approved Catppuccin tangerine #f29f1a / peach #fab387 is
# 15.1996, while the one-channel neighbour #f29e1a is 0.3796 and identity is 0.
# Other reviewed secondary collisions (Kanagawa dark 19.6062; Retreat vibrant
# light 29.2716) remain distinct. The threshold never changes generated roles.
MIN_DISTINCT_DELTA_E = 12.0


def _interpolate(value, anchors):
    for (x0, y0), (x1, y1) in zip(anchors, anchors[1:]):
        if x0 <= value <= x1:
            return y0 + (value - x0) * (y1 - y0) / (x1 - x0)
    raise ValueError('hue outside mapping')


def ryb_to_hct(hue: float) -> float:
    return _interpolate(hue % 360, RYB_HCT_HUES) % 360


def hct_to_ryb(hue: float) -> float:
    unwrapped = (hue - 25) % 360 + 25
    return _interpolate(unwrapped, tuple((h, r) for r, h in RYB_HCT_HUES)) % 360


def ryb_complement(hue: float) -> float:
    return ryb_to_hct(hct_to_ryb(hue) + 180)


def ryb_midpoint(primary: float, tertiary: float, primary_weight: float = 2.0) -> float:
    """Weighted point on the shorter RYB arc; 2:1 moves one third from P to T.

    Exactly antipodal inputs have no unique shorter arc: preserve the review
    prototype's explicit error rather than silently inventing a direction.
    """
    if not all(math.isfinite(value) for value in (primary, tertiary, primary_weight)) or primary_weight <= 0:
        raise ValueError('RYB midpoint requires finite hues and a positive weight')
    delta = (tertiary - primary + 180) % 360 - 180
    if math.isclose(abs(delta), 180, abs_tol=1e-9):
        raise ValueError('antipodal RYB accents have no unique shorter arc')
    return (primary + delta / (primary_weight + 1)) % 360


@dataclass(frozen=True)
class Selection:
    hue: float
    rule: str


def select_hue(primary: Color, tertiary: Color, *, source: Color | None = None,
               scheme_type: str = '') -> Selection:
    if scheme_type in ('monochrome', 'muted'):
        if source is None:
            raise ValueError('monochrome/muted standout requires the source colour')
        return Selection(ryb_complement(source.to_hct().hue), 'source-complement')
    midpoint = ryb_midpoint(hct_to_ryb(primary.to_hct().hue),
                            hct_to_ryb(tertiary.to_hct().hue))
    return Selection(ryb_to_hct(midpoint + 180), 'dual-complement-2:1')


def perceptual_difference(first: Color, second: Color) -> float:
    """Raw Euclidean CAM16-UCS Delta E, including lightness and colourfulness."""
    a, b = (Cam16.from_rgb(*color.to_rgb()) for color in (first, second))
    return math.dist((a.jstar, a.astar, a.bstar), (b.jstar, b.astar, b.bstar))


def accent_differences(standout: Color, theme: dict[str, str]) -> dict[str, float]:
    """Review all three accents without changing the selected or final colour."""
    return {role: perceptual_difference(standout, Color.from_hex(theme[role]))
            for role in ('primary', 'secondary', 'tertiary')}


def indistinct_accents(differences: dict[str, float]) -> tuple[str, ...]:
    return tuple(role for role, distance in differences.items() if distance < MIN_DISTINCT_DELTA_E)


def clashes(hue_a: float, chroma_a: float, hue_b: float, chroma_b: float) -> bool:
    """Conservative vibration check, not a universal aesthetic judgement.

    Red (HCT 350..40) and blue (250..290) both at C>=48 are the high-chroma
    edge-vibration pair from D1. Small icons do not need both full-strength.
    Soften standout only; preserve its derived hue and every pre-existing role.
    """
    def red(h):
        return h % 360 >= 350 or h % 360 <= 40
    def blue(h):
        return 250 <= h % 360 <= 290
    return min(chroma_a, chroma_b) >= 48 and (
        (red(hue_a) and blue(hue_b)) or (blue(hue_a) and red(hue_b)))


def matched_chroma(primary: Color, hue: float, muted_chroma: float | None = None) -> float:
    hct = primary.to_hct()
    chroma = (max(32.0, min(56.0, hct.chroma * 1.15 + 8.0))
              if muted_chroma is None else muted_chroma)
    if not math.isfinite(chroma) or chroma < 0:
        raise ValueError('standout chroma must be finite and non-negative')
    return min(chroma, 40.0) if clashes(hct.hue, hct.chroma, hue, chroma) else chroma


@dataclass(frozen=True)
class Synthesis:
    standout: str
    on_standout: str
    selected_tone: int
    surface_contrast: float


def on_standout_color(standout: Color, mode: str) -> str:
    """Choose a readable foreground independently for each display mode."""
    if mode not in ('dark', 'light'):
        raise ValueError('standout mode must be dark or light')
    palette = TonalPalette.from_rgb(*standout.to_rgb())
    tones = (*range(20, -1, -1), 100) if mode == 'dark' else (100, *range(20, -1, -1))
    for tone in tones:
        color = Color.from_hex(palette.get_hex(tone))
        if contrast_ratio(color, standout) >= 4.5:
            return color.to_hex()
    raise ValueError('no on_standout tone meets text contrast')


def synthesis_details(primary: Color, surface: Color, mode: str, selection: Selection,
                      *, muted_chroma: float | None = None) -> Synthesis:
    """D2/D8 canonical dark colour, with a per-mode foreground and measurement.

    primary/selection always belong to the dark reference scheme. Maximize
    actual in-gamut chroma over integer T60..75, ties nearest T67 then lower.
    Surface contrast is observational only: neither mode changes or rejects a
    standout to satisfy a surface floor. Mode affects only the on-colour.
    """
    if mode not in ('dark', 'light'):
        raise ValueError('standout mode must be dark or light')
    palette = TonalPalette(selection.hue, matched_chroma(primary, selection.hue, muted_chroma))
    primary_hct = primary.to_hct()
    choices = []
    for tone in range(60, 76):
        color = Color.from_hex(palette.get_hex(tone))
        hct = color.to_hct()
        if not clashes(primary_hct.hue, primary_hct.chroma, hct.hue, hct.chroma):
            choices.append((tone, color, hct.chroma, contrast_ratio(color, surface)))
    if not choices:
        raise ValueError('no standout tone meets harmony')
    selected = max(choices, key=lambda choice: (choice[2], -abs(choice[0] - 67), -choice[0]))
    tone, standout, _, surface_contrast = selected
    return Synthesis(standout.to_hex(), on_standout_color(standout, mode), tone, surface_contrast)


def synthesize(primary: Color, surface: Color, mode: str, selection: Selection,
               *, muted_chroma: float | None = None) -> dict[str, str]:
    result = synthesis_details(primary, surface, mode, selection, muted_chroma=muted_chroma)
    return {'standout': result.standout, 'on_standout': result.on_standout}


def standout_roles(dark_theme: dict[str, str], mode: str, *, source: Color | None = None,
                   scheme_type: str = '',
                   surface: Color | None = None) -> dict[str, str]:
    """One dark-reference owner for both modes, including hue and matched chroma.

    The optional display surface is measured only; it cannot change the colour.
    A caller generating light alone must still supply the actual dark accents.
    """
    primary = Color.from_hex(dark_theme['primary'])
    selection = select_hue(primary, Color.from_hex(dark_theme['tertiary']), source=source, scheme_type=scheme_type)
    return synthesize(primary, surface if surface is not None else Color.from_hex(dark_theme['surface']), mode, selection,
                       muted_chroma=MUTED_STANDOUT_CHROMA if scheme_type in ('monochrome', 'muted') else None)
