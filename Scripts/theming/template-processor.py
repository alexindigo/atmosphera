#!/usr/bin/env python3
"""
Template processor - Wallpaper-based color extraction and theme generation.

A CLI tool that extracts dominant colors from wallpaper images and generates palettes with optional templating:
- Material Design 3 using HCT (Hue, Chroma, Tone) color space.
- Vibrant accent-based using HSL (Hue, Saturation, Lightness) color space.

Usage:
    python3 template-processor.py IMAGE_OR_JSON [OPTIONS]

Options:
    --default        Generate vibrant accent-based colors (default)
    --material       Generate Material Design 3 colors
    --dark           Generate dark theme only
    --light          Generate light theme only
    --both           Generate both themes (default)
    -o, --output     Write JSON output to file (stdout if omitted)
    -r, --render     Render a template (input_path:output_path)
    -c, --config     Path to Matugen TOML configuration file
    --mode           Override theme mode: dark or light (Matugen compat)
    -t, --type       Scheme type (ignored, Matugen compat)

Input:
    Can be an image file (PNG/JPG) or a JSON color palette file.

Example:
    python3 template-processor.py ~/wallpaper.png --material --both
    python3 template-processor.py ~/wallpaper.jpg --dark -o theme.json
    python3 template-processor.py ~/wallpaper.png -r template.txt:output.txt
    python3 template-processor.py ~/wallpaper.png -c ~/.config/matugen/config.toml

Author: Noctalia Team
License: MIT
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Import from lib package
from lib import read_image, ImageReadError, extract_palette, generate_theme, TemplateRenderer


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog='template-processor',
        description='Extract color palettes from wallpapers and generate themes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 template-processor.py wallpaper.png                          # default mode, both themes
  python3 template-processor.py wallpaper.png --material --dark        # material mode, dark only
  python3 template-processor.py wallpaper.jpg --dark -o theme.json     # output to file
  python3 template-processor.py wallpaper.png -r tpl.txt:out.txt       # render template
        """
    )

    parser.add_argument(
        'image',
        type=Path,
        help='Path to wallpaper image (PNG/JPG) or JSON color palette'
    )

    # Theme style (mutually exclusive)
    style_group = parser.add_mutually_exclusive_group()
    style_group.add_argument(
        '--material',
        action='store_true',
        help='Generate Material Design 3 colors'
    )
    style_group.add_argument(
        '--default',
        action='store_true',
        default=True,
        help='Generate vibrant accent-based palette (default)'
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
    use_material = args.material

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
