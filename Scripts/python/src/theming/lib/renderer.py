"""
Template rendering for Matugen compatibility.

This module provides the TemplateRenderer class for processing template files
using the {{colors.name.mode.format}} syntax compatible with Matugen.

Supports pipe filters: {{ colors.primary.dark.hex | set_alpha 0.5 | grayscale }}
"""

import re
import sys
from pathlib import Path
from typing import Optional

try:
    import tomllib
except ImportError:
    tomllib = None

from .color import Color, find_closest_color


class TemplateRenderer:
    """
    Renders templates using the generated theme colors.
    Compatible with Matugen-style {{colors.name.mode.format}} tags.

    Supports filters via pipe syntax:
        {{ colors.primary.dark.hex | grayscale }}
        {{ colors.primary.dark.rgba | set_alpha 0.5 }}

    Theme data uses snake_case keys (e.g., 'primary', 'surface_container').
    """

    # Aliases for custom/legacy keys
    COLOR_ALIASES = {
        "hover": "surface_container_high",
        "on_hover": "on_surface",
    }

    # Supported filters and their argument requirements
    SUPPORTED_FILTERS = {
        # No arguments
        "grayscale": 0,
        "invert": 0,
        # One argument (float)
        "set_alpha": 1,
        "set_lightness": 1,
        "set_hue": 1,
        "set_saturation": 1,
        "lighten": 1,
        "darken": 1,
        "saturate": 1,
        "desaturate": 1,
    }

    def __init__(self, theme_data: dict[str, dict[str, str]], verbose: bool = True):
        self.theme_data = theme_data
        self.verbose = verbose
        self._current_file: Optional[str] = None
        self._error_count = 0

    def _log_error(self, message: str, line_hint: str = ""):
        """Log an error to stderr."""
        self._error_count += 1
        prefix = f"[{self._current_file}] " if self._current_file else ""
        hint = f" near '{line_hint}'" if line_hint else ""
        print(f"Template error: {prefix}{message}{hint}", file=sys.stderr)

    def _log_warning(self, message: str):
        """Log a warning to stderr."""
        if self.verbose:
            prefix = f"[{self._current_file}] " if self._current_file else ""
            print(f"Template warning: {prefix}{message}", file=sys.stderr)

    def _get_hex_color(self, color_name: str, mode: str) -> Optional[str]:
        """Get raw hex color value for a color name and mode."""
        key = self.COLOR_ALIASES.get(color_name, color_name)

        if mode == "default":
            mode_data = self.theme_data.get("dark") or self.theme_data.get("light")
        else:
            mode_data = self.theme_data.get(mode)

        if not mode_data:
            self._log_error(f"Unknown mode '{mode}'", f"colors.{color_name}.{mode}")
            return None

        hex_color = mode_data.get(key)
        if not hex_color:
            self._log_error(f"Unknown color '{key}'", f"colors.{color_name}.{mode}")
            return None

        return hex_color

    def _format_color(self, color: Color, format_type: str) -> str:
        """Format a Color object to the requested format string."""
        if format_type == "hex":
            return color.to_hex()
        elif format_type == "hex_stripped":
            return color.to_hex().lstrip('#')
        elif format_type == "rgb":
            return f"rgb({color.r}, {color.g}, {color.b})"
        elif format_type == "rgba":
            alpha = getattr(color, 'alpha', 1.0)
            return f"rgba({color.r}, {color.g}, {color.b}, {alpha})"
        elif format_type == "hsl":
            h, s, l = color.to_hsl()
            return f"hsl({int(h)}, {int(s * 100)}%, {int(l * 100)}%)"
        elif format_type == "hsla":
            h, s, l = color.to_hsl()
            alpha = getattr(color, 'alpha', 1.0)
            return f"hsla({int(h)}, {int(s * 100)}%, {int(l * 100)}%, {alpha})"
        elif format_type == "hue":
            h, _, _ = color.to_hsl()
            return str(int(h))
        elif format_type == "saturation":
            _, s, _ = color.to_hsl()
            return str(int(s * 100))
        elif format_type == "lightness":
            _, _, l = color.to_hsl()
            return str(int(l * 100))
        elif format_type == "red":
            return str(color.r)
        elif format_type == "green":
            return str(color.g)
        elif format_type == "blue":
            return str(color.b)
        elif format_type == "alpha":
            return str(getattr(color, 'alpha', 1.0))
        else:
            self._log_error(f"Unknown format '{format_type}'")
            return color.to_hex()

    def _parse_filter(self, filter_str: str) -> tuple[str, Optional[str]]:
        """Parse a filter string into (name, argument).

        Uses matugen syntax (space-separated): | set_alpha 0.5
        """
        filter_str = filter_str.strip()
        if ' ' in filter_str:
            name, arg = filter_str.split(None, 1)
            return name.strip(), arg.strip()
        return filter_str, None

    def _apply_filter(self, color: Color, filter_name: str, arg: Optional[str], raw_expr: str) -> Color:
        """Apply a single filter to a color."""
        if filter_name not in self.SUPPORTED_FILTERS:
            supported = ", ".join(sorted(self.SUPPORTED_FILTERS.keys()))
            self._log_error(f"Unknown filter '{filter_name}'. Supported: {supported}", raw_expr)
            return color

        expected_args = self.SUPPORTED_FILTERS[filter_name]

        # Validate argument presence
        if expected_args > 0 and arg is None:
            self._log_error(f"Filter '{filter_name}' requires an argument", raw_expr)
            return color
        if expected_args == 0 and arg is not None:
            self._log_warning(f"Filter '{filter_name}' ignores argument '{arg}'")

        # Parse numeric argument if needed
        num_arg = None
        if expected_args > 0:
            try:
                num_arg = float(arg)
            except (ValueError, TypeError):
                self._log_error(f"Filter '{filter_name}' requires numeric argument, got '{arg}'", raw_expr)
                return color

        # Apply the filter
        h, s, l = color.to_hsl()

        if filter_name == "grayscale":
            # Luminance-based grayscale
            gray = int(0.299 * color.r + 0.587 * color.g + 0.114 * color.b)
            result = Color(gray, gray, gray)

        elif filter_name == "invert":
            result = Color(255 - color.r, 255 - color.g, 255 - color.b)

        elif filter_name == "set_alpha":
            result = Color(color.r, color.g, color.b)
            result.alpha = max(0.0, min(1.0, num_arg))

        elif filter_name == "set_lightness":
            # Argument is 0-100
            new_l = max(0.0, min(1.0, num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)

        elif filter_name == "set_hue":
            # Argument is 0-360
            new_h = num_arg % 360
            result = Color.from_hsl(new_h, s, l)

        elif filter_name == "set_saturation":
            # Argument is 0-100
            new_s = max(0.0, min(1.0, num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)

        elif filter_name == "lighten":
            # Increase lightness by percentage points
            new_l = max(0.0, min(1.0, l + num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)

        elif filter_name == "darken":
            # Decrease lightness by percentage points
            new_l = max(0.0, min(1.0, l - num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)

        elif filter_name == "saturate":
            # Increase saturation by percentage points
            new_s = max(0.0, min(1.0, s + num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)

        elif filter_name == "desaturate":
            # Decrease saturation by percentage points
            new_s = max(0.0, min(1.0, s - num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)

        else:
            result = color

        # Preserve alpha if set
        if hasattr(color, 'alpha') and not hasattr(result, 'alpha'):
            result.alpha = color.alpha

        return result

    def _process_expression(self, expr: str) -> str:
        """Process a full template expression like 'colors.primary.dark.hex | filter1 | filter2: arg'."""
        # Split by pipe, keeping track of the base and filters
        parts = [p.strip() for p in expr.split('|')]

        if not parts:
            self._log_error("Empty expression", expr)
            return f"{{{{{expr}}}}}"

        # Parse the base: colors.name.mode.format
        base = parts[0]
        base_match = re.match(r'^colors\.([a-z_0-9]+)\.([a-z_0-9]+)\.([a-z_0-9]+)$', base)

        if not base_match:
            self._log_error(f"Invalid syntax '{base}'. Expected: colors.<name>.<mode>.<format>", expr)
            return f"{{{{{expr}}}}}"

        color_name, mode, format_type = base_match.groups()

        # Get the hex color
        hex_color = self._get_hex_color(color_name, mode)
        if not hex_color:
            return f"{{{{UNKNOWN:{color_name}.{mode}}}}}"

        # Start with the color
        color = Color.from_hex(hex_color)

        # Apply filters if any
        filters = parts[1:]
        for filter_str in filters:
            filter_name, arg = self._parse_filter(filter_str)
            if filter_name:
                color = self._apply_filter(color, filter_name, arg, expr)

        # Format the final color
        return self._format_color(color, format_type)

    def render(self, template_text: str) -> str:
        """Replace all tags in template text."""
        self._error_count = 0

        # Pattern matches {{ ... }} with any content inside
        # We'll parse the content ourselves for better error reporting
        pattern = r"\{\{\s*([^}]+?)\s*\}\}"

        def replace(match):
            expr = match.group(1).strip()

            # Check if it starts with 'colors.'
            if not expr.startswith('colors.'):
                # Not a color expression - could be other template syntax
                # Return as-is for now (or could log warning)
                return match.group(0)

            return self._process_expression(expr)

        result = re.sub(pattern, replace, template_text)

        # Process escape sequences (matugen-compatible)
        # \\ in template becomes \ in output
        result = result.replace('\\\\', '\\')

        if self._error_count > 0:
            print(f"Template rendering completed with {self._error_count} error(s)", file=sys.stderr)

        return result

    def render_file(self, input_path: Path, output_path: Path) -> bool:
        """Render a template file to an output path.

        Returns True if successful, False if skipped due to errors.
        """
        self._current_file = str(input_path)
        success = False
        try:
            template_text = input_path.read_text()
            rendered_text = self.render(template_text)

            # Skip writing if there were errors (keeps previous working version)
            if self._error_count > 0:
                print(f"Skipping {output_path}: template has {self._error_count} error(s)", file=sys.stderr)
            else:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(rendered_text)
                success = True
        except FileNotFoundError:
            self._log_error(f"Template file not found: {input_path}")
        except PermissionError:
            self._log_error(f"Permission denied: {output_path}")
        except Exception as e:
            self._log_error(f"Unexpected error: {e}")
        finally:
            self._current_file = None
        return success

    def _substitute_closest_color(self, text: str, closest_color: str) -> str:
        """Substitute {{closest_color}} in text."""
        return re.sub(r"\{\{\s*closest_color\s*\}\}", closest_color, text)

    def process_config_file(self, config_path: Path):
        """Process Matugen TOML configuration file."""
        if not tomllib:
            print("Error: tomllib module not available (requires Python 3.11+)", file=sys.stderr)
            return

        try:
            with open(config_path, "rb") as f:
                data = tomllib.load(f)

            templates = data.get("templates", {})
            for name, template in templates.items():
                input_path = template.get("input_path")
                output_path = template.get("output_path")

                if not input_path or not output_path:
                    print(f"Warning: Template '{name}' missing input_path or output_path", file=sys.stderr)
                    continue

                self.render_file(Path(input_path).expanduser(), Path(output_path).expanduser())

                # Handle closest_color if configured (matugen-compatible)
                closest_color_value = ""
                colors_to_compare = template.get("colors_to_compare")
                compare_to = template.get("compare_to")

                if colors_to_compare and compare_to:
                    # Render compare_to to get the actual hex color
                    rendered_compare_to = self.render(compare_to)
                    # Find the closest color name
                    closest_color_value = find_closest_color(rendered_compare_to, colors_to_compare)

                # Execute pre_hook if specified
                pre_hook = template.get("pre_hook")
                if pre_hook:
                    import subprocess
                    # Substitute closest_color first, then render color variables
                    if closest_color_value:
                        pre_hook = self._substitute_closest_color(pre_hook, closest_color_value)
                    pre_hook = self.render(pre_hook)
                    try:
                        subprocess.run(pre_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running pre_hook for {name}: {e}", file=sys.stderr)

                # Execute post_hook if specified
                post_hook = template.get("post_hook")
                if post_hook:
                    import subprocess
                    # Substitute closest_color first, then render color variables
                    if closest_color_value:
                        post_hook = self._substitute_closest_color(post_hook, closest_color_value)
                    post_hook = self.render(post_hook)
                    try:
                        subprocess.run(post_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running post_hook for {name}: {e}", file=sys.stderr)

        except FileNotFoundError:
            print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        except Exception as e:
            print(f"Error processing config file {config_path}: {e}", file=sys.stderr)
