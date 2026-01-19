"""
Predefined scheme expansion - Convert 14-color schemes to full palette.

This module expands predefined color schemes (like Tokyo-Night) from their
14 core colors to the full 48-color palette used by templates.

Input format (14 colors):
    mPrimary, mOnPrimary, mSecondary, mOnSecondary, mTertiary, mOnTertiary,
    mError, mOnError, mSurface, mOnSurface, mSurfaceVariant, mOnSurfaceVariant,
    mOutline, mHover

Output: Full 48-color palette matching generate_theme() output.
"""

from typing import Literal

from .color import Color, adjust_surface
from .contrast import ensure_contrast

ThemeMode = Literal["dark", "light"]


def _hex_to_color(hex_str: str) -> Color:
    """Convert hex string to Color object."""
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16)
    g = int(hex_str[2:4], 16)
    b = int(hex_str[4:6], 16)
    return Color(r, g, b)


def _make_container_dark(base: Color) -> Color:
    """Generate container color for dark mode."""
    h, s, l = base.to_hsl()
    return Color.from_hsl(h, min(s + 0.15, 1.0), max(l - 0.35, 0.15))


def _make_container_light(base: Color) -> Color:
    """Generate container color for light mode."""
    h, s, l = base.to_hsl()
    return Color.from_hsl(h, max(s - 0.20, 0.30), min(l + 0.35, 0.85))


def _make_fixed_dark(base: Color) -> tuple[Color, Color]:
    """Generate fixed and fixed_dim colors for dark mode."""
    h, s, _ = base.to_hsl()
    fixed = Color.from_hsl(h, max(s, 0.70), 0.85)
    fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.75)
    return fixed, fixed_dim


def _make_fixed_light(base: Color) -> tuple[Color, Color]:
    """Generate fixed and fixed_dim colors for light mode."""
    h, s, _ = base.to_hsl()
    fixed = Color.from_hsl(h, max(s, 0.70), 0.40)
    fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.30)
    return fixed, fixed_dim


def expand_predefined_scheme(scheme_data: dict[str, str], mode: ThemeMode) -> dict[str, str]:
    """
    Expand 14-color predefined scheme to full 48-color palette.

    Args:
        scheme_data: Dictionary with keys like mPrimary, mSecondary, etc.
        mode: "dark" or "light"

    Returns:
        Dictionary with all 48 color names mapped to hex values.
    """
    is_dark = mode == "dark"

    # Parse input colors
    primary = _hex_to_color(scheme_data["mPrimary"])
    on_primary = _hex_to_color(scheme_data["mOnPrimary"])
    secondary = _hex_to_color(scheme_data["mSecondary"])
    on_secondary = _hex_to_color(scheme_data["mOnSecondary"])
    tertiary = _hex_to_color(scheme_data["mTertiary"])
    on_tertiary = _hex_to_color(scheme_data["mOnTertiary"])
    error = _hex_to_color(scheme_data["mError"])
    on_error = _hex_to_color(scheme_data["mOnError"])
    surface = _hex_to_color(scheme_data["mSurface"])
    on_surface = _hex_to_color(scheme_data["mOnSurface"])
    surface_variant = _hex_to_color(scheme_data["mSurfaceVariant"])
    on_surface_variant = _hex_to_color(scheme_data["mOnSurfaceVariant"])
    outline = _hex_to_color(scheme_data["mOutline"])

    # Generate container colors
    if is_dark:
        primary_container = _make_container_dark(primary)
        secondary_container = _make_container_dark(secondary)
        tertiary_container = _make_container_dark(tertiary)
        error_container = _make_container_dark(error)
    else:
        primary_container = _make_container_light(primary)
        secondary_container = _make_container_light(secondary)
        tertiary_container = _make_container_light(tertiary)
        error_container = _make_container_light(error)

    # Generate "on container" colors with proper contrast
    primary_h, primary_s, _ = primary.to_hsl()
    secondary_h, secondary_s, _ = secondary.to_hsl()
    tertiary_h, tertiary_s, _ = tertiary.to_hsl()
    error_h, error_s, _ = error.to_hsl()

    if is_dark:
        # Light text on dark containers
        on_primary_container = ensure_contrast(
            Color.from_hsl(primary_h, primary_s, 0.90), primary_container, 4.5
        )
        on_secondary_container = ensure_contrast(
            Color.from_hsl(secondary_h, secondary_s, 0.90), secondary_container, 4.5
        )
        on_tertiary_container = ensure_contrast(
            Color.from_hsl(tertiary_h, tertiary_s, 0.90), tertiary_container, 4.5
        )
        on_error_container = ensure_contrast(
            Color.from_hsl(error_h, error_s, 0.90), error_container, 4.5
        )
    else:
        # Dark text on light containers
        on_primary_container = ensure_contrast(
            Color.from_hsl(primary_h, primary_s, 0.15), primary_container, 4.5
        )
        on_secondary_container = ensure_contrast(
            Color.from_hsl(secondary_h, secondary_s, 0.15), secondary_container, 4.5
        )
        on_tertiary_container = ensure_contrast(
            Color.from_hsl(tertiary_h, tertiary_s, 0.15), tertiary_container, 4.5
        )
        on_error_container = ensure_contrast(
            Color.from_hsl(error_h, error_s, 0.15), error_container, 4.5
        )

    # Generate fixed colors
    if is_dark:
        primary_fixed, primary_fixed_dim = _make_fixed_dark(primary)
        secondary_fixed, secondary_fixed_dim = _make_fixed_dark(secondary)
        tertiary_fixed, tertiary_fixed_dim = _make_fixed_dark(tertiary)
    else:
        primary_fixed, primary_fixed_dim = _make_fixed_light(primary)
        secondary_fixed, secondary_fixed_dim = _make_fixed_light(secondary)
        tertiary_fixed, tertiary_fixed_dim = _make_fixed_light(tertiary)

    # Generate "on fixed" colors
    if is_dark:
        on_primary_fixed = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.15), primary_fixed, 4.5
        )
        on_primary_fixed_variant = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.20), primary_fixed_dim, 4.5
        )
        on_secondary_fixed = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.15), secondary_fixed, 4.5
        )
        on_secondary_fixed_variant = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.20), secondary_fixed_dim, 4.5
        )
        on_tertiary_fixed = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.15), tertiary_fixed, 4.5
        )
        on_tertiary_fixed_variant = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.20), tertiary_fixed_dim, 4.5
        )
    else:
        on_primary_fixed = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.90), primary_fixed, 4.5
        )
        on_primary_fixed_variant = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.85), primary_fixed_dim, 4.5
        )
        on_secondary_fixed = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.90), secondary_fixed, 4.5
        )
        on_secondary_fixed_variant = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.85), secondary_fixed_dim, 4.5
        )
        on_tertiary_fixed = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.90), tertiary_fixed, 4.5
        )
        on_tertiary_fixed_variant = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.85), tertiary_fixed_dim, 4.5
        )

    # Generate surface containers from the surface color
    surface_h, surface_s, _ = surface.to_hsl()
    base_surface = Color.from_hsl(surface_h, surface_s, 0.5)

    if is_dark:
        surface_container_lowest = adjust_surface(base_surface, 0.85, 0.06)
        surface_container_low = adjust_surface(base_surface, 0.85, 0.10)
        surface_container = adjust_surface(base_surface, 0.70, 0.20)
        surface_container_high = adjust_surface(base_surface, 0.75, 0.18)
        surface_container_highest = adjust_surface(base_surface, 0.70, 0.22)
        surface_dim = adjust_surface(base_surface, 0.85, 0.08)
        surface_bright = adjust_surface(base_surface, 0.75, 0.24)
    else:
        surface_container_lowest = adjust_surface(base_surface, 0.85, 0.96)
        surface_container_low = adjust_surface(base_surface, 0.85, 0.92)
        surface_container = adjust_surface(base_surface, 0.80, 0.86)
        surface_container_high = adjust_surface(base_surface, 0.75, 0.84)
        surface_container_highest = adjust_surface(base_surface, 0.70, 0.80)
        surface_dim = adjust_surface(base_surface, 0.85, 0.82)
        surface_bright = adjust_surface(base_surface, 0.90, 0.95)

    # Generate outline variant
    outline_h, outline_s, outline_l = outline.to_hsl()
    if is_dark:
        outline_variant = Color.from_hsl(outline_h, outline_s, max(outline_l - 0.15, 0.1))
    else:
        outline_variant = Color.from_hsl(outline_h, outline_s, min(outline_l + 0.15, 0.9))

    # Shadow and scrim
    shadow = surface  # Use surface color for shadow in dark mode
    scrim = Color(0, 0, 0)

    # Inverse colors
    if is_dark:
        inverse_surface = Color.from_hsl(surface_h, 0.08, 0.90)
        inverse_on_surface = Color.from_hsl(surface_h, 0.05, 0.15)
        inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.40)
    else:
        inverse_surface = Color.from_hsl(surface_h, 0.08, 0.15)
        inverse_on_surface = Color.from_hsl(surface_h, 0.05, 0.90)
        inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.70)

    # Background is same as surface in MD3
    background = surface
    on_background = on_surface

    return {
        # Primary
        "primary": primary.to_hex(),
        "on_primary": on_primary.to_hex(),
        "primary_container": primary_container.to_hex(),
        "on_primary_container": on_primary_container.to_hex(),
        "primary_fixed": primary_fixed.to_hex(),
        "primary_fixed_dim": primary_fixed_dim.to_hex(),
        "on_primary_fixed": on_primary_fixed.to_hex(),
        "on_primary_fixed_variant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "secondary": secondary.to_hex(),
        "on_secondary": on_secondary.to_hex(),
        "secondary_container": secondary_container.to_hex(),
        "on_secondary_container": on_secondary_container.to_hex(),
        "secondary_fixed": secondary_fixed.to_hex(),
        "secondary_fixed_dim": secondary_fixed_dim.to_hex(),
        "on_secondary_fixed": on_secondary_fixed.to_hex(),
        "on_secondary_fixed_variant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "tertiary": tertiary.to_hex(),
        "on_tertiary": on_tertiary.to_hex(),
        "tertiary_container": tertiary_container.to_hex(),
        "on_tertiary_container": on_tertiary_container.to_hex(),
        "tertiary_fixed": tertiary_fixed.to_hex(),
        "tertiary_fixed_dim": tertiary_fixed_dim.to_hex(),
        "on_tertiary_fixed": on_tertiary_fixed.to_hex(),
        "on_tertiary_fixed_variant": on_tertiary_fixed_variant.to_hex(),
        # Error
        "error": error.to_hex(),
        "on_error": on_error.to_hex(),
        "error_container": error_container.to_hex(),
        "on_error_container": on_error_container.to_hex(),
        # Surface
        "surface": surface.to_hex(),
        "on_surface": on_surface.to_hex(),
        "surface_variant": surface_variant.to_hex(),
        "on_surface_variant": on_surface_variant.to_hex(),
        "surface_dim": surface_dim.to_hex(),
        "surface_bright": surface_bright.to_hex(),
        # Surface containers
        "surface_container_lowest": surface_container_lowest.to_hex(),
        "surface_container_low": surface_container_low.to_hex(),
        "surface_container": surface_container.to_hex(),
        "surface_container_high": surface_container_high.to_hex(),
        "surface_container_highest": surface_container_highest.to_hex(),
        # Outline and other
        "outline": outline.to_hex(),
        "outline_variant": outline_variant.to_hex(),
        "shadow": shadow.to_hex(),
        "scrim": scrim.to_hex(),
        # Inverse
        "inverse_surface": inverse_surface.to_hex(),
        "inverse_on_surface": inverse_on_surface.to_hex(),
        "inverse_primary": inverse_primary.to_hex(),
        # Background
        "background": background.to_hex(),
        "on_background": on_background.to_hex(),
    }
