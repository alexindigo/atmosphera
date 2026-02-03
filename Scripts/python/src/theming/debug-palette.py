#!/usr/bin/env python3
"""
Debug script to trace color extraction divergence between machines.
Run this on both machines with the same image and compare outputs.

Usage: python3 debug-palette.py /path/to/image.png
"""

import hashlib
import json
import sys
from pathlib import Path

from lib import read_image, ImageReadError
from lib.color import rgb_to_lab
from lib.palette import downsample_pixels, kmeans_cluster, _score_colors_count, _hue_to_family
from lib.hct import Hct
from lib.color import Color

def hash_data(data: list) -> str:
    """Create a short hash of list data for comparison."""
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:16]

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 debug-palette.py /path/to/image.png")
        sys.exit(1)

    image_path = Path(sys.argv[1])

    print(f"=== Debug Palette Extraction ===")
    print(f"Image: {image_path}")
    print(f"Python: {sys.version}")
    print()

    # Step 1: Read image
    try:
        pixels = read_image(image_path)
    except ImageReadError as e:
        print(f"Error reading image: {e}")
        sys.exit(1)

    print(f"1. Raw pixels: {len(pixels)} pixels")
    print(f"   First 5: {pixels[:5]}")
    print(f"   Hash: {hash_data(pixels[:1000])}")  # Hash first 1000 for speed
    print()

    # Step 2: Downsample
    sampled = downsample_pixels(pixels, factor=4)
    print(f"2. Downsampled: {len(sampled)} pixels")
    print(f"   First 5: {sampled[:5]}")
    print(f"   Hash: {hash_data(sampled)}")
    print()

    # Step 3: Convert to Lab
    colors_lab = [rgb_to_lab(*c) for c in sampled]
    print(f"3. Lab conversion:")
    print(f"   First 5: {[tuple(round(v, 6) for v in lab) for lab in colors_lab[:5]]}")
    # Round for hash to avoid float repr issues
    lab_rounded = [[round(v, 10) for v in lab] for lab in colors_lab]
    print(f"   Hash: {hash_data(lab_rounded)}")
    print()

    # Step 4: Sort by lightness (this is what k-means init does)
    sorted_indices = sorted(range(len(colors_lab)), key=lambda i: colors_lab[i][0])
    print(f"4. Sorted indices (by L):")
    print(f"   First 10: {sorted_indices[:10]}")
    print(f"   Hash: {hash_data(sorted_indices)}")
    print()

    # Step 5: K-means clustering (48 clusters for "count" mode)
    clusters = kmeans_cluster(sampled, k=48)
    print(f"5. K-means clusters: {len(clusters)} clusters")
    print(f"   Top 5 by size:")
    for i, (centroid, representative, count) in enumerate(clusters[:5]):
        print(f"     {i+1}. centroid={centroid}, repr={representative}, count={count}")

    # Hash cluster data
    cluster_data = [(list(c), list(r), n) for c, r, n in clusters]
    print(f"   Hash: {hash_data(cluster_data)}")
    print()

    # Step 6: Score colors (count mode = faithful)
    colors_for_scoring = [(c[1], c[2]) for c in clusters]  # (representative, count)
    scored = _score_colors_count(colors_for_scoring)
    print(f"6. Scored colors (count/faithful mode):")
    for i, (color, score) in enumerate(scored[:5]):
        hct = color.to_hct()
        family = _hue_to_family(hct.hue)
        family_names = ["RED", "ORANGE", "YELLOW", "GREEN", "BLUE", "PURPLE"]
        print(f"     {i+1}. {color.to_hex()} score={score:.0f} hue={hct.hue:.1f} chroma={hct.chroma:.1f} family={family_names[family]}")
    print()

    # Final result
    print(f"=== Final Primary Color ===")
    if scored:
        primary = scored[0][0]
        print(f"Primary: {primary.to_hex()}")
        hct = primary.to_hct()
        print(f"HCT: hue={hct.hue:.2f}, chroma={hct.chroma:.2f}, tone={hct.tone:.2f}")

    print()
    print("Compare the hashes between machines to find where divergence starts.")

if __name__ == "__main__":
    main()
