"""
Palette extraction using K-means clustering.

This module provides functions for extracting dominant colors from images
using perceptual color distance calculations and k-means clustering.
"""

import math

from .color import Color, rgb_to_hsl, hsl_to_rgb, hue_distance
from .hct import Cam16, Hct

# Type aliases
RGB = tuple[int, int, int]
HSL = tuple[float, float, float]


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
                # Circular mean for hue (hue is 0-360, wraps around)
                sin_sum = sum(math.sin(math.radians(c[0])) for c in cluster)
                cos_sum = sum(math.cos(math.radians(c[0])) for c in cluster)
                avg_h = math.degrees(math.atan2(sin_sum, cos_sum)) % 360
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
