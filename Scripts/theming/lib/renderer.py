"""
Template rendering for Matugen compatibility.

This module provides the TemplateRenderer class for processing template files
using the {{colors.name.mode.format}} syntax compatible with Matugen.
"""

import re
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

from .color import Color


class TemplateRenderer:
    """
    Renders templates using the generated theme colors.
    Compatible with Matugen-style {{colors.name.mode.format}} tags.

    Theme data now uses snake_case keys directly (e.g., 'primary', 'surface_container').
    """

    # Aliases for custom/legacy keys
    COLOR_ALIASES = {
        "hover": "surface_container_high",
        "on_hover": "on_surface",
    }

    def __init__(self, theme_data: dict[str, dict[str, str]]):
        self.theme_data = theme_data

    def _get_color_value(self, color_name: str, mode: str, format_type: str) -> str:
        """Get processed color value for a template tag."""
        # Resolve aliases (e.g., hover -> surface_container_high)
        key = self.COLOR_ALIASES.get(color_name, color_name)

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
            if format_type == "hue":
                return str(int(h))
            if format_type == "saturation":
                return str(int(s * 100))
            if format_type == "lightness":
                return str(int(l * 100))

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
