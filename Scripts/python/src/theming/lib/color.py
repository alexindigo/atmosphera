"""
Color representation and conversion utilities.

This module provides the Color class and functions for converting between
RGB and HSL color spaces.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING

# Type aliases
RGB = tuple[int, int, int]
HSL = tuple[float, float, float]

if TYPE_CHECKING:
    from .hct import Hct


@dataclass
class Color:
    """Represents a color with RGB values (0-255)."""
    r: int
    g: int
    b: int

    @classmethod
    def from_rgb(cls, rgb: RGB) -> 'Color':
        return cls(rgb[0], rgb[1], rgb[2])

    @classmethod
    def from_hex(cls, hex_str: str) -> 'Color':
        """Parse hex color string (#RRGGBB or RRGGBB)."""
        hex_str = hex_str.lstrip('#')
        return cls(
            int(hex_str[0:2], 16),
            int(hex_str[2:4], 16),
            int(hex_str[4:6], 16)
        )

    def to_rgb(self) -> RGB:
        return (self.r, self.g, self.b)

    def to_hex(self) -> str:
        """Convert to hex string (#RRGGBB)."""
        return f"#{self.r:02x}{self.g:02x}{self.b:02x}"

    def to_hsl(self) -> HSL:
        """Convert RGB to HSL."""
        return rgb_to_hsl(self.r, self.g, self.b)

    def to_hct(self) -> 'Hct':
        """Convert to HCT color space."""
        from .hct import Hct
        return Hct.from_rgb(self.r, self.g, self.b)

    @classmethod
    def from_hsl(cls, h: float, s: float, l: float) -> 'Color':
        """Create Color from HSL values."""
        r, g, b = hsl_to_rgb(h, s, l)
        return cls(r, g, b)

    @classmethod
    def from_hct(cls, hct: 'Hct') -> 'Color':
        """Create Color from HCT."""
        r, g, b = hct.to_rgb()
        return cls(r, g, b)


def rgb_to_hsl(r: int, g: int, b: int) -> HSL:
    """
    Convert RGB (0-255) to HSL (0-360, 0-1, 0-1).

    Args:
        r: Red component (0-255)
        g: Green component (0-255)
        b: Blue component (0-255)

    Returns:
        Tuple of (hue, saturation, lightness)
    """
    r_norm = r / 255.0
    g_norm = g / 255.0
    b_norm = b / 255.0

    max_c = max(r_norm, g_norm, b_norm)
    min_c = min(r_norm, g_norm, b_norm)
    delta = max_c - min_c

    # Lightness
    l = (max_c + min_c) / 2.0

    if delta == 0:
        h = 0.0
        s = 0.0
    else:
        # Saturation
        s = delta / (1 - abs(2 * l - 1)) if l != 0 and l != 1 else 0

        # Hue
        if max_c == r_norm:
            h = 60.0 * (((g_norm - b_norm) / delta) % 6)
        elif max_c == g_norm:
            h = 60.0 * (((b_norm - r_norm) / delta) + 2)
        else:
            h = 60.0 * (((r_norm - g_norm) / delta) + 4)

    return (h, s, l)


def hsl_to_rgb(h: float, s: float, l: float) -> RGB:
    """
    Convert HSL (0-360, 0-1, 0-1) to RGB (0-255).

    Args:
        h: Hue (0-360)
        s: Saturation (0-1)
        l: Lightness (0-1)

    Returns:
        Tuple of (r, g, b)
    """
    if s == 0:
        # Achromatic (gray)
        v = int(round(l * 255))
        return (v, v, v)

    def hue_to_rgb(p: float, q: float, t: float) -> float:
        if t < 0:
            t += 1
        if t > 1:
            t -= 1
        if t < 1/6:
            return p + (q - p) * 6 * t
        if t < 1/2:
            return q
        if t < 2/3:
            return p + (q - p) * (2/3 - t) * 6
        return p

    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q
    h_norm = h / 360.0

    r = hue_to_rgb(p, q, h_norm + 1/3)
    g = hue_to_rgb(p, q, h_norm)
    b = hue_to_rgb(p, q, h_norm - 1/3)

    return (
        int(round(r * 255)),
        int(round(g * 255)),
        int(round(b * 255))
    )


def adjust_lightness(color: Color, target_l: float) -> Color:
    """Adjust a color's lightness to a target value (0-1)."""
    h, s, _ = color.to_hsl()
    return Color.from_hsl(h, s, target_l)


def shift_hue(color: Color, degrees: float) -> Color:
    """Shift a color's hue by specified degrees."""
    h, s, l = color.to_hsl()
    new_h = (h + degrees) % 360
    return Color.from_hsl(new_h, s, l)


def hue_distance(h1: float, h2: float) -> float:
    """Calculate minimum angular distance between two hues (0-180)."""
    diff = abs(h1 - h2)
    return min(diff, 360 - diff)


def adjust_surface(color: Color, s_max: float, l_target: float) -> Color:
    """Derive a surface color from a base color with saturation limit and target lightness."""
    h, s, _ = color.to_hsl()
    return Color.from_hsl(h, min(s, s_max), l_target)


def saturate(color: Color, amount: float) -> Color:
    """Adjust saturation by amount (-1 to 1)."""
    h, s, l = color.to_hsl()
    new_s = max(0.0, min(1.0, s + amount))
    return Color.from_hsl(h, new_s, l)
