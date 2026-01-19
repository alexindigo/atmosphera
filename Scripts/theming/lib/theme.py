"""
Theme generation functions for Material and Normal modes.

This module provides functions for generating complete color themes
from a color palette, supporting both Material Design 3 and a more
vibrant "wallust-style" theme.
"""

from typing import Literal

from .color import Color, shift_hue, hue_distance, adjust_surface
from .contrast import ensure_contrast
from .material import MaterialScheme
from .palette import find_error_color

# Type alias
ThemeMode = Literal["dark", "light"]


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

    base_surface = Color.from_hsl(surface_hue, s, 0.5)  # l doesn't matter for next step

    # Preserving saturation (up to 0.9) to be true to primary color
    surface = adjust_surface(base_surface, 0.90, 0.12)
    surface_variant = adjust_surface(base_surface, 0.80, 0.16)

    # Surface containers - progressive lightness for visual hierarchy (keep primary hue)
    surface_container_lowest = adjust_surface(base_surface, 0.85, 0.06)
    surface_container_low = adjust_surface(base_surface, 0.85, 0.10)
    surface_container = adjust_surface(base_surface, 0.70, 0.20)
    surface_container_high = adjust_surface(base_surface, 0.75, 0.18)
    surface_container_highest = adjust_surface(base_surface, 0.70, 0.22)

    # Text colors - desaturated
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.95)
    on_surface = ensure_contrast(base_on_surface, surface, 4.5)

    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.80)
    on_surface_variant = ensure_contrast(base_on_surface_variant, surface_variant, 4.5)

    outline = adjust_surface(palette[0], 0.10, 0.30)
    outline_variant = adjust_surface(palette[0], 0.10, 0.40)

    # Contrasting foregrounds - dark text on bright accent colors
    dark_fg = Color.from_hsl(palette[0].to_hsl()[0], 0.20, 0.12)  # Darker for better contrast
    on_primary = ensure_contrast(dark_fg, primary_adjusted, 7.0)  # Higher contrast target
    on_secondary = ensure_contrast(dark_fg, secondary_adjusted, 7.0)
    on_tertiary = ensure_contrast(dark_fg, tertiary_adjusted, 7.0)
    on_error = ensure_contrast(dark_fg, error, 7.0)

    # "On" colors for containers - light text on dark containers, tinted with respective color
    on_primary_container = ensure_contrast(Color.from_hsl(primary_h, primary_s, 0.90), primary_container, 4.5)
    sec_h, sec_s, _ = secondary.to_hsl()
    on_secondary_container = ensure_contrast(Color.from_hsl(sec_h, sec_s, 0.90), secondary_container, 4.5)
    ter_h, ter_s, _ = tertiary.to_hsl()
    on_tertiary_container = ensure_contrast(Color.from_hsl(ter_h, ter_s, 0.90), tertiary_container, 4.5)
    err_h, err_s, _ = error.to_hsl()
    on_error_container = ensure_contrast(Color.from_hsl(err_h, err_s, 0.90), error_container, 4.5)

    # Shadow and scrim
    shadow = surface
    scrim = Color(0, 0, 0)  # Pure black

    # Inverse colors - for inverted surfaces (light surface on dark theme)
    inv_h = palette[0].to_hsl()[0]
    inverse_surface = Color.from_hsl(inv_h, 0.08, 0.90)
    inverse_on_surface = Color.from_hsl(inv_h, 0.05, 0.15)
    inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.40)

    # Background aliases (same as surface in MD3)
    background = surface
    on_background = on_surface

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
    on_primary_fixed = ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.15), primary_fixed, 4.5)
    on_primary_fixed_variant = ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.20), primary_fixed_dim, 4.5)
    on_secondary_fixed = ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.15), secondary_fixed, 4.5)
    on_secondary_fixed_variant = ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.20), secondary_fixed_dim, 4.5)
    on_tertiary_fixed = ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.15), tertiary_fixed, 4.5)
    on_tertiary_fixed_variant = ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.20), tertiary_fixed_dim, 4.5)

    # Surface dim - darker than surface for dimmed areas
    surface_dim = adjust_surface(base_surface, 0.85, 0.08)
    # Surface bright - lighter than surface
    surface_bright = adjust_surface(base_surface, 0.75, 0.24)

    return {
        # Primary
        "primary": primary_adjusted.to_hex(),
        "on_primary": on_primary.to_hex(),
        "primary_container": primary_container.to_hex(),
        "on_primary_container": on_primary_container.to_hex(),
        "primary_fixed": primary_fixed.to_hex(),
        "primary_fixed_dim": primary_fixed_dim.to_hex(),
        "on_primary_fixed": on_primary_fixed.to_hex(),
        "on_primary_fixed_variant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "secondary": secondary_adjusted.to_hex(),
        "on_secondary": on_secondary.to_hex(),
        "secondary_container": secondary_container.to_hex(),
        "on_secondary_container": on_secondary_container.to_hex(),
        "secondary_fixed": secondary_fixed.to_hex(),
        "secondary_fixed_dim": secondary_fixed_dim.to_hex(),
        "on_secondary_fixed": on_secondary_fixed.to_hex(),
        "on_secondary_fixed_variant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "tertiary": tertiary_adjusted.to_hex(),
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
    surface = adjust_surface(palette[0], 0.90, 0.90)
    surface_variant = adjust_surface(palette[0], 0.80, 0.78)  # Darker than surface

    # Surface containers - progressive darkening for light mode (keep primary hue)
    surface_container_lowest = adjust_surface(palette[0], 0.85, 0.96)   # Lightest
    surface_container_low = adjust_surface(palette[0], 0.85, 0.92)
    surface_container = adjust_surface(palette[0], 0.80, 0.86)
    surface_container_high = adjust_surface(palette[0], 0.75, 0.84)
    surface_container_highest = adjust_surface(palette[0], 0.70, 0.80)  # Darkest

    # Foreground colors - tinted with primary hue
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.10)
    on_surface = ensure_contrast(base_on_surface, surface, 4.5)

    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.90)  # Light text on darker variant
    on_surface_variant = ensure_contrast(base_on_surface_variant, surface_variant, 4.5)

    # Contrasting foregrounds - light text on dark accent colors
    light_fg = Color.from_hsl(text_h, 0.1, 0.98)  # Brighter for better contrast
    on_primary = ensure_contrast(light_fg, primary_adjusted, 7.0)  # Higher contrast target
    on_secondary = ensure_contrast(light_fg, secondary_adjusted, 7.0)
    on_tertiary = ensure_contrast(light_fg, tertiary_adjusted, 7.0)
    on_error = ensure_contrast(light_fg, error, 7.0)

    # "On" colors for containers - dark text on light containers, tinted with respective color
    primary_h, primary_s, _ = primary.to_hsl()
    on_primary_container = ensure_contrast(Color.from_hsl(primary_h, primary_s, 0.15), primary_container, 4.5)
    sec_h, sec_s, _ = secondary.to_hsl()
    on_secondary_container = ensure_contrast(Color.from_hsl(sec_h, sec_s, 0.15), secondary_container, 4.5)
    ter_h, ter_s, _ = tertiary.to_hsl()
    on_tertiary_container = ensure_contrast(Color.from_hsl(ter_h, ter_s, 0.15), tertiary_container, 4.5)
    err_h, err_s, _ = error.to_hsl()
    on_error_container = ensure_contrast(Color.from_hsl(err_h, err_s, 0.15), error_container, 4.5)

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
    on_primary_fixed = ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.90), primary_fixed, 4.5)
    on_primary_fixed_variant = ensure_contrast(Color.from_hsl(primary_h, 0.15, 0.85), primary_fixed_dim, 4.5)
    on_secondary_fixed = ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.90), secondary_fixed, 4.5)
    on_secondary_fixed_variant = ensure_contrast(Color.from_hsl(secondary.to_hsl()[0], 0.15, 0.85), secondary_fixed_dim, 4.5)
    on_tertiary_fixed = ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.90), tertiary_fixed, 4.5)
    on_tertiary_fixed_variant = ensure_contrast(Color.from_hsl(tertiary.to_hsl()[0], 0.15, 0.85), tertiary_fixed_dim, 4.5)

    # Surface dim - slightly darker than surface
    surface_dim = adjust_surface(palette[0], 0.85, 0.82)
    # Surface bright - brighter than surface
    surface_bright = adjust_surface(palette[0], 0.90, 0.95)

    # Outline uses primary hue, more saturated
    surface_h, surface_s, _ = palette[0].to_hsl()
    outline = Color.from_hsl(surface_h, max(surface_s * 0.4, 0.25), 0.65)
    outline_variant = Color.from_hsl(surface_h, max(surface_s * 0.3, 0.20), 0.75)
    shadow = Color.from_hsl(surface_h, max(surface_s * 0.3, 0.15), 0.80)
    scrim = Color(0, 0, 0)  # Pure black

    # Inverse colors - for inverted surfaces (dark surface on light theme)
    inverse_surface = Color.from_hsl(surface_h, 0.08, 0.15)
    inverse_on_surface = Color.from_hsl(surface_h, 0.05, 0.90)
    inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.70)

    # Background aliases (same as surface in MD3)
    background = surface
    on_background = on_surface

    return {
        # Primary
        "primary": primary_adjusted.to_hex(),
        "on_primary": on_primary.to_hex(),
        "primary_container": primary_container.to_hex(),
        "on_primary_container": on_primary_container.to_hex(),
        "primary_fixed": primary_fixed.to_hex(),
        "primary_fixed_dim": primary_fixed_dim.to_hex(),
        "on_primary_fixed": on_primary_fixed.to_hex(),
        "on_primary_fixed_variant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "secondary": secondary_adjusted.to_hex(),
        "on_secondary": on_secondary.to_hex(),
        "secondary_container": secondary_container.to_hex(),
        "on_secondary_container": on_secondary_container.to_hex(),
        "secondary_fixed": secondary_fixed.to_hex(),
        "secondary_fixed_dim": secondary_fixed_dim.to_hex(),
        "on_secondary_fixed": on_secondary_fixed.to_hex(),
        "on_secondary_fixed_variant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "tertiary": tertiary_adjusted.to_hex(),
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
