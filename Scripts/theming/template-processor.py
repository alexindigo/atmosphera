#!/usr/bin/env python3
"""
Template processor - Wallpaper-based color extraction and theme generation.

A CLI tool that extracts dominant colors from wallpaper images and generates:
- Material Design 3 color themes using HCT (Hue, Chroma, Tone) color space.
- Simpler accent based color theme using HSL (Hue, Saturation, Lightness) color space.

Usage:
    python3 template-processor.py IMAGE_PATH [OPTIONS]

Options:
    --material    Generate Material-style colors (default)
    --normal      Generate simpler accent-based palette
    --dark        Generate dark theme only
    --light       Generate light theme only
    --both        Generate both themes (default)
    --output FILE Write JSON to file (stdout if omitted)

Example:
    python3 template-processor.py ~/wallpaper.png --material --both
    python3 template-processor.py ~/wallpaper.jpg --dark -o theme.json

Author: Noctalia Team
License: MIT
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import sys
import zlib
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Any

# =============================================================================
# Type Definitions
# =============================================================================

RGB = tuple[int, int, int]
HSL = tuple[float, float, float]
ThemeMode = Literal["dark", "light"]

# =============================================================================
# CAM16 / HCT Color Space Implementation
# =============================================================================
# Based on Material Color Utilities (Google)
# HCT = Hue, Chroma, Tone - Material Design 3's perceptual color space

# sRGB to XYZ matrix (D65 illuminant)
SRGB_TO_XYZ = [
    [0.41233895, 0.35762064, 0.18051042],
    [0.2126, 0.7152, 0.0722],
    [0.01932141, 0.11916382, 0.95034478],
]

# XYZ to sRGB matrix
XYZ_TO_SRGB = [
    [3.2413774792388685, -1.5376652402851851, -0.49885366846268053],
    [-0.9691452513005321, 1.8758853451067872, 0.04156585616912061],
    [0.05562093689691305, -0.20395524564742123, 1.0571799111220335],
]

# CAM16 viewing conditions for standard sRGB
# Based on average surround, D65 white point, 200 cd/m² adapting luminance
class ViewingConditions:
    """CAM16 viewing conditions for sRGB display."""
    # White point (D65)
    WHITE_POINT_D65 = [95.047, 100.0, 108.883]

    # Precomputed values for standard conditions
    n = 0.18418651851244416
    aw = 29.980997194447333
    nbb = 1.0169191804458755
    ncb = 1.0169191804458755
    c = 0.69
    nc = 1.0
    fl = 0.3884814537800353
    fl_root = 0.7894826179304937
    z = 1.909169568483652

    # RGB to CAM16 adaptation matrix
    RGB_D = [1.0211931250282205, 0.9862992588498498, 0.9338046048498166]


def _linearize(channel: int) -> float:
    """Convert sRGB channel (0-255) to linear RGB (0-1)."""
    normalized = channel / 255.0
    if normalized <= 0.040449936:
        return normalized / 12.92
    return math.pow((normalized + 0.055) / 1.055, 2.4)


def _delinearize(linear: float) -> int:
    """Convert linear RGB (0-1) to sRGB channel (0-255)."""
    if linear <= 0.0031308:
        normalized = linear * 12.92
    else:
        normalized = 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055
    return max(0, min(255, round(normalized * 255)))


def _matrix_multiply(matrix: list[list[float]], vector: list[float]) -> list[float]:
    """Multiply 3x3 matrix by 3-element vector."""
    return [
        matrix[0][0] * vector[0] + matrix[0][1] * vector[1] + matrix[0][2] * vector[2],
        matrix[1][0] * vector[0] + matrix[1][1] * vector[1] + matrix[1][2] * vector[2],
        matrix[2][0] * vector[0] + matrix[2][1] * vector[1] + matrix[2][2] * vector[2],
    ]


def _signum(x: float) -> float:
    """Return sign of x: -1, 0, or 1."""
    if x < 0:
        return -1.0
    elif x > 0:
        return 1.0
    return 0.0


def _lerp(a: float, b: float, t: float) -> float:
    """Linear interpolation between a and b."""
    return a + (b - a) * t


def rgb_to_xyz(r: int, g: int, b: int) -> tuple[float, float, float]:
    """Convert sRGB to CIE XYZ."""
    linear_r = _linearize(r)
    linear_g = _linearize(g)
    linear_b = _linearize(b)
    xyz = _matrix_multiply(SRGB_TO_XYZ, [linear_r, linear_g, linear_b])
    return (xyz[0] * 100, xyz[1] * 100, xyz[2] * 100)


def xyz_to_rgb(x: float, y: float, z: float) -> tuple[int, int, int]:
    """Convert CIE XYZ to sRGB."""
    linear = _matrix_multiply(XYZ_TO_SRGB, [x / 100, y / 100, z / 100])
    return (_delinearize(linear[0]), _delinearize(linear[1]), _delinearize(linear[2]))


def y_to_lstar(y: float) -> float:
    """Convert XYZ Y component to L* (CIELAB lightness / HCT Tone)."""
    if y <= 0:
        return 0.0
    # Standard CIELAB formula
    # Y is in [0, 100], normalize to [0, 1]
    y_normalized = y / 100.0
    # Threshold: (6/29)^3 ≈ 0.008856
    if y_normalized <= 0.008856:
        # Linear region: L* = (29/3)^3 * Y/Yn = 903.3 * Y/100
        return 903.2962962962963 * y_normalized
    # Cube root region: L* = 116 * (Y/Yn)^(1/3) - 16
    return 116.0 * math.pow(y_normalized, 1.0 / 3.0) - 16.0


def lstar_to_y(lstar: float) -> float:
    """Convert L* (Tone) to XYZ Y component."""
    if lstar <= 0:
        return 0.0
    if lstar > 100:
        lstar = 100.0
    # Inverse of y_to_lstar
    # Threshold at L* = 8 (corresponds to y_normalized = 0.008856)
    if lstar <= 8.0:
        # Linear region: Y/Yn = L* / 903.3
        return lstar / 903.2962962962963 * 100.0
    # Cube root region: Y/Yn = ((L* + 16) / 116)^3
    fy = (lstar + 16.0) / 116.0
    return fy * fy * fy * 100.0


def argb_to_int(r: int, g: int, b: int) -> int:
    """Convert RGB to ARGB integer (alpha = 255)."""
    return (255 << 24) | (r << 16) | (g << 8) | b


def int_to_rgb(argb: int) -> tuple[int, int, int]:
    """Convert ARGB integer to RGB tuple."""
    return ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)


class Cam16:
    """CAM16 color appearance model representation."""

    def __init__(self, hue: float, chroma: float, j: float, q: float,
                 m: float, s: float, jstar: float, astar: float, bstar: float):
        self.hue = hue
        self.chroma = chroma
        self.j = j  # Lightness
        self.q = q  # Brightness
        self.m = m  # Colorfulness
        self.s = s  # Saturation
        self.jstar = jstar  # CAM16-UCS J*
        self.astar = astar  # CAM16-UCS a*
        self.bstar = bstar  # CAM16-UCS b*

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'Cam16':
        """Create CAM16 from sRGB values."""
        # Convert to XYZ
        x, y, z = rgb_to_xyz(r, g, b)

        # Convert XYZ to cone responses (Hunt-Pointer-Estevez)
        r_c = 0.401288 * x + 0.650173 * y - 0.051461 * z
        g_c = -0.250268 * x + 1.204414 * y + 0.045854 * z
        b_c = -0.002079 * x + 0.048952 * y + 0.953127 * z

        # Chromatic adaptation
        r_d = ViewingConditions.RGB_D[0] * r_c
        g_d = ViewingConditions.RGB_D[1] * g_c
        b_d = ViewingConditions.RGB_D[2] * b_c

        # Post-adaptation compression
        r_af = math.pow(ViewingConditions.fl * abs(r_d) / 100.0, 0.42)
        g_af = math.pow(ViewingConditions.fl * abs(g_d) / 100.0, 0.42)
        b_af = math.pow(ViewingConditions.fl * abs(b_d) / 100.0, 0.42)

        r_a = _signum(r_d) * 400.0 * r_af / (r_af + 27.13)
        g_a = _signum(g_d) * 400.0 * g_af / (g_af + 27.13)
        b_a = _signum(b_d) * 400.0 * b_af / (b_af + 27.13)

        # Redness-greenness, yellowness-blueness
        a = (11.0 * r_a + -12.0 * g_a + b_a) / 11.0
        b = (r_a + g_a - 2.0 * b_a) / 9.0

        # Hue
        hue_radians = math.atan2(b, a)
        hue = math.degrees(hue_radians)
        if hue < 0:
            hue += 360.0

        # Achromatic response
        # u is used in the chroma calculation denominator
        u = (20.0 * r_a + 20.0 * g_a + 21.0 * b_a) / 20.0
        p2 = (40.0 * r_a + 20.0 * g_a + b_a) / 20.0
        ac = p2 * ViewingConditions.nbb

        # Lightness
        j = 100.0 * math.pow(ac / ViewingConditions.aw, ViewingConditions.c * ViewingConditions.z)

        # Brightness
        q = (4.0 / ViewingConditions.c) * math.sqrt(j / 100.0) * (ViewingConditions.aw + 4.0) * ViewingConditions.fl_root

        # Eccentricity and hue composition
        hue_prime = hue + 360.0 if hue < 20.14 else hue
        e_hue = 0.25 * (math.cos(math.radians(hue_prime) + 2.0) + 3.8)

        # Chroma
        t = 50000.0 / 13.0 * ViewingConditions.nc * ViewingConditions.ncb * e_hue * math.sqrt(a * a + b * b) / (u + 0.305)
        alpha = math.pow(t, 0.9) * math.pow(1.64 - math.pow(0.29, ViewingConditions.n), 0.73)
        chroma = alpha * math.sqrt(j / 100.0)

        # Colorfulness
        m = chroma * ViewingConditions.fl_root

        # Saturation
        s = 50.0 * math.sqrt((ViewingConditions.c * alpha) / (ViewingConditions.aw + 4.0))

        # CAM16-UCS coordinates
        jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
        mstar = 1.0 / 0.0228 * math.log(1.0 + 0.0228 * m) if m > 0 else 0
        astar = mstar * math.cos(hue_radians)
        bstar = mstar * math.sin(hue_radians)

        return cls(hue, chroma, j, q, m, s, jstar, astar, bstar)

    @classmethod
    def from_jch(cls, j: float, chroma: float, hue: float) -> 'Cam16':
        """Create CAM16 from J (lightness), chroma, and hue."""
        q = (4.0 / ViewingConditions.c) * math.sqrt(j / 100.0) * (ViewingConditions.aw + 4.0) * ViewingConditions.fl_root
        m = chroma * ViewingConditions.fl_root
        alpha = chroma / math.sqrt(j / 100.0) if j > 0 else 0
        s = 50.0 * math.sqrt((ViewingConditions.c * alpha) / (ViewingConditions.aw + 4.0))

        hue_radians = math.radians(hue)
        jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
        mstar = 1.0 / 0.0228 * math.log(1.0 + 0.0228 * m) if m > 0 else 0
        astar = mstar * math.cos(hue_radians)
        bstar = mstar * math.sin(hue_radians)

        return cls(hue, chroma, j, q, m, s, jstar, astar, bstar)

    def to_rgb(self) -> tuple[int, int, int]:
        """Convert CAM16 back to sRGB."""
        if self.chroma == 0 or self.j == 0:
            # Achromatic
            y = lstar_to_y(self.j)
            return xyz_to_rgb(y, y, y)

        hue_radians = math.radians(self.hue)

        # Reverse the compression
        alpha = self.chroma / math.sqrt(self.j / 100.0) if self.j > 0 else 0
        t = math.pow(alpha / math.pow(1.64 - math.pow(0.29, ViewingConditions.n), 0.73), 1.0 / 0.9)

        hue_prime = self.hue + 360.0 if self.hue < 20.14 else self.hue
        e_hue = 0.25 * (math.cos(math.radians(hue_prime) + 2.0) + 3.8)

        ac = ViewingConditions.aw * math.pow(self.j / 100.0, 1.0 / (ViewingConditions.c * ViewingConditions.z))
        p1 = 50000.0 / 13.0 * ViewingConditions.nc * ViewingConditions.ncb * e_hue
        p2 = ac / ViewingConditions.nbb

        gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * math.cos(hue_radians) + 108.0 * t * math.sin(hue_radians))

        a = gamma * math.cos(hue_radians)
        b = gamma * math.sin(hue_radians)

        r_a = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
        g_a = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
        b_a = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0

        def reverse_adapt(adapted: float) -> float:
            abs_adapted = abs(adapted)
            base = max(0, 27.13 * abs_adapted / (400.0 - abs_adapted))
            return _signum(adapted) * 100.0 / ViewingConditions.fl * math.pow(base, 1.0 / 0.42)

        r_c = reverse_adapt(r_a) / ViewingConditions.RGB_D[0]
        g_c = reverse_adapt(g_a) / ViewingConditions.RGB_D[1]
        b_c = reverse_adapt(b_a) / ViewingConditions.RGB_D[2]

        # Convert from cone responses to XYZ
        x = 1.8620678 * r_c - 1.0112547 * g_c + 0.1491867 * b_c
        y = 0.3875265 * r_c + 0.6214474 * g_c - 0.0089739 * b_c
        z = -0.0158415 * r_c - 0.0344156 * g_c + 1.0502571 * b_c

        return xyz_to_rgb(x, y, z)


class Hct:
    """
    HCT (Hue, Chroma, Tone) color representation.

    Material Design 3's perceptual color space combining:
    - Hue: CAM16 hue (0-360)
    - Chroma: CAM16 chroma (colorfulness, typically 0-120+)
    - Tone: CIELAB L* lightness (0-100)
    """

    def __init__(self, hue: float, chroma: float, tone: float):
        self._hue = hue % 360.0
        self._chroma = max(0.0, chroma)
        self._tone = max(0.0, min(100.0, tone))
        self._argb: int | None = None

    @property
    def hue(self) -> float:
        return self._hue

    @property
    def chroma(self) -> float:
        return self._chroma

    @property
    def tone(self) -> float:
        return self._tone

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'Hct':
        """Create HCT from sRGB values."""
        cam = Cam16.from_rgb(r, g, b)
        _, y, _ = rgb_to_xyz(r, g, b)
        tone = y_to_lstar(y)
        return cls(cam.hue, cam.chroma, tone)

    @classmethod
    def from_argb(cls, argb: int) -> 'Hct':
        """Create HCT from ARGB integer."""
        r, g, b = int_to_rgb(argb)
        return cls.from_rgb(r, g, b)

    def to_rgb(self) -> tuple[int, int, int]:
        """Convert HCT to sRGB, solving for the color."""
        return self._solve_to_rgb(self._hue, self._chroma, self._tone)

    def to_argb(self) -> int:
        """Convert HCT to ARGB integer."""
        if self._argb is None:
            r, g, b = self.to_rgb()
            self._argb = argb_to_int(r, g, b)
        return self._argb

    def to_hex(self) -> str:
        """Convert HCT to hex string."""
        r, g, b = self.to_rgb()
        return f"#{r:02x}{g:02x}{b:02x}"

    @staticmethod
    def _solve_to_rgb(hue: float, chroma: float, tone: float) -> tuple[int, int, int]:
        """
        Solve for RGB given HCT values.

        This finds an sRGB color with the target tone (L*) and hue,
        with chroma as close as possible to the target (reducing if needed
        to stay within gamut).
        """
        # Handle edge cases
        if tone <= 0.0:
            return (0, 0, 0)
        if tone >= 100.0:
            return (255, 255, 255)
        if chroma < 0.5:
            # Nearly achromatic
            y = lstar_to_y(tone)
            return xyz_to_rgb(y, y, y)

        # Binary search on chroma to find a valid sRGB color
        # that matches the target tone and hue
        low_chroma = 0.0
        high_chroma = chroma
        best_rgb = None
        best_chroma = 0.0

        for iteration in range(20):
            mid_chroma = (low_chroma + high_chroma) / 2.0

            # Try to create a color with this chroma
            rgb = Hct._find_rgb_for_hct(hue, mid_chroma, tone)

            if rgb is not None:
                r, g, b = rgb
                if 0 <= r <= 255 and 0 <= g <= 255 and 0 <= b <= 255:
                    # Valid color found, try higher chroma
                    best_rgb = rgb
                    best_chroma = mid_chroma
                    low_chroma = mid_chroma
                else:
                    # Out of gamut, reduce chroma
                    high_chroma = mid_chroma
            else:
                high_chroma = mid_chroma

        if best_rgb is not None:
            return best_rgb

        # Fallback: return gray at the target tone
        y = lstar_to_y(tone)
        return xyz_to_rgb(y, y, y)

    @staticmethod
    def _find_rgb_for_hct(hue: float, chroma: float, tone: float) -> tuple[int, int, int] | None:
        """
        Find an RGB color for the given HCT values by working in CAM16 space.
        """
        # The relationship between L* (tone) and CAM16 J is approximately:
        # J ≈ L* for standard viewing conditions
        # But we need to adjust for the nonlinearity

        j = tone  # Initial approximation

        # Iterate to find the correct J that gives us the target tone
        for _ in range(5):
            cam = Cam16.from_jch(j, chroma, hue)
            rgb = cam.to_rgb()
            r, g, b = rgb

            # Clamp to get valid values for testing
            r_clamped = max(0, min(255, r))
            g_clamped = max(0, min(255, g))
            b_clamped = max(0, min(255, b))

            # Check if clamping changed the values (out of gamut)
            if r != r_clamped or g != g_clamped or b != b_clamped:
                return None

            # Get actual tone
            _, y, _ = rgb_to_xyz(r, g, b)
            actual_tone = y_to_lstar(y)

            # Adjust J to get closer to target tone
            tone_diff = tone - actual_tone
            if abs(tone_diff) < 0.5:
                return (r, g, b)

            # Adjust J proportionally
            j += tone_diff * 0.5

            if j <= 0 or j > 100:
                return None

        # Return the best we found
        cam = Cam16.from_jch(j, chroma, hue)
        rgb = cam.to_rgb()
        r, g, b = rgb

        if 0 <= r <= 255 and 0 <= g <= 255 and 0 <= b <= 255:
            return (r, g, b)

        return None

    def set_hue(self, hue: float) -> 'Hct':
        """Return new HCT with different hue."""
        return Hct(hue, self._chroma, self._tone)

    def set_chroma(self, chroma: float) -> 'Hct':
        """Return new HCT with different chroma."""
        return Hct(self._hue, chroma, self._tone)

    def set_tone(self, tone: float) -> 'Hct':
        """Return new HCT with different tone."""
        return Hct(self._hue, self._chroma, tone)


class TonalPalette:
    """
    A palette of tones for a single hue and chroma.

    Material Design 3 uses specific tone values for different UI elements.
    """

    def __init__(self, hue: float, chroma: float):
        self.hue = hue
        self.chroma = chroma
        self._cache: dict[int, int] = {}

    @classmethod
    def from_hct(cls, hct: Hct) -> 'TonalPalette':
        """Create TonalPalette from HCT color."""
        return cls(hct.hue, hct.chroma)

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'TonalPalette':
        """Create TonalPalette from RGB color."""
        hct = Hct.from_rgb(r, g, b)
        return cls(hct.hue, hct.chroma)

    def tone(self, t: int) -> int:
        """Get ARGB color at the specified tone (0-100)."""
        if t not in self._cache:
            hct = Hct(self.hue, self.chroma, float(t))
            self._cache[t] = hct.to_argb()
        return self._cache[t]

    def get_rgb(self, t: int) -> tuple[int, int, int]:
        """Get RGB color at the specified tone."""
        return int_to_rgb(self.tone(t))

    def get_hex(self, t: int) -> str:
        """Get hex color at the specified tone."""
        r, g, b = self.get_rgb(t)
        return f"#{r:02x}{g:02x}{b:02x}"


# =============================================================================
# Material Design 3 Scheme Generation
# =============================================================================

class MaterialScheme:
    """
    Material Design 3 color scheme generator.

    Implements the official Material Design 3 color system using HCT color space.
    Based on SchemeContent variant which preserves the source color's character.
    """

    # Tone values for Material Design 3 (dark theme)
    DARK_TONES = {
        'primary': 80,
        'on_primary': 20,
        'primary_container': 30,
        'on_primary_container': 90,
        'secondary': 80,
        'on_secondary': 20,
        'secondary_container': 30,
        'on_secondary_container': 90,
        'tertiary': 80,
        'on_tertiary': 20,
        'tertiary_container': 30,
        'on_tertiary_container': 90,
        'error': 80,
        'on_error': 20,
        'error_container': 30,
        'on_error_container': 90,
        'surface': 6,
        'on_surface': 90,
        'surface_variant': 30,
        'on_surface_variant': 80,
        'surface_container_lowest': 4,
        'surface_container_low': 10,
        'surface_container': 12,
        'surface_container_high': 17,
        'surface_container_highest': 22,
        'outline': 60,
        'outline_variant': 30,
        'shadow': 0,
        'scrim': 0,
        'inverse_surface': 90,
        'inverse_on_surface': 20,
        'inverse_primary': 40,
    }

    # Tone values for Material Design 3 (light theme)
    LIGHT_TONES = {
        'primary': 40,
        'on_primary': 100,
        'primary_container': 90,
        'on_primary_container': 10,
        'secondary': 40,
        'on_secondary': 100,
        'secondary_container': 90,
        'on_secondary_container': 10,
        'tertiary': 40,
        'on_tertiary': 100,
        'tertiary_container': 90,
        'on_tertiary_container': 10,
        'error': 40,
        'on_error': 100,
        'error_container': 90,
        'on_error_container': 10,
        'surface': 98,
        'on_surface': 10,
        'surface_variant': 90,
        'on_surface_variant': 30,
        'surface_container_lowest': 100,
        'surface_container_low': 96,
        'surface_container': 94,
        'surface_container_high': 92,
        'surface_container_highest': 90,
        'outline': 50,
        'outline_variant': 80,
        'shadow': 0,
        'scrim': 0,
        'inverse_surface': 20,
        'inverse_on_surface': 95,
        'inverse_primary': 80,
    }

    def __init__(self, source_color: Hct):
        """
        Create a Material Design 3 scheme from a source color.

        Args:
            source_color: The source color in HCT space
        """
        self.source = source_color

        # Create tonal palettes for each color role
        # SchemeContent-style: preserves source color characteristics

        # Primary: source color's hue and chroma (unchanged)
        self.primary_palette = TonalPalette(source_color.hue, source_color.chroma)

        # Secondary: same hue, reduced chroma
        # Formula: max(chroma - 32, chroma * 0.5)
        secondary_chroma = max(source_color.chroma - 32.0, source_color.chroma * 0.5)
        self.secondary_palette = TonalPalette(source_color.hue, secondary_chroma)

        # Tertiary: analogous color (simplified as 60° rotation)
        # In full implementation this uses TemperatureCache for analogous colors
        tertiary_hue = (source_color.hue + 60.0) % 360.0
        tertiary_chroma = max(source_color.chroma - 32.0, source_color.chroma * 0.5)
        self.tertiary_palette = TonalPalette(tertiary_hue, tertiary_chroma)

        # Error: red hue with high chroma
        self.error_palette = TonalPalette(25.0, 84.0)  # Material red

        # Neutral: source hue, low chroma (chroma / 8)
        neutral_chroma = source_color.chroma / 8.0
        self.neutral_palette = TonalPalette(source_color.hue, neutral_chroma)

        # Neutral variant: source hue, slightly more chroma than neutral
        neutral_variant_chroma = (source_color.chroma / 8.0) + 4.0
        self.neutral_variant_palette = TonalPalette(source_color.hue, neutral_variant_chroma)

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'MaterialScheme':
        """Create scheme from RGB color."""
        return cls(Hct.from_rgb(r, g, b))

    @classmethod
    def from_hex(cls, hex_color: str) -> 'MaterialScheme':
        """Create scheme from hex color string."""
        hex_color = hex_color.lstrip('#')
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        return cls.from_rgb(r, g, b)

    def get_dark_scheme(self) -> dict[str, str]:
        """Generate dark theme color dictionary."""
        return self._generate_scheme(is_dark=True)

    def get_light_scheme(self) -> dict[str, str]:
        """Generate light theme color dictionary."""
        return self._generate_scheme(is_dark=False)

    def _generate_scheme(self, is_dark: bool) -> dict[str, str]:
        """Generate scheme with appropriate tone values."""
        tones = self.DARK_TONES if is_dark else self.LIGHT_TONES

        scheme = {
            # Primary colors
            'mPrimary': self.primary_palette.get_hex(tones['primary']),
            'mOnPrimary': self.primary_palette.get_hex(tones['on_primary']),
            'mPrimaryContainer': self.primary_palette.get_hex(tones['primary_container']),
            'mOnPrimaryContainer': self.primary_palette.get_hex(tones['on_primary_container']),

            # Secondary colors
            'mSecondary': self.secondary_palette.get_hex(tones['secondary']),
            'mOnSecondary': self.secondary_palette.get_hex(tones['on_secondary']),
            'mSecondaryContainer': self.secondary_palette.get_hex(tones['secondary_container']),
            'mOnSecondaryContainer': self.secondary_palette.get_hex(tones['on_secondary_container']),

            # Tertiary colors
            'mTertiary': self.tertiary_palette.get_hex(tones['tertiary']),
            'mOnTertiary': self.tertiary_palette.get_hex(tones['on_tertiary']),
            'mTertiaryContainer': self.tertiary_palette.get_hex(tones['tertiary_container']),
            'mOnTertiaryContainer': self.tertiary_palette.get_hex(tones['on_tertiary_container']),

            # Error colors
            'mError': self.error_palette.get_hex(tones['error']),
            'mOnError': self.error_palette.get_hex(tones['on_error']),
            'mErrorContainer': self.error_palette.get_hex(tones['error_container']),
            'mOnErrorContainer': self.error_palette.get_hex(tones['on_error_container']),

            # Surface colors
            'mSurface': self.neutral_palette.get_hex(tones['surface']),
            'mOnSurface': self.neutral_palette.get_hex(tones['on_surface']),
            'mSurfaceVariant': self.neutral_variant_palette.get_hex(tones['surface_variant']),
            'mOnSurfaceVariant': self.neutral_variant_palette.get_hex(tones['on_surface_variant']),

            # Surface containers
            'mSurfaceContainerLowest': self.neutral_palette.get_hex(tones['surface_container_lowest']),
            'mSurfaceContainerLow': self.neutral_palette.get_hex(tones['surface_container_low']),
            'mSurfaceContainer': self.neutral_palette.get_hex(tones['surface_container']),
            'mSurfaceContainerHigh': self.neutral_palette.get_hex(tones['surface_container_high']),
            'mSurfaceContainerHighest': self.neutral_palette.get_hex(tones['surface_container_highest']),

            # Outline and other
            'mOutline': self.neutral_variant_palette.get_hex(tones['outline']),
            'mOutlineVariant': self.neutral_variant_palette.get_hex(tones['outline_variant']),
            'mShadow': self.neutral_palette.get_hex(tones['shadow']),
            'mScrim': self.neutral_palette.get_hex(tones['scrim']),

            # Inverse colors
            'mInverseSurface': self.neutral_palette.get_hex(tones['inverse_surface']),
            'mInverseOnSurface': self.neutral_palette.get_hex(tones['inverse_on_surface']),
            'mInversePrimary': self.primary_palette.get_hex(tones['inverse_primary']),

            # Background (alias for surface)
            'mBackground': self.neutral_palette.get_hex(tones['surface']),
            'mOnBackground': self.neutral_palette.get_hex(tones['on_surface']),
        }

        return scheme


def harmonize_color(design_color: Hct, source_color: Hct, amount: float = 0.5) -> Hct:
    """
    Shift a design color's hue towards a source color's hue.

    Used to make custom colors feel more cohesive with the theme.

    Args:
        design_color: The color to adjust
        source_color: The reference color to harmonize towards
        amount: How much to shift (0-1, default 0.5)

    Returns:
        Harmonized HCT color
    """
    diff = _hue_difference(source_color.hue, design_color.hue)
    rotation = min(diff * amount, 15.0)  # Max 15° rotation
    if _shorter_rotation(source_color.hue, design_color.hue) < 0:
        rotation = -rotation
    new_hue = (design_color.hue + rotation) % 360.0
    return Hct(new_hue, design_color.chroma, design_color.tone)


def _hue_difference(hue1: float, hue2: float) -> float:
    """Calculate the absolute difference between two hues."""
    diff = abs(hue1 - hue2)
    return min(diff, 360.0 - diff)


def _shorter_rotation(from_hue: float, to_hue: float) -> float:
    """Calculate the shorter rotation direction between hues."""
    diff = to_hue - from_hue
    if diff > 180.0:
        return diff - 360.0
    elif diff < -180.0:
        return diff + 360.0
    return diff


# =============================================================================
# Legacy Color Class (for compatibility)
# =============================================================================

@dataclass
class Color:
    """Represents a color with RGB values (0-255)."""
    r: int
    g: int
    b: int

    @classmethod
    def from_rgb(cls, rgb: RGB) -> Color:
        return cls(rgb[0], rgb[1], rgb[2])

    @classmethod
    def from_hex(cls, hex_str: str) -> Color:
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

    def to_hct(self) -> Hct:
        """Convert to HCT color space."""
        return Hct.from_rgb(self.r, self.g, self.b)

    @classmethod
    def from_hsl(cls, h: float, s: float, l: float) -> Color:
        """Create Color from HSL values."""
        r, g, b = hsl_to_rgb(h, s, l)
        return cls(r, g, b)

    @classmethod
    def from_hct(cls, hct: Hct) -> Color:
        """Create Color from HCT."""
        r, g, b = hct.to_rgb()
        return cls(r, g, b)


# =============================================================================
# Color Utilities (RGB/HSL Conversion)
# =============================================================================

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


def _adjust_surface(color: Color, s_max: float, l_target: float) -> Color:
    """Derive a surface color from a base color with saturation limit and target lightness."""
    h, s, _ = color.to_hsl()
    return Color.from_hsl(h, min(s, s_max), l_target)



def saturate(color: Color, amount: float) -> Color:
    """Adjust saturation by amount (-1 to 1)."""
    h, s, l = color.to_hsl()
    new_s = max(0.0, min(1.0, s + amount))
    return Color.from_hsl(h, new_s, l)


# =============================================================================
# Contrast Utilities (WCAG Luminance/Contrast)
# =============================================================================

def relative_luminance(r: int, g: int, b: int) -> float:
    """
    Calculate relative luminance per WCAG 2.1.
    
    The formula converts sRGB to linear RGB, then applies the luminance formula:
    L = 0.2126 * R + 0.7152 * G + 0.0722 * B
    
    Args:
        r, g, b: RGB components (0-255)
    
    Returns:
        Relative luminance (0-1)
    """
    def linearize(c: int) -> float:
        c_norm = c / 255.0
        if c_norm <= 0.03928:
            return c_norm / 12.92
        return ((c_norm + 0.055) / 1.055) ** 2.4
    
    r_lin = linearize(r)
    g_lin = linearize(g)
    b_lin = linearize(b)
    
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin


def contrast_ratio(color1: Color, color2: Color) -> float:
    """
    Calculate WCAG contrast ratio between two colors.
    
    Returns a value between 1:1 (identical) and 21:1 (black/white).
    """
    l1 = relative_luminance(color1.r, color1.g, color1.b)
    l2 = relative_luminance(color2.r, color2.g, color2.b)
    
    lighter = max(l1, l2)
    darker = min(l1, l2)
    
    return (lighter + 0.05) / (darker + 0.05)


def is_dark(color: Color) -> bool:
    """Determine if a color is perceptually dark."""
    return relative_luminance(color.r, color.g, color.b) < 0.179


def ensure_contrast(
    foreground: Color,
    background: Color,
    min_ratio: float = 4.5,
    prefer_light: bool | None = None
) -> Color:
    """
    Adjust foreground color to meet minimum contrast ratio against background.
    
    Args:
        foreground: The color to adjust
        background: The background color (not modified)
        min_ratio: Minimum contrast ratio (default 4.5 for WCAG AA)
        prefer_light: If True, prefer lightening; if False, prefer darkening;
                     if None, auto-detect based on background
    
    Returns:
        Adjusted foreground color meeting contrast requirements
    """
    current_ratio = contrast_ratio(foreground, background)
    if current_ratio >= min_ratio:
        return foreground
    
    h, s, l = foreground.to_hsl()
    bg_dark = is_dark(background)
    
    # Determine direction to adjust
    if prefer_light is None:
        prefer_light = bg_dark
    
    # Binary search for the right lightness
    if prefer_light:
        low, high = l, 1.0
    else:
        low, high = 0.0, l
    
    best_color = foreground
    for _ in range(20):  # Max iterations
        mid = (low + high) / 2
        test_color = Color.from_hsl(h, s, mid)
        ratio = contrast_ratio(test_color, background)
        
        if ratio >= min_ratio:
            best_color = test_color
            if prefer_light:
                high = mid
            else:
                low = mid
        else:
            if prefer_light:
                low = mid
            else:
                high = mid
    
    return best_color

# Alias for consistent naming
_ensure_contrast = ensure_contrast



def get_contrasting_color(background: Color, min_ratio: float = 4.5) -> Color:
    """Get a contrasting foreground color (black or white variant)."""
    if is_dark(background):
        # Light foreground for dark background
        fg = Color(243, 237, 247)  # Off-white
    else:
        # Dark foreground for light background
        fg = Color(14, 14, 67)  # Dark blue-black
    
    return ensure_contrast(fg, background, min_ratio)


# =============================================================================
# Image Reader (PNG/JPEG Parsing)
# =============================================================================

class ImageReadError(Exception):
    """Raised when image cannot be read or parsed."""
    pass


def read_png(path: Path) -> list[RGB]:
    """
    Parse a PNG file and extract RGB pixels.
    
    Supports 8-bit RGB and RGBA color types (most common for wallpapers).
    Uses zlib for IDAT decompression and handles PNG filters.
    """
    with open(path, 'rb') as f:
        data = f.read()
    
    # Verify PNG signature
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ImageReadError("Invalid PNG signature")
    
    pos = 8
    width = 0
    height = 0
    bit_depth = 0
    color_type = 0
    idat_chunks: list[bytes] = []
    
    while pos < len(data):
        # Read chunk length and type
        chunk_len = struct.unpack('>I', data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+chunk_len]
        pos += 12 + chunk_len  # length + type + data + crc
        
        if chunk_type == b'IHDR':
            width = struct.unpack('>I', chunk_data[0:4])[0]
            height = struct.unpack('>I', chunk_data[4:8])[0]
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
            
            if bit_depth != 8:
                raise ImageReadError(f"Unsupported bit depth: {bit_depth}")
            if color_type not in (2, 6):  # RGB or RGBA
                raise ImageReadError(f"Unsupported color type: {color_type}")
        
        elif chunk_type == b'IDAT':
            idat_chunks.append(chunk_data)
        
        elif chunk_type == b'IEND':
            break
    
    if not idat_chunks or width == 0:
        raise ImageReadError("Missing image data")
    
    # Decompress all IDAT chunks
    compressed = b''.join(idat_chunks)
    raw_data = zlib.decompress(compressed)
    
    # Calculate bytes per pixel and row
    bpp = 3 if color_type == 2 else 4  # RGB or RGBA
    stride = width * bpp + 1  # +1 for filter byte
    
    pixels: list[RGB] = []
    prev_row: list[int] = [0] * (width * bpp)
    
    for y in range(height):
        row_start = y * stride
        filter_type = raw_data[row_start]
        row_data = list(raw_data[row_start + 1:row_start + stride])
        
        # Apply PNG filter reconstruction
        unfiltered = _png_unfilter(row_data, prev_row, bpp, filter_type)
        prev_row = unfiltered
        
        # Extract RGB values (skip alpha if present)
        for x in range(width):
            idx = x * bpp
            r, g, b = unfiltered[idx], unfiltered[idx+1], unfiltered[idx+2]
            pixels.append((r, g, b))
    
    return pixels


def _png_unfilter(
    row: list[int],
    prev_row: list[int],
    bpp: int,
    filter_type: int
) -> list[int]:
    """Apply PNG filter reconstruction."""
    result = [0] * len(row)
    
    for i in range(len(row)):
        x = row[i]
        a = result[i - bpp] if i >= bpp else 0
        b = prev_row[i]
        c = prev_row[i - bpp] if i >= bpp else 0
        
        if filter_type == 0:  # None
            result[i] = x
        elif filter_type == 1:  # Sub
            result[i] = (x + a) & 0xFF
        elif filter_type == 2:  # Up
            result[i] = (x + b) & 0xFF
        elif filter_type == 3:  # Average
            result[i] = (x + (a + b) // 2) & 0xFF
        elif filter_type == 4:  # Paeth
            result[i] = (x + _paeth_predictor(a, b, c)) & 0xFF
        else:
            raise ImageReadError(f"Unknown PNG filter type: {filter_type}")
    
    return result


def _paeth_predictor(a: int, b: int, c: int) -> int:
    """Paeth predictor for PNG filter reconstruction."""
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    
    if pa <= pb and pa <= pc:
        return a
    elif pb <= pc:
        return b
    return c


def read_jpeg(path: Path) -> list[RGB]:
    """
    Parse a JPEG file and extract RGB pixels.
    
    Supports baseline (SOF0), extended (SOF1), and progressive (SOF2) JPEG.
    This is a simplified decoder that extracts dimensions then samples colors.
    """
    with open(path, 'rb') as f:
        data = f.read()
    
    # Verify JPEG signature (SOI marker)
    if data[:2] != b'\xff\xd8':
        raise ImageReadError("Invalid JPEG signature")
    
    pos = 2
    width = 0
    height = 0
    
    # SOF markers that contain image dimensions
    # SOF0=Baseline, SOF1=Extended, SOF2=Progressive, SOF3=Lossless
    # SOF5-7=Differential variants, SOF9-11=Arithmetic coding variants
    sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                   0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    
    # Standalone markers (no length field)
    standalone_markers = {0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7,  # RST0-7
                          0xD8,  # SOI
                          0xD9,  # EOI
                          0x01}  # TEM
    
    while pos < len(data) - 1:
        # Find next marker
        if data[pos] != 0xFF:
            pos += 1
            continue
        
        # Skip padding 0xFF bytes
        while pos < len(data) and data[pos] == 0xFF:
            pos += 1
        
        if pos >= len(data):
            break
        
        marker = data[pos]
        pos += 1
        
        # Check for SOF marker (contains dimensions)
        if marker in sof_markers:
            if pos + 7 <= len(data):
                # Skip segment length (2 bytes), precision (1 byte)
                height = struct.unpack('>H', data[pos+3:pos+5])[0]
                width = struct.unpack('>H', data[pos+5:pos+7])[0]
                break
        
        # End of image
        if marker == 0xD9:
            break
        
        # Skip segment data for markers with length field
        if marker not in standalone_markers and marker != 0x00:
            if pos + 2 <= len(data):
                seg_len = struct.unpack('>H', data[pos:pos+2])[0]
                pos += seg_len
    
    if width == 0 or height == 0:
        raise ImageReadError("Could not parse JPEG dimensions")
    
    # Since full JPEG decoding is extremely complex without external libraries,
    # we fall back to sampling the raw data for color approximation.
    return _sample_jpeg_colors(data, width, height)


def _read_image_imagemagick(path: Path) -> list[RGB]:
    """
    Read image using ImageMagick's convert command.
    
    Converts image to PPM format (trivial to parse) and extracts RGB pixels.
    This method works accurately for any image format ImageMagick supports.
    """
    import subprocess
    
    # Use magick or convert command
    # -depth 8: 8 bits per channel
    # -resize: downsample for performance (we don't need full resolution for color extraction)
    # ppm: output as PPM format (easy to parse)
    
    # Downsample to max 200x200 for performance
    resize_spec = "200x200>"
    
    try:
        # Try 'magick convert' first (ImageMagick 7+), fallback to 'convert' (ImageMagick 6)
        try:
            result = subprocess.run(
                ['magick', 'convert', str(path), '-resize', resize_spec, '-depth', '8', 'ppm:-'],
                capture_output=True,
                check=True
            )
        except FileNotFoundError:
            result = subprocess.run(
                ['convert', str(path), '-resize', resize_spec, '-depth', '8', 'ppm:-'],
                capture_output=True,
                check=True
            )
    except subprocess.CalledProcessError as e:
        raise ImageReadError(f"ImageMagick failed: {e.stderr.decode()}")
    except FileNotFoundError:
        raise ImageReadError("ImageMagick not found. Please install imagemagick.")
    
    ppm_data = result.stdout
    return _parse_ppm(ppm_data)


def _parse_ppm(data: bytes) -> list[RGB]:
    """
    Parse PPM (Portable Pixmap) binary format.
    
    PPM P6 format:
    P6
    width height
    maxval
    <binary RGB data>
    """
    pos = 0
    tokens: list[str] = []
    
    # Read header tokens (need 4: P6, width, height, maxval)
    while len(tokens) < 4 and pos < len(data):
        # Skip whitespace
        while pos < len(data) and data[pos:pos+1] in (b' ', b'\t', b'\n', b'\r'):
            pos += 1
        
        # Skip comments
        if pos < len(data) and data[pos:pos+1] == b'#':
            while pos < len(data) and data[pos:pos+1] != b'\n':
                pos += 1
            continue
        
        # Read token
        token_start = pos
        while pos < len(data) and data[pos:pos+1] not in (b' ', b'\t', b'\n', b'\r', b'#'):
            pos += 1
        
        if pos > token_start:
            tokens.append(data[token_start:pos].decode('ascii'))
    
    if len(tokens) < 4 or tokens[0] != 'P6':
        raise ImageReadError(f"Invalid PPM format: {tokens}")
    
    width = int(tokens[1])
    height = int(tokens[2])
    maxval = int(tokens[3])
    
    # Skip exactly one whitespace character after maxval (per PPM spec)
    if pos < len(data) and data[pos:pos+1] in (b' ', b'\t', b'\n', b'\r'):
        pos += 1
    
    pixel_data = data[pos:]
    
    # Parse RGB triplets
    pixels: list[RGB] = []
    scale = 255.0 / maxval if maxval != 255 else 1.0
    
    for i in range(0, min(len(pixel_data), width * height * 3), 3):
        if i + 2 < len(pixel_data):
            r = int(pixel_data[i] * scale)
            g = int(pixel_data[i + 1] * scale)
            b = int(pixel_data[i + 2] * scale)
            pixels.append((r, g, b))
    
    if not pixels:
        raise ImageReadError("No pixels extracted from PPM data")
    
    return pixels


def read_image(path: Path) -> list[RGB]:
    """
    Read an image file and return its pixels as RGB tuples.
    
    Uses ImageMagick for accurate color extraction from any format.
    Falls back to native PNG parsing if ImageMagick is unavailable.
    """
    suffix = path.suffix.lower()
    
    # Try ImageMagick first (works for any format)
    try:
        return _read_image_imagemagick(path)
    except ImageReadError:
        # Fall back to native parsing for PNG
        if suffix == '.png':
            return read_png(path)
        raise


# =============================================================================
# Palette Extraction (K-means Clustering)
# =============================================================================

def downsample_pixels(pixels: list[RGB], factor: int = 4) -> list[RGB]:
    """
    Downsample pixels for faster processing.
    
    Takes every Nth pixel to reduce dataset size while maintaining
    color distribution characteristics.
    """
    if factor <= 1:
        return pixels
    
    # Calculate step based on factor squared (for 2D image)
    step = factor * factor
    return pixels[::step]


def color_distance_hsl(c1: HSL, c2: HSL) -> float:
    """
    Calculate perceptual distance between two colors in HSL space.
    
    Hue is weighted less for low-saturation colors (grays).
    """
    h1, s1, l1 = c1
    h2, s2, l2 = c2
    
    # Hue distance (circular)
    dh = min(abs(h1 - h2), 360 - abs(h1 - h2)) / 180.0
    
    # Weight hue by average saturation (grays have similar hues but shouldn't match)
    avg_sat = (s1 + s2) / 2
    dh_weighted = dh * avg_sat
    
    ds = abs(s1 - s2)
    dl = abs(l1 - l2)
    
    return (dh_weighted ** 2 + ds ** 2 + dl ** 2) ** 0.5


def kmeans_cluster(
    colors: list[RGB],
    k: int = 5,
    iterations: int = 15
) -> list[tuple[RGB, int]]:
    """
    Perform K-means clustering on colors.
    
    Returns list of (centroid_rgb, cluster_size) tuples, sorted by cluster size.
    Uses deterministic initialization for reproducible results.
    """
    if len(colors) < k:
        # Not enough colors, return what we have
        unique = list(set(colors))
        return [(c, colors.count(c)) for c in unique[:k]]
    
    # Convert to HSL for perceptual clustering
    colors_hsl = [rgb_to_hsl(*c) for c in colors]
    
    # Deterministic initialization: pick evenly spaced colors from sorted list
    sorted_indices = sorted(range(len(colors_hsl)), key=lambda i: colors_hsl[i])
    step = len(sorted_indices) // k
    centroids = [colors_hsl[sorted_indices[i * step]] for i in range(k)]
    
    # K-means iterations
    for _ in range(iterations):
        # Assign colors to nearest centroid
        clusters: list[list[HSL]] = [[] for _ in range(k)]
        
        for color in colors_hsl:
            min_dist = float('inf')
            min_idx = 0
            for i, centroid in enumerate(centroids):
                dist = color_distance_hsl(color, centroid)
                if dist < min_dist:
                    min_dist = dist
                    min_idx = i
            clusters[min_idx].append(color)
        
        # Update centroids
        new_centroids = []
        for i, cluster in enumerate(clusters):
            if cluster:
                avg_h = sum(c[0] for c in cluster) / len(cluster)
                avg_s = sum(c[1] for c in cluster) / len(cluster)
                avg_l = sum(c[2] for c in cluster) / len(cluster)
                new_centroids.append((avg_h, avg_s, avg_l))
            else:
                new_centroids.append(centroids[i])
        
        centroids = new_centroids
    
    # Final assignment and counting
    cluster_counts = [0] * k
    for color in colors_hsl:
        min_dist = float('inf')
        min_idx = 0
        for i, centroid in enumerate(centroids):
            dist = color_distance_hsl(color, centroid)
            if dist < min_dist:
                min_dist = dist
                min_idx = i
        cluster_counts[min_idx] += 1
    
    # Convert centroids back to RGB and pair with counts
    results = []
    for i, centroid in enumerate(centroids):
        rgb = hsl_to_rgb(*centroid)
        results.append((rgb, cluster_counts[i]))
    
    # Sort by cluster size (most common first)
    results.sort(key=lambda x: -x[1])
    
    return results


def extract_palette(pixels: list[RGB], k: int = 5) -> list[Color]:
    """
    Extract K dominant colors from pixel data using CAM16 chroma filtering.

    Uses the same approach as matugen: filter by CAM16 chroma >= 5.0 to
    ensure we get colorful, usable theme colors.

    Args:
        pixels: List of RGB tuples
        k: Number of colors to extract

    Returns:
        List of Color objects, sorted by dominance
    """
    # Downsample for performance
    sampled = downsample_pixels(pixels, factor=4)

    # Filter using CAM16 chroma (like matugen does with chroma >= 5.0)
    # This is more perceptually accurate than HSL saturation filtering
    filtered = []
    for p in sampled:
        try:
            cam = Cam16.from_rgb(p[0], p[1], p[2])
            # Keep colors with sufficient chroma (colorfulness)
            # matugen uses chroma >= 5.0
            if cam.chroma >= 5.0:
                filtered.append(p)
        except (ValueError, ZeroDivisionError):
            # Skip invalid colors
            continue

    # Fall back to tone-based filter if CAM16 filtering removed too many
    if len(filtered) < k * 10:
        filtered = []
        for p in sampled:
            try:
                hct = Hct.from_rgb(p[0], p[1], p[2])
                # Keep colors with reasonable tone (not too dark or bright)
                if 15.0 < hct.tone < 85.0:
                    filtered.append(p)
            except (ValueError, ZeroDivisionError):
                continue

    if len(filtered) < k * 10:
        filtered = sampled

    # Cluster
    clusters = kmeans_cluster(filtered, k=k)

    # Score colors like Material's Score algorithm
    # Prioritizes colors that will work well as theme source colors
    result_colors = []
    for rgb, count in clusters:
        color = Color.from_rgb(rgb)
        try:
            hct = color.to_hct()

            # Calculate score based on Material Design principles:
            # 1. Chroma contribution - prefer colorful colors
            chroma_score = hct.chroma

            # 2. Tone penalty - prefer mid-tones (40-60 is ideal)
            # Penalize very dark (<20) or very bright (>80) colors
            if hct.tone < 20:
                tone_penalty = (20 - hct.tone) * 2  # Heavy penalty for dark
            elif hct.tone > 80:
                tone_penalty = (hct.tone - 80) * 1.5  # Moderate penalty for bright
            elif hct.tone < 40:
                tone_penalty = (40 - hct.tone) * 0.5  # Light penalty for somewhat dark
            elif hct.tone > 60:
                tone_penalty = (hct.tone - 60) * 0.3  # Very light penalty
            else:
                tone_penalty = 0  # Ideal tone range

            # 3. Hue penalty - slight penalty for yellow-green hues (less popular)
            hue = hct.hue
            if 80 < hue < 110:  # Yellow-green range
                hue_penalty = 5
            else:
                hue_penalty = 0

            # Combined score: chroma contribution minus penalties, weighted by count
            score = (chroma_score - tone_penalty - hue_penalty) * math.sqrt(count)

            result_colors.append((color, score, hct.chroma, hct.tone))
        except (ValueError, ZeroDivisionError):
            result_colors.append((color, 0.0, 0.0, 50.0))

    # Sort by score (highest first)
    result_colors.sort(key=lambda x: -x[1])

    # Extract just the colors
    final_colors = [c[0] for c in result_colors]

    # Ensure we have enough colors by deriving from primary using HCT
    while len(final_colors) < k:
        primary = final_colors[0]
        primary_hct = primary.to_hct()
        offset = len(final_colors) * 60.0  # 60° hue rotation in HCT
        new_hct = Hct((primary_hct.hue + offset) % 360.0, primary_hct.chroma, primary_hct.tone)
        final_colors.append(Color.from_hct(new_hct))

    return final_colors[:k]


def find_error_color(palette: list[Color]) -> Color:
    """
    Find or generate an error color (red-biased).
    
    Looks for existing red in palette, otherwise returns a default.
    """
    # Look for a red-ish color in the palette
    for color in palette:
        h, s, l = color.to_hsl()
        # Red hues: 0-30 or 330-360
        if (h <= 30 or h >= 330) and s > 0.4 and 0.3 < l < 0.7:
            return color
    
    # Default error red
    return Color.from_hex("#FD4663")


def derive_harmonious_colors(primary: Color) -> tuple[Color, Color, Color]:
    """
    Derive secondary and tertiary colors as harmonious complements to primary.
    
    Uses hue shifts for visual distinction (matugen-compatible):
    - Secondary: 30° hue shift (analogous, slightly cooler/warmer)
    - Tertiary: 60° hue shift (distinct accent color)
    - Quaternary: 180° hue shift (complementary)
    
    Returns:
        Tuple of (secondary, tertiary, quaternary) colors
    """
    h, s, l = primary.to_hsl()
    
    # Secondary: 30° analogous hue shift with slightly lower saturation
    secondary = Color.from_hsl((h + 30) % 360, s * 0.8, l)
    
    # Tertiary: complementary (180° shift) for strong contrast
    tertiary = Color.from_hsl((h + 180) % 360, s * 0.9, l)
    
    # Quaternary: complementary - opposite on color wheel
    quaternary = Color.from_hsl((h + 180) % 360, s, l)
    
    return secondary, tertiary, quaternary


# =============================================================================
# Theme Generation (Material/Normal)
# =============================================================================


def generate_material_dark(palette: list[Color]) -> dict[str, str]:
    """
    Generate Material Design 3 dark theme from palette using HCT color space.

    Uses proper Material Design 3 tonal palettes and tone values for
    perceptually accurate and consistent theming.
    """
    primary = palette[0] if palette else Color(255, 245, 155)

    # Create Material scheme from primary color
    scheme = MaterialScheme.from_rgb(primary.r, primary.g, primary.b)
    return scheme.get_dark_scheme()


def generate_material_light(palette: list[Color]) -> dict[str, str]:
    """
    Generate Material Design 3 light theme from palette using HCT color space.

    Uses proper Material Design 3 tonal palettes and tone values for
    perceptually accurate and consistent theming.
    """
    primary = palette[0] if palette else Color(93, 101, 245)

    # Create Material scheme from primary color
    scheme = MaterialScheme.from_rgb(primary.r, primary.g, primary.b)
    return scheme.get_light_scheme()


def generate_normal_dark(palette: list[Color]) -> dict[str, str]:
    """
    Generate wallust-style dark theme from palette.
    
    More vibrant than Material - uses palette colors directly and keeps
    surfaces saturated with the primary hue. Outputs same keys as Material.
    """
    # Use extracted colors directly (wallust style)
    # But check if colors are distinct enough - if not, derive from primary
    primary = palette[0] if palette else Color(255, 245, 155)
    primary_h, primary_s, primary_l = primary.to_hsl()
    
    # Secondary: use palette[1] only if hue is >30° different, otherwise derive
    MIN_HUE_DISTANCE = 30
    if len(palette) > 1:
        sec_h, _, _ = palette[1].to_hsl()
        if hue_distance(primary_h, sec_h) > MIN_HUE_DISTANCE:
            secondary = palette[1]
        else:
            # Colors too similar - shift hue by 60°
            secondary = shift_hue(primary, 60)
    else:
        secondary = shift_hue(primary, 60)
    
    # Tertiary: use palette[2] only if hue is >30° different from both primary and secondary
    if len(palette) > 2:
        ter_h, _, _ = palette[2].to_hsl()
        sec_h, _, _ = secondary.to_hsl()
        if hue_distance(primary_h, ter_h) > MIN_HUE_DISTANCE and hue_distance(sec_h, ter_h) > MIN_HUE_DISTANCE:
            tertiary = palette[2]
        else:
            # Colors too similar - shift hue by 120° from primary
            tertiary = shift_hue(primary, 120)
    else:
        tertiary = shift_hue(primary, 120)
    
    # Quaternary: complementary
    quaternary = palette[3] if len(palette) > 3 else shift_hue(primary, 180)
    error = find_error_color(palette)
    
    # Keep colors vibrant - preserve saturation
    h, s, l = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, max(s, 0.7), max(l, 0.65))
    
    h, s, l = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, max(s, 0.6), max(l, 0.60))
    
    h, s, l = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, max(s, 0.5), max(l, 0.60))

    # Container colors - darker, more saturated versions of accent colors
    def make_container_dark(base: Color) -> Color:
        h, s, l = base.to_hsl()
        return Color.from_hsl(h, min(s + 0.15, 1.0), max(l - 0.35, 0.15))

    primary_container = make_container_dark(primary_adjusted)
    secondary_container = make_container_dark(secondary_adjusted)
    tertiary_container = make_container_dark(tertiary_adjusted)
    error_container = make_container_dark(error)

    # Surface: COLORFUL dark - a deep, saturated version of primary
    # Heuristic: Shift Cyan (160-200) slightly towards Blue (+10) to avoid "Teal" look
    surface_hue, s, _ = palette[0].to_hsl()
    if 160 <= surface_hue <= 200:
        surface_hue = (surface_hue + 10) % 360
    
    base_surface = Color.from_hsl(surface_hue, s, 0.5) # l doesn't matter for next step
    
    # Preserving saturation (up to 0.9) to be true to primary color
    mSurface = _adjust_surface(base_surface, 0.90, 0.12)
    mSurfaceVariant = _adjust_surface(base_surface, 0.80, 0.16)

    # Surface containers - progressive lightness for visual hierarchy (keep primary hue)
    mSurfaceContainerLowest = _adjust_surface(base_surface, 0.85, 0.06)
    mSurfaceContainerLow = _adjust_surface(base_surface, 0.85, 0.10)
    mSurfaceContainer = _adjust_surface(base_surface, 0.70, 0.20)
    mSurfaceContainerHigh = _adjust_surface(base_surface, 0.75, 0.18)
    mSurfaceContainerHighest = _adjust_surface(base_surface, 0.70, 0.22)

    # Text colors - desaturated
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.95)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)

    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.80)
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)
    
    mOutline = _adjust_surface(palette[0], 0.10, 0.30)
    mOutlineVariant = _adjust_surface(palette[0], 0.10, 0.40)

    # Contrasting foregrounds - dark text on bright accent colors
    dark_fg = Color.from_hsl(palette[0].to_hsl()[0], 0.20, 0.12)  # Darker for better contrast
    on_primary = _ensure_contrast(dark_fg, primary_adjusted, 7.0)  # Higher contrast target
    on_secondary = _ensure_contrast(dark_fg, secondary_adjusted, 7.0)
    on_tertiary = _ensure_contrast(dark_fg, tertiary_adjusted, 7.0)
    on_error = _ensure_contrast(dark_fg, error, 7.0)

    # "On" colors for containers - light text on dark containers
    light_fg = Color.from_hsl(primary_h, 0.15, 0.90)
    on_primary_container = _ensure_contrast(light_fg, primary_container, 4.5)
    on_secondary_container = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.90), secondary_container, 4.5)
    on_tertiary_container = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.90), tertiary_container, 4.5)
    on_error_container = _ensure_contrast(Color.from_hsl(0, 0.15, 0.90), error_container, 4.5)

    # Shadow and scrim
    shadow = mSurface
    mScrim = Color(0, 0, 0)  # Pure black

    # Inverse colors - for inverted surfaces (light surface on dark theme)
    inv_h = palette[0].to_hsl()[0]
    mInverseSurface = Color.from_hsl(inv_h, 0.08, 0.90)
    mInverseOnSurface = Color.from_hsl(inv_h, 0.05, 0.15)
    mInversePrimary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.40)

    # Background aliases (same as surface in MD3)
    mBackground = mSurface
    mOnBackground = mOnSurface

    # Fixed colors - high-chroma accents consistent across light/dark
    # In dark mode: lighter versions of accent colors
    def make_fixed_dark(base: Color) -> tuple[Color, Color]:
        h, s, _ = base.to_hsl()
        fixed = Color.from_hsl(h, max(s, 0.70), 0.85)       # Light, saturated
        fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.75)   # Slightly darker
        return fixed, fixed_dim

    primary_fixed, primary_fixed_dim = make_fixed_dark(primary_adjusted)
    secondary_fixed, secondary_fixed_dim = make_fixed_dark(secondary_adjusted)
    tertiary_fixed, tertiary_fixed_dim = make_fixed_dark(tertiary_adjusted)

    # "On" colors for fixed - dark text on light fixed colors
    on_primary_fixed = _ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.15), primary_fixed, 4.5)
    on_primary_fixed_variant = _ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.20), primary_fixed_dim, 4.5)
    on_secondary_fixed = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.15), secondary_fixed, 4.5)
    on_secondary_fixed_variant = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.20), secondary_fixed_dim, 4.5)
    on_tertiary_fixed = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.15), tertiary_fixed, 4.5)
    on_tertiary_fixed_variant = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.20), tertiary_fixed_dim, 4.5)

    # Surface dim - darker than surface for dimmed areas
    mSurfaceDim = _adjust_surface(base_surface, 0.85, 0.08)
    # Surface bright - lighter than surface
    mSurfaceBright = _adjust_surface(base_surface, 0.75, 0.24)

    return {
        # Primary
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mPrimaryContainer": primary_container.to_hex(),
        "mOnPrimaryContainer": on_primary_container.to_hex(),
        "mPrimaryFixed": primary_fixed.to_hex(),
        "mPrimaryFixedDim": primary_fixed_dim.to_hex(),
        "mOnPrimaryFixed": on_primary_fixed.to_hex(),
        "mOnPrimaryFixedVariant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mSecondaryContainer": secondary_container.to_hex(),
        "mOnSecondaryContainer": on_secondary_container.to_hex(),
        "mSecondaryFixed": secondary_fixed.to_hex(),
        "mSecondaryFixedDim": secondary_fixed_dim.to_hex(),
        "mOnSecondaryFixed": on_secondary_fixed.to_hex(),
        "mOnSecondaryFixedVariant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mTertiaryContainer": tertiary_container.to_hex(),
        "mOnTertiaryContainer": on_tertiary_container.to_hex(),
        "mTertiaryFixed": tertiary_fixed.to_hex(),
        "mTertiaryFixedDim": tertiary_fixed_dim.to_hex(),
        "mOnTertiaryFixed": on_tertiary_fixed.to_hex(),
        "mOnTertiaryFixedVariant": on_tertiary_fixed_variant.to_hex(),
        # Error
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mErrorContainer": error_container.to_hex(),
        "mOnErrorContainer": on_error_container.to_hex(),
        # Surface
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mSurfaceDim": mSurfaceDim.to_hex(),
        "mSurfaceBright": mSurfaceBright.to_hex(),
        # Surface containers
        "mSurfaceContainerLowest": mSurfaceContainerLowest.to_hex(),
        "mSurfaceContainerLow": mSurfaceContainerLow.to_hex(),
        "mSurfaceContainer": mSurfaceContainer.to_hex(),
        "mSurfaceContainerHigh": mSurfaceContainerHigh.to_hex(),
        "mSurfaceContainerHighest": mSurfaceContainerHighest.to_hex(),
        # Outline and other
        "mOutline": mOutline.to_hex(),
        "mOutlineVariant": mOutlineVariant.to_hex(),
        "mShadow": shadow.to_hex(),
        "mScrim": mScrim.to_hex(),
        # Inverse
        "mInverseSurface": mInverseSurface.to_hex(),
        "mInverseOnSurface": mInverseOnSurface.to_hex(),
        "mInversePrimary": mInversePrimary.to_hex(),
        # Background
        "mBackground": mBackground.to_hex(),
        "mOnBackground": mOnBackground.to_hex(),
    }


def generate_normal_light(palette: list[Color]) -> dict[str, str]:
    """
    Generate wallust-style light theme from palette.
    
    More vibrant than Material - uses palette colors directly and keeps
    surfaces saturated with the primary hue. Outputs same keys as Material.
    """
    # Use extracted colors directly
    primary = palette[0] if palette else Color(93, 101, 245)
    secondary = palette[1] if len(palette) > 1 else shift_hue(primary, 30)
    tertiary = palette[2] if len(palette) > 2 else shift_hue(primary, 60)
    quaternary = palette[3] if len(palette) > 3 else shift_hue(primary, 180)
    error = find_error_color(palette)
    
    # Keep colors vibrant - darken for visibility on light bg
    h, s, l = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, max(s, 0.7), min(l, 0.45))
    
    h, s, l = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, max(s, 0.6), min(l, 0.40))
    
    h, s, l = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, max(s, 0.5), min(l, 0.35))

    # Container colors - lighter, less saturated versions of accent colors for light mode
    def make_container_light(base: Color) -> Color:
        h, s, l = base.to_hsl()
        return Color.from_hsl(h, max(s - 0.20, 0.30), min(l + 0.35, 0.85))

    primary_container = make_container_light(primary_adjusted)
    secondary_container = make_container_light(secondary_adjusted)
    tertiary_container = make_container_light(tertiary_adjusted)
    error_container = make_container_light(error)

    # Surface: COLORFUL light - a pastel, saturated version of primary
    # Preserving saturation (up to 0.9) to be true to primary color
    mSurface = _adjust_surface(palette[0], 0.90, 0.90)
    mSurfaceVariant = _adjust_surface(palette[0], 0.80, 0.78)  # Darker than surface

    # Surface containers - progressive darkening for light mode (keep primary hue)
    mSurfaceContainerLowest = _adjust_surface(palette[0], 0.85, 0.96)   # Lightest
    mSurfaceContainerLow = _adjust_surface(palette[0], 0.85, 0.92)
    mSurfaceContainer = _adjust_surface(palette[0], 0.80, 0.86)
    mSurfaceContainerHigh = _adjust_surface(palette[0], 0.75, 0.84)
    mSurfaceContainerHighest = _adjust_surface(palette[0], 0.70, 0.80)  # Darkest

    # Foreground colors - tinted with primary hue
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.10)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)

    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.90)  # Light text on darker variant
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)
    
    # Contrasting foregrounds - light text on dark accent colors
    light_fg = Color.from_hsl(text_h, 0.1, 0.98)  # Brighter for better contrast
    on_primary = ensure_contrast(light_fg, primary_adjusted, 7.0)  # Higher contrast target
    on_secondary = ensure_contrast(light_fg, secondary_adjusted, 7.0)
    on_tertiary = ensure_contrast(light_fg, tertiary_adjusted, 7.0)
    on_error = ensure_contrast(light_fg, error, 7.0)

    # "On" colors for containers - dark text on light containers
    primary_h, primary_s, _ = primary.to_hsl()
    dark_fg = Color.from_hsl(primary_h, 0.15, 0.15)
    on_primary_container = _ensure_contrast(dark_fg, primary_container, 4.5)
    on_secondary_container = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.15), secondary_container, 4.5)
    on_tertiary_container = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.15), tertiary_container, 4.5)
    on_error_container = _ensure_contrast(Color.from_hsl(0, 0.15, 0.15), error_container, 4.5)

    # Fixed colors - high-chroma accents consistent across light/dark
    # In light mode: darker versions of accent colors
    def make_fixed_light(base: Color) -> tuple[Color, Color]:
        h, s, _ = base.to_hsl()
        fixed = Color.from_hsl(h, max(s, 0.70), 0.40)       # Darker, saturated
        fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.30)   # Even darker
        return fixed, fixed_dim

    primary_fixed, primary_fixed_dim = make_fixed_light(primary_adjusted)
    secondary_fixed, secondary_fixed_dim = make_fixed_light(secondary_adjusted)
    tertiary_fixed, tertiary_fixed_dim = make_fixed_light(tertiary_adjusted)

    # "On" colors for fixed - light text on dark fixed colors
    on_primary_fixed = _ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.90), primary_fixed, 4.5)
    on_primary_fixed_variant = _ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.85), primary_fixed_dim, 4.5)
    on_secondary_fixed = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.90), secondary_fixed, 4.5)
    on_secondary_fixed_variant = _ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.85), secondary_fixed_dim, 4.5)
    on_tertiary_fixed = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.90), tertiary_fixed, 4.5)
    on_tertiary_fixed_variant = _ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.85), tertiary_fixed_dim, 4.5)

    # Surface dim - slightly darker than surface
    mSurfaceDim = _adjust_surface(palette[0], 0.85, 0.82)
    # Surface bright - brighter than surface
    mSurfaceBright = _adjust_surface(palette[0], 0.90, 0.95)

    # Outline uses primary hue, more saturated
    surface_h, surface_s, _ = palette[0].to_hsl()
    mOutline = Color.from_hsl(surface_h, max(surface_s * 0.4, 0.25), 0.65)
    mOutlineVariant = Color.from_hsl(surface_h, max(surface_s * 0.3, 0.20), 0.75)
    shadow = Color.from_hsl(surface_h, max(surface_s * 0.3, 0.15), 0.80)
    mScrim = Color(0, 0, 0)  # Pure black

    # Inverse colors - for inverted surfaces (dark surface on light theme)
    mInverseSurface = Color.from_hsl(surface_h, 0.08, 0.15)
    mInverseOnSurface = Color.from_hsl(surface_h, 0.05, 0.90)
    mInversePrimary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.70)

    # Background aliases (same as surface in MD3)
    mBackground = mSurface
    mOnBackground = mOnSurface

    return {
        # Primary
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mPrimaryContainer": primary_container.to_hex(),
        "mOnPrimaryContainer": on_primary_container.to_hex(),
        "mPrimaryFixed": primary_fixed.to_hex(),
        "mPrimaryFixedDim": primary_fixed_dim.to_hex(),
        "mOnPrimaryFixed": on_primary_fixed.to_hex(),
        "mOnPrimaryFixedVariant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mSecondaryContainer": secondary_container.to_hex(),
        "mOnSecondaryContainer": on_secondary_container.to_hex(),
        "mSecondaryFixed": secondary_fixed.to_hex(),
        "mSecondaryFixedDim": secondary_fixed_dim.to_hex(),
        "mOnSecondaryFixed": on_secondary_fixed.to_hex(),
        "mOnSecondaryFixedVariant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mTertiaryContainer": tertiary_container.to_hex(),
        "mOnTertiaryContainer": on_tertiary_container.to_hex(),
        "mTertiaryFixed": tertiary_fixed.to_hex(),
        "mTertiaryFixedDim": tertiary_fixed_dim.to_hex(),
        "mOnTertiaryFixed": on_tertiary_fixed.to_hex(),
        "mOnTertiaryFixedVariant": on_tertiary_fixed_variant.to_hex(),
        # Error
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mErrorContainer": error_container.to_hex(),
        "mOnErrorContainer": on_error_container.to_hex(),
        # Surface
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mSurfaceDim": mSurfaceDim.to_hex(),
        "mSurfaceBright": mSurfaceBright.to_hex(),
        # Surface containers
        "mSurfaceContainerLowest": mSurfaceContainerLowest.to_hex(),
        "mSurfaceContainerLow": mSurfaceContainerLow.to_hex(),
        "mSurfaceContainer": mSurfaceContainer.to_hex(),
        "mSurfaceContainerHigh": mSurfaceContainerHigh.to_hex(),
        "mSurfaceContainerHighest": mSurfaceContainerHighest.to_hex(),
        # Outline and other
        "mOutline": mOutline.to_hex(),
        "mOutlineVariant": mOutlineVariant.to_hex(),
        "mShadow": shadow.to_hex(),
        "mScrim": mScrim.to_hex(),
        # Inverse
        "mInverseSurface": mInverseSurface.to_hex(),
        "mInverseOnSurface": mInverseOnSurface.to_hex(),
        "mInversePrimary": mInversePrimary.to_hex(),
        # Background
        "mBackground": mBackground.to_hex(),
        "mOnBackground": mOnBackground.to_hex(),
    }


def generate_theme(
    palette: list[Color],
    mode: ThemeMode,
    material: bool = True
) -> dict[str, str]:
    """Generate theme for specified mode."""
    if material:
        if mode == "dark":
            return generate_material_dark(palette)
        return generate_material_light(palette)
    else:
        if mode == "dark":
            return generate_normal_dark(palette)
        return generate_normal_light(palette)


# =============================================================================
# Template Rendering (Matugen Compatibility)
# =============================================================================

class TemplateRenderer:
    """
    Renders templates using the generated theme colors.
    Compatible with Matugen-style {{colors.name.mode.format}} tags.
    """
    
    # Map from Matugen color names to theme keys
    # Now properly maps to MaterialScheme generated keys
    COLOR_MAP = {
        # Primary colors
        "primary": "mPrimary",
        "on_primary": "mOnPrimary",
        "primary_container": "mPrimaryContainer",
        "on_primary_container": "mOnPrimaryContainer",

        # Secondary colors
        "secondary": "mSecondary",
        "on_secondary": "mOnSecondary",
        "secondary_container": "mSecondaryContainer",
        "on_secondary_container": "mOnSecondaryContainer",

        # Tertiary colors
        "tertiary": "mTertiary",
        "on_tertiary": "mOnTertiary",
        "tertiary_container": "mTertiaryContainer",
        "on_tertiary_container": "mOnTertiaryContainer",

        # Error colors
        "error": "mError",
        "on_error": "mOnError",
        "error_container": "mErrorContainer",
        "on_error_container": "mOnErrorContainer",

        # Surface colors
        "surface": "mSurface",
        "on_surface": "mOnSurface",
        "surface_variant": "mSurfaceVariant",
        "on_surface_variant": "mOnSurfaceVariant",

        # Outline and misc
        "outline": "mOutline",
        "outline_variant": "mOutlineVariant",
        "shadow": "mShadow",
        "scrim": "mScrim",

        # Inverse colors
        "inverse_surface": "mInverseSurface",
        "inverse_on_surface": "mInverseOnSurface",
        "inverse_primary": "mInversePrimary",

        # Background (alias for surface in MD3)
        "background": "mBackground",
        "on_background": "mOnBackground",

        # Surface Containers (Material 3)
        "surface_container_lowest": "mSurfaceContainerLowest",
        "surface_container_low": "mSurfaceContainerLow",
        "surface_container": "mSurfaceContainer",
        "surface_container_high": "mSurfaceContainerHigh",
        "surface_container_highest": "mSurfaceContainerHighest",
        "surface_dim": "mSurfaceDim",
        "surface_bright": "mSurfaceBright",

        # Fixed colors (Material 3)
        "primary_fixed": "mPrimaryFixed",
        "primary_fixed_dim": "mPrimaryFixedDim",
        "on_primary_fixed": "mOnPrimaryFixed",
        "on_primary_fixed_variant": "mOnPrimaryFixedVariant",
        "secondary_fixed": "mSecondaryFixed",
        "secondary_fixed_dim": "mSecondaryFixedDim",
        "on_secondary_fixed": "mOnSecondaryFixed",
        "on_secondary_fixed_variant": "mOnSecondaryFixedVariant",
        "tertiary_fixed": "mTertiaryFixed",
        "tertiary_fixed_dim": "mTertiaryFixedDim",
        "on_tertiary_fixed": "mOnTertiaryFixed",
        "on_tertiary_fixed_variant": "mOnTertiaryFixedVariant",

        # Custom/Noctalia keys
        "hover": "mSurfaceContainerHigh",  # Fallback
        "on_hover": "mOnSurface",  # Fallback
    }

    def __init__(self, theme_data: dict[str, dict[str, str]]):
        self.theme_data = theme_data

    def _get_color_value(self, color_name: str, mode: str, format_type: str) -> str:
        """Get processed color value for a template tag."""
        # Map color name to theme key
        key = self.COLOR_MAP.get(color_name)
        if not key:
            return f"{{{{UNKNOWN_COLOR_{color_name}}}}}"

        # Get relevant mode data
        # Handle 'default' mode (active mode if only one generated, or first available)
        if mode == "default":
            mode_data = self.theme_data.get("dark") or self.theme_data.get("light")
        else:
            mode_data = self.theme_data.get(mode)

        if not mode_data:
            return f"{{{{UNKNOWN_MODE_{mode}}}}}"

        hex_color = mode_data.get(key)
        if not hex_color:
             # Fallback to unmapped name (e.g. if input JSON uses standard keys)
             hex_color = mode_data.get(color_name)
        
        if not hex_color:
            return f"{{{{UNKNOWN_KEY_{key}}}}}"

        # Apply format
        if format_type == "hex":
            return hex_color
        elif format_type == "hex_stripped":
            return hex_color.lstrip('#')
        elif format_type == "rgb":
            c = Color.from_hex(hex_color)
            return f"{c.r}, {c.g}, {c.b}"
        elif format_type == "rgba":
            c = Color.from_hex(hex_color)
            return f"{c.r}, {c.g}, {c.b}, 1.0"
        elif format_type in ("hue", "saturation", "lightness"):
            c = Color.from_hex(hex_color)
            h, s, l = c.to_hsl()
            if format_type == "hue": return str(int(h))
            if format_type == "saturation": return str(int(s * 100))
            if format_type == "lightness": return str(int(l * 100))
        
        return hex_color

    def render(self, template_text: str) -> str:
        """Replace all tags in template text."""
        # Generic pattern for {{colors.name.mode.format}}
        pattern = r"\{\{\s*colors\.([a-z_0-9]+)\.([a-z_0-9]+)\.([a-z_0-9]+)\s*\}\}"
        
        def replace(match):
            color_name, mode, format_type = match.groups()
            return self._get_color_value(color_name, mode, format_type)

        return re.sub(pattern, replace, template_text)

    def render_file(self, input_path: Path, output_path: Path):
        """Render a template file to an output path."""
        try:
            template_text = input_path.read_text()
            rendered_text = self.render(template_text)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(rendered_text)
        except Exception as e:
            print(f"Error rendering template {input_path}: {e}", file=sys.stderr)

    def process_config_file(self, config_path: Path):
        """Process Matugen TOML configuration file."""
        if not tomllib:
            print("Error: tomllib module not available (requires Python 3.11+)", file=sys.stderr)
            return

        try:
            with open(config_path, "rb") as f:
                data = tomllib.load(f)
            
            # Matugen config structure: https://github.com/InioX/matugen
            # [config] section (ignored)
            # [templates.name] sections
            
            templates = data.get("templates", {})
            for name, template in templates.items():
                input_path = template.get("input_path")
                output_path = template.get("output_path")
                
                if not input_path or not output_path:
                    continue
                    
                self.render_file(Path(input_path).expanduser(), Path(output_path).expanduser())
                
                # Matugen supports post_hook, we probably can't easily support that blindly
                # without shell=True which is risky, but let's see if we need it.
                # TemplateProcessor.qml puts post_hook in the TOML.
                # We should execute it if possible to fully replicate behavior.
                post_hook = template.get("post_hook")
                if post_hook:
                    import subprocess
                    try:
                        subprocess.run(post_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running post_hook for {name}: {e}", file=sys.stderr)

        except Exception as e:
            print(f"Error processing config file {config_path}: {e}", file=sys.stderr)

def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog='template-processor',
        description='Extract color palettes from wallpapers and generate themes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 template-processor.py wallpaper.png --material --both
  python3 template-processor.py wallpaper.jpg --dark -o theme.json
  python3 template-processor.py ~/Pictures/bg.png --normal --light
        """
    )
    
    parser.add_argument(
        'image',
        type=Path,
        help='Path to wallpaper image (PNG/JPG)'
    )
    
    # Theme style (mutually exclusive)
    style_group = parser.add_mutually_exclusive_group()
    style_group.add_argument(
        '--material',
        action='store_true',
        default=True,
        help='Generate Material-style colors (default)'
    )
    style_group.add_argument(
        '--default',
        action='store_true',
        help='Generate simpler accent-based palette'
    )
    
    # Theme mode (mutually exclusive)
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        '--dark',
        action='store_true',
        help='Generate dark theme only'
    )
    mode_group.add_argument(
        '--light',
        action='store_true',
        help='Generate light theme only'
    )
    mode_group.add_argument(
        '--both',
        action='store_true',
        default=True,
        help='Generate both dark and light themes (default)'
    )
    
    parser.add_argument(
        '--output', '-o',
        type=Path,
        help='Write JSON output to file (stdout if omitted)'
    )
    
    parser.add_argument(
        '--render', '-r',
        action='append',
        help='Render a template (input_path:output_path)'
    )
    
    # Matugen compatibility arguments
    parser.add_argument(
        '--config', '-c',
        type=Path,
        help='Path to Matugen TOML configuration file'
    )
    parser.add_argument(
        '--mode',
        choices=['dark', 'light'],
        help='Override theme mode (for Matugen compatibility)'
    )
    parser.add_argument(
        '--type', '-t',
        help='Scheme type (ignored, for Matugen compatibility)'
    )
    
    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()
    
    # Validate image path
    if not args.image.exists():
        print(f"Error: Image not found: {args.image}", file=sys.stderr)
        return 1
    
    
    # Initialize result dictionary
    result: dict[str, dict[str, str]] = {}

    # Check if input is a JSON palette (Predefined Scheme bypass)
    if args.image.suffix.lower() == '.json':
        try:
            with open(args.image, 'r') as f:
                input_data = json.load(f)
            
            # Expect {"colors": ...} or direct dict
            colors_data = input_data.get("colors", input_data)
            
            # Flatten QML-style object structure if needed
            # structure: key -> { default: { hex: "#..." } } or key -> "#..."
            flat_colors = {}
            for k, v in colors_data.items():
                if isinstance(v, dict) and 'default' in v and 'hex' in v['default']:
                    flat_colors[k] = v['default']['hex']
                elif isinstance(v, str):
                    flat_colors[k] = v
                else:
                    # Best effort fallback
                    flat_colors[k] = str(v)
            
            # Assign to both/all modes since predefined scheme usually provides the correct palette for the requested mode
            result["dark"] = flat_colors
            result["light"] = flat_colors
            
            # Skip extraction logic
            palette = None 
        except Exception as e:
            print(f"Error reading JSON palette: {e}", file=sys.stderr)
            return 1
    else:
        # Standard Image Extraction
        # Validate image path is a file
        if not args.image.is_file():
             print(f"Error: Not a file: {args.image}", file=sys.stderr)
             return 1

        # Read image
        try:
            pixels = read_image(args.image)
        except ImageReadError as e:
            print(f"Error reading image: {e}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"Unexpected error reading image: {e}", file=sys.stderr)
            return 1
        
        # Extract palette
        k = 5
        palette = extract_palette(pixels, k=k)
        
        if not palette:
            print("Error: Could not extract colors from image", file=sys.stderr)
            return 1
    
    # Determine which themes to generate
    use_material = not args.default
    
    # Handle --mode compatibility
    arg_dark = args.dark
    arg_light = args.light
    arg_both = args.both
    
    if args.mode == 'dark':
        arg_dark = True
        arg_light = False
        arg_both = False
    elif args.mode == 'light':
        arg_dark = False
        arg_light = True
        arg_both = False
    
    
    if palette:
        if arg_dark:
            result["dark"] = generate_theme(palette, "dark", use_material)
        elif arg_light:
            result["light"] = generate_theme(palette, "light", use_material)
        else:
            # Generate both (default)
            result["dark"] = generate_theme(palette, "dark", use_material)
            result["light"] = generate_theme(palette, "light", use_material)
    
    # Output JSON
    json_output = json.dumps(result, indent=2)
    
    if args.output:
        try:
            args.output.write_text(json_output)
            print(f"Theme written to: {args.output}", file=sys.stderr)
        except IOError as e:
            print(f"Error writing output: {e}", file=sys.stderr)
            return 1
    elif not args.render and not args.config:
        print(json_output)
    
    # Process templates
    if args.render or args.config:
        renderer = TemplateRenderer(result)
        
        if args.render:
            for render_spec in args.render:
                if ':' not in render_spec:
                    print(f"Error: Invalid render spec (must be input:output): {render_spec}", file=sys.stderr)
                    continue
                
                input_str, output_str = render_spec.split(':', 1)
                input_path = Path(input_str).expanduser()
                output_path = Path(output_str).expanduser()
                
                if not input_path.exists():
                    print(f"Error: Template not found: {input_path}", file=sys.stderr)
                    continue
                    
                renderer.render_file(input_path, output_path)
                
        if args.config:
            if not args.config.exists():
                 print(f"Error: Config file not found: {args.config}", file=sys.stderr)
            else:
                 renderer.process_config_file(args.config)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
