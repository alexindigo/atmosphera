#!/usr/bin/env python3
"""
Compare Noctalia's template-processor color extraction with matugen.

Usage:
    ./compare-matugen.py <wallpaper_path>
    ./compare-matugen.py ~/Pictures/Wallpapers/example.png

Compares all M3 schemes (tonal-spot, fruit-salad, rainbow) and shows
a table with hue differences.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Add the theming lib to path
SCRIPT_DIR = Path(__file__).parent.resolve()
THEMING_DIR = SCRIPT_DIR.parent / "python" / "src" / "theming"
sys.path.insert(0, str(THEMING_DIR))

from lib.color import Color
from lib.hct import Hct


def hue_diff(h1: float, h2: float) -> float:
    """Calculate circular hue difference."""
    diff = abs(h1 - h2)
    return min(diff, 360.0 - diff)


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex to RGB tuple."""
    h = hex_color.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def rgb_distance(hex1: str, hex2: str) -> float:
    """Calculate Euclidean RGB distance (0-441 range)."""
    r1, g1, b1 = hex_to_rgb(hex1)
    r2, g2, b2 = hex_to_rgb(hex2)
    return ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2) ** 0.5


def get_hct(hex_color: str) -> Hct:
    """Convert hex color to HCT."""
    return Color.from_hex(hex_color).to_hct()


def run_our_processor(image_path: Path, scheme: str) -> dict | None:
    """Run our template-processor and return colors."""
    cmd = [
        sys.executable,
        str(THEMING_DIR / "template-processor.py"),
        str(image_path),
        "--scheme-type", scheme,
        "--dark"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return data.get("dark", {})
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error running our processor: {e}", file=sys.stderr)
        return None


def run_matugen(image_path: Path, scheme: str) -> dict | None:
    """Run matugen and return colors."""
    matugen_scheme = f"scheme-{scheme}"
    cmd = [
        "matugen", "image", str(image_path),
        "--json", "hex",
        "--dry-run",
        "-t", matugen_scheme
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        colors = data.get("colors", {})
        # Extract dark mode values
        return {k: v.get("dark", v) for k, v in colors.items() if isinstance(v, dict)}
    except subprocess.CalledProcessError as e:
        print(f"Error running matugen: {e}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"Error parsing matugen output: {e}", file=sys.stderr)
        return None


def compare_schemes(image_path: Path) -> None:
    """Compare all M3 schemes between our processor and matugen."""
    schemes = ["tonal-spot", "fruit-salad", "rainbow"]
    color_keys = ["primary", "secondary", "tertiary", "surface", "on_surface"]

    print(f"\nComparing: {image_path.name}\n")
    print("=" * 78)

    # Header
    print(f"{'Scheme':<12} {'Color':<14} {'Ours':<10} {'Matugen':<10} {'Diff':>10}  {'Match':<10}")
    print("-" * 78)

    for scheme in schemes:
        ours = run_our_processor(image_path, scheme)
        matugen = run_matugen(image_path, scheme)

        if not ours or not matugen:
            print(f"{scheme}: Failed to get colors")
            continue

        for key in color_keys:
            our_hex = ours.get(key, "")
            mat_hex = matugen.get(key, "")

            if not our_hex or not mat_hex:
                continue

            try:
                our_hct = get_hct(our_hex)
                mat_hct = get_hct(mat_hex)
                avg_chroma = (our_hct.chroma + mat_hct.chroma) / 2

                # For low-chroma colors, use RGB distance instead of hue
                # (hue is meaningless for near-grayscale colors)
                if avg_chroma < 15:
                    rgb_dist = rgb_distance(our_hex, mat_hex)
                    # RGB distance: 0-10 excellent, 10-25 good, 25-50 fair
                    if rgb_dist < 10:
                        match = "excellent"
                    elif rgb_dist < 25:
                        match = "good"
                    elif rgb_dist < 50:
                        match = "fair"
                    else:
                        match = "poor"
                    diff_str = f"{rgb_dist:>5.1f} rgb"
                else:
                    diff = hue_diff(our_hct.hue, mat_hct.hue)
                    if diff < 5:
                        match = "excellent"
                    elif diff < 15:
                        match = "good"
                    elif diff < 30:
                        match = "fair"
                    else:
                        match = "poor"
                    diff_str = f"{diff:>5.1f} hue"

                print(f"{scheme:<12} {key:<14} {our_hex:<10} {mat_hex:<10} {diff_str:>10}  {match:<10}")
            except Exception as e:
                print(f"{scheme:<12} {key:<14} Error: {e}")

        print("-" * 78)

    # Also show source color comparison
    print("\nSource Color Extraction:")
    print("-" * 40)

    ours = run_our_processor(image_path, "tonal-spot")
    matugen = run_matugen(image_path, "tonal-spot")

    if ours and matugen:
        # Get source from primary at tone 40 (approximation)
        our_primary = ours.get("primary", "")
        mat_source = matugen.get("source_color", "")

        if our_primary and mat_source:
            our_hct = get_hct(our_primary)
            mat_hct = get_hct(mat_source)
            print(f"Our primary hue:     {our_hct.hue:.1f}°")
            print(f"Matugen source hue:  {mat_hct.hue:.1f}°")
            print(f"Difference:          {hue_diff(our_hct.hue, mat_hct.hue):.1f}°")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare Noctalia template-processor with matugen"
    )
    parser.add_argument(
        "wallpaper",
        type=Path,
        help="Path to wallpaper image"
    )

    args = parser.parse_args()

    if not args.wallpaper.exists():
        print(f"Error: File not found: {args.wallpaper}", file=sys.stderr)
        return 1

    # Check if matugen is available
    try:
        subprocess.run(["matugen", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: matugen not found. Please install matugen first.", file=sys.stderr)
        return 1

    compare_schemes(args.wallpaper)
    return 0


if __name__ == "__main__":
    sys.exit(main())
