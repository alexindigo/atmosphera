"""Shared standout selection and synthesis, independent of scheme generation.

Only original detailed (tonal-spot) cluster populations are image evidence.
Bundled-scheme review uses secondary/tertiary as equal-weight candidates, with
the same family/selection/synthesis contract. No other role is ever modified.
"""

from dataclasses import dataclass
import math

from .color import Color, hue_distance
from .contrast import contrast_ratio
from .hct import TonalPalette
from .quantizer import source_color_to_rgb


# Artist's RYB wheel, clockwise: red, orange, yellow, green, blue, purple.
# Piecewise-linear perceptual hue anchors, deliberately NOT an RGB/HCT +180.
# These are a fixed hue design mapping, not a pigment-mixing simulation.
# HCT is unwrapped across red so both directions interpolate monotonically.
RYB_HCT_HUES = (
    (0, 25), (30, 40), (60, 55), (90, 80), (120, 100),
    (150, 130), (180, 155), (210, 200), (240, 265),
    (270, 295), (300, 315), (330, 350), (360, 385),
)

# Provisional review parameter, not a user-selected final muted saturation.
MUTED_STANDOUT_CHROMA = 24.0
MIN_CHROMA = 16.0
MAX_FAMILY_WIDTH = 30.0
MIN_IMAGE_SHARE = 0.02
MIN_SEPARATION = 60.0


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


@dataclass(frozen=True)
class Candidate:
    hex: str
    hue: float
    chroma: float
    population: int

    @classmethod
    def from_color(cls, color: Color, population: int):
        hct = color.to_hct()
        return cls(color.to_hex(), hct.hue, hct.chroma, population)


def image_candidates(clusters: dict[int, int]) -> tuple[Candidate, ...]:
    return tuple(Candidate.from_color(Color(*source_color_to_rgb(argb)), count)
                 for argb, count in clusters.items() if count > 0)


def family_width(members) -> float:
    """Shortest covering arc, invariant to the arbitrary hue origin."""
    hues = sorted(c.hue % 360 for c in members)
    gaps = [(hues[(i + 1) % len(hues)] - h) % 360 for i, h in enumerate(hues)]
    # Identical hues (including singletons) have zero width, not 360.
    return 0.0 if len(set(hues)) == 1 else 360 - max(gaps)


def hue_families(candidates) -> tuple[tuple[Candidate, ...], ...]:
    """Complete-span agglomeration, not fixed bins or single-link chaining.

    Start with chromatic singleton clusters. Repeatedly merge the pair with
    the smallest combined covering arc, only if that arc is <=30 degrees.
    Equal widths (rounded to 1e-9 degrees for floating noise) prefer larger
    combined population, then sorted member hexes. Neither partition nor tie
    breaking uses an absolute hue origin or input order. Families are disjoint;
    every merge enforces the whole-family width bound.
    """
    groups = [(c,) for c in sorted(candidates, key=lambda c: c.hex)
              if c.chroma >= MIN_CHROMA and c.population > 0]
    while True:
        choices = []
        for i, first in enumerate(groups):
            for j in range(i + 1, len(groups)):
                merged = tuple(sorted(first + groups[j], key=lambda c: c.hex))
                width = family_width(merged)
                if width <= MAX_FAMILY_WIDTH + 1e-9:
                    choices.append((round(width, 9), -sum(c.population for c in merged),
                                    tuple(c.hex for c in merged), i, j, merged))
        if not choices:
            return tuple(groups)
        *_, i, j, merged = min(choices)
        groups[i] = merged
        groups.pop(j)


def supported_member(family) -> Candidate:
    floor = math.ceil(max(c.population for c in family) * 0.25)
    return min((c for c in family if c.population >= floor),
               key=lambda c: (-c.chroma, -c.population, c.hex))


def family_hue(family) -> float:
    x = sum(c.population * math.cos(math.radians(c.hue)) for c in family)
    y = sum(c.population * math.sin(math.radians(c.hue)) for c in family)
    return math.degrees(math.atan2(y, x)) % 360


@dataclass(frozen=True)
class Selection:
    hue: float
    rule: str
    member: str | None = None
    share: float = 0.0
    separation: float = 0.0


def select_hue(primary: Color, candidates=(), total_pixels: int = 0,
               *, source: Color | None = None, scheme_type: str = '') -> Selection:
    primary_hue = primary.to_hct().hue
    if scheme_type in ('monochrome', 'muted'):
        if source is None:
            raise ValueError('monochrome/muted standout requires the source colour')
        return Selection(ryb_complement(source.to_hct().hue), 'source-complement')
    families = [f for f in hue_families(candidates)
                if total_pixels > 0 and sum(c.population for c in f) / total_pixels
                >= MIN_IMAGE_SHARE - 1e-12]
    if families:
        family = min(families, key=lambda f: (
            -hue_distance(family_hue(f), primary_hue),
            -sum(c.population for c in f), -supported_member(f).chroma,
            supported_member(f).hex))
        distance = hue_distance(family_hue(family), primary_hue)
        if distance >= MIN_SEPARATION - 1e-9:
            member = supported_member(family)
            return Selection(member.hue, 'existing-colour', member.hex,
                             sum(c.population for c in family) / total_pixels, distance)
    return Selection(ryb_complement(primary_hue), 'ryb-complement')


def clashes(hue_a: float, chroma_a: float, hue_b: float, chroma_b: float) -> bool:
    """Conservative vibration check, not a universal aesthetic judgement.

    Red (HCT 350..40) and blue (250..290) both at C>=48 are the high-chroma
    edge-vibration pair from D1. Small icons do not need both full-strength.
    Soften standout only; preserve its image hue and every pre-existing role.
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


def synthesize(primary: Color, surface: Color, mode: str, selection: Selection,
               *, muted_chroma: float | None = None) -> dict[str, str]:
    """Highest actual in-gamut chroma at integer T60..75; light T40/on T100.

    Ties prefer T67 (centre of the saturated dark range), then lower tone.
    Search only tones satisfying surface contrast and the final clash check.
    Dark on-colour is the lightest tone <=T20 that clears 4.5:1, else black.
    Contrast is measured on the final quantized 8-bit sRGB, never ideal HCT.
    Impossible custom surfaces fail explicitly rather than altering other roles.
    """
    if mode not in ('dark', 'light'):
        raise ValueError('standout mode must be dark or light')
    palette = TonalPalette(selection.hue, matched_chroma(primary, selection.hue, muted_chroma))
    primary_hct = primary.to_hct()
    choices = []
    for tone in range(60, 76) if mode == 'dark' else (40,):
        color = Color.from_hex(palette.get_hex(tone))
        hct = color.to_hct()
        if (contrast_ratio(color, surface) >= 3.0
                and not clashes(primary_hct.hue, primary_hct.chroma, hct.hue, hct.chroma)):
            choices.append((hct.chroma, -abs(tone - 67), -tone, color))
    if not choices:
        raise ValueError('no standout tone meets surface contrast and harmony')
    standout = max(choices, key=lambda item: item[:3])[3]
    on_tones = range(20, -1, -1) if mode == 'dark' else (100,)
    on = next((Color.from_hex(palette.get_hex(t)) for t in on_tones
               if contrast_ratio(Color.from_hex(palette.get_hex(t)), standout) >= 4.5), None)
    if on is None:
        raise ValueError('no on_standout tone meets text contrast')
    return {'standout': standout.to_hex(), 'on_standout': on.to_hex()}


def standout_roles(theme: dict[str, str], mode: str, candidates=(), total_pixels: int = 0,
                   *, source: Color | None = None, scheme_type: str = '',
                   muted_chroma: float = MUTED_STANDOUT_CHROMA) -> dict[str, str]:
    primary = Color.from_hex(theme['primary'])
    selection = select_hue(primary, candidates, total_pixels, source=source, scheme_type=scheme_type)
    return synthesize(primary, Color.from_hex(theme['surface']), mode, selection,
                      muted_chroma=muted_chroma if scheme_type in ('monochrome', 'muted') else None)
