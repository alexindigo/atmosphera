#!/usr/bin/env python3
"""Standout contract tests; run inside the assigned project VM."""

from dataclasses import replace
from itertools import permutations
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python/src/theming'))
from lib.color import Color, hue_distance
from lib.contrast import contrast_ratio
from lib.hct import TonalPalette
from lib.quantizer import extract_image_colors, extract_source_color
from lib.standout import (
    Candidate, Selection, RYB_HCT_HUES, clashes, family_hue, family_width,
    hct_to_ryb, hue_families, image_candidates, matched_chroma, ryb_complement,
    ryb_to_hct, select_hue, supported_member, synthesize,
)
from lib.theme import generate_theme

TYPES = ('tonal-spot', 'content', 'fruit-salad', 'rainbow', 'monochrome',
         'vibrant', 'faithful', 'dysfunctional', 'muted')


def candidate(name, hue, chroma=40, population=10):
    return Candidate(name, hue, chroma, population)


def partition(groups):
    return sorted(tuple(sorted(c.hex for c in group)) for group in groups)


class StandoutTests(unittest.TestCase):
    def test_family_origin_input_order_and_span(self):
        # Straddles zero and would chain to 55 if only neighbouring gaps mattered.
        members = [candidate('a', 350), candidate('b', 5), candidate('c', 20),
                   candidate('d', 35), candidate('e', 55)]
        expected = partition(hue_families(members))
        for origin in (0, 1, 15, 29, 90, 180, 355):
            shifted = [replace(c, hue=(c.hue + origin) % 360) for c in members]
            for order in (shifted, list(reversed(shifted)), shifted[2:] + shifted[:2]):
                groups = hue_families(order)
                self.assertEqual(partition(groups), expected)
                self.assertTrue(all(family_width(g) <= 30 + 1e-9 for g in groups))
                self.assertEqual(sum(map(len, groups)), len(members))

    def test_family_boundary_chroma_and_circular_mean(self):
        groups = hue_families([candidate('a', 350, 16), candidate('b', 20, 16),
                              candidate('c', 120, 15.999), candidate('d', 180, 60, 0)])
        self.assertEqual(len(groups), 1)
        self.assertAlmostEqual(family_width(groups[0]), 30)
        self.assertLess(hue_distance(family_hue(groups[0]), 5), 1e-9)

    def test_supported_member_rejects_saturated_sliver(self):
        family = (candidate('a', 40, 30, 100), candidate('b', 50, 60, 25),
                  candidate('c', 55, 100, 24))
        self.assertEqual(supported_member(family).hex, 'b')
        for order in permutations(family):
            self.assertEqual(supported_member(order).hex, 'b')

    def test_full_image_support_not_chromatic_denominator(self):
        primary = Color.from_hex('#00677d')
        colors = (candidate('orange1', 50, 45, 10), candidate('orange2', 55, 50, 10))
        exact = select_hue(primary, colors, 1000)
        self.assertEqual(exact.rule, 'existing-colour')
        self.assertAlmostEqual(exact.share, .02)
        self.assertEqual(select_hue(primary, colors, 1001).rule, 'ryb-complement')

    def test_separation_uses_generated_primary_and_farthest_family(self):
        primary = Color.from_hex('#ffb787')
        h = primary.to_hct().hue
        for separation, rule in ((59.999, 'ryb-complement'), (60, 'existing-colour')):
            result = select_hue(primary, (candidate('a', (h + separation) % 360),), 100)
            self.assertEqual(result.rule, rule)
        result = select_hue(primary, (candidate('near', h + 80),
                                     candidate('far', (h + 170) % 360)), 100)
        self.assertEqual(result.member, 'far')

    def test_empty_and_achromatic_fallback(self):
        primary = Color.from_hex('#00677d')
        for colors in ((), (candidate('grey', 50, 2, 100),)):
            result = select_hue(primary, colors, 100)
            self.assertEqual(result.rule, 'ryb-complement')
            self.assertAlmostEqual(result.hue, ryb_complement(primary.to_hct().hue))

    def test_ryb_anchors_roundtrip_and_artist_complements(self):
        for r, h in RYB_HCT_HUES:
            self.assertAlmostEqual(ryb_to_hct(r), h % 360)
            self.assertAlmostEqual(hct_to_ryb(h), r % 360)
        for hue in range(360):
            self.assertLess(hue_distance(ryb_to_hct(hct_to_ryb(hue)), hue), 1e-9)
            self.assertLess(hue_distance(ryb_complement(ryb_complement(hue)), hue), 1e-9)
        self.assertAlmostEqual(ryb_complement(265), 55)   # blue -> orange
        self.assertAlmostEqual(ryb_complement(315), 100)  # purple -> golden yellow
        self.assertAlmostEqual(ryb_complement(25), 155)   # red -> green

    def test_vibration_check_and_moderation(self):
        self.assertTrue(clashes(25, 70, 265, 60))
        self.assertTrue(clashes(265, 60, 25, 70))
        self.assertFalse(clashes(25, 70, 265, 40))
        self.assertFalse(clashes(50, 70, 220, 60))
        primary = Color.from_hex('#ff0000')
        self.assertLessEqual(matched_chroma(primary, 265), 40)
        pale = Color.from_hex('#abcbd0')
        vivid = Color.from_hex('#00afff')
        self.assertLess(matched_chroma(pale, 50), matched_chroma(vivid, 50))
        for value in (-1, float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                matched_chroma(primary, 50, value)

    def test_tones_gamut_contrast_and_highest_chroma(self):
        primary = Color.from_hex('#00677d')
        for hue in range(0, 360, 15):
            selection = Selection(hue, 'test')
            for mode, surface in (('light', '#fafafa'), ('dark', '#202020')):
                roles = synthesize(primary, Color.from_hex(surface), mode, selection)
                color, on = (Color.from_hex(roles[k]) for k in ('standout', 'on_standout'))
                self.assertGreaterEqual(contrast_ratio(color, on), 4.5)
                self.assertGreaterEqual(contrast_ratio(color, Color.from_hex(surface)), 3)
                self.assertFalse(clashes(primary.to_hct().hue, primary.to_hct().chroma,
                                         color.to_hct().hue, color.to_hct().chroma))
                if mode == 'light':
                    self.assertAlmostEqual(color.to_hct().tone, 40, delta=.25)
                    self.assertEqual(roles['on_standout'], '#ffffff')
                else:
                    self.assertGreaterEqual(color.to_hct().tone, 59.75)
                    self.assertLessEqual(color.to_hct().tone, 75.25)
                    palette = TonalPalette(hue, matched_chroma(primary, hue))
                    maximum = max(Color.from_hex(palette.get_hex(t)).to_hct().chroma
                                  for t in range(60, 76))
                    self.assertAlmostEqual(color.to_hct().chroma, maximum)

    def test_impossible_surface_does_not_change_other_roles(self):
        with self.assertRaisesRegex(ValueError, 'surface contrast'):
            synthesize(Color.from_hex('#00677d'), Color.from_hex('#888888'),
                       'dark', Selection(50, 'test'))

    def test_monochrome_muted_source_complement_parameter(self):
        source = Color.from_hex('#d9690d')
        for kind in ('monochrome', 'muted'):
            for mode in ('dark', 'light'):
                outputs = [generate_theme([source], mode, kind, muted_standout_chroma=c)
                           for c in (8, 16, 24, 32, 40)]
                self.assertEqual(len({v['standout'] for v in outputs}), 5)
                for output in outputs:
                    choice = select_hue(Color.from_hex(output['primary']), (), 0,
                                        source=source, scheme_type=kind)
                    self.assertEqual(choice.rule, 'source-complement')
                    self.assertAlmostEqual(choice.hue, ryb_complement(source.to_hct().hue))
                stripped = [{k: v for k, v in out.items() if 'standout' not in k} for out in outputs]
                self.assertTrue(all(out == stripped[0] for out in stripped))

    def test_all_scheme_types_and_both_modes(self):
        source = Color.from_hex('#77c2da')
        orange = Candidate.from_color(Color.from_hex('#d9690d'), 300)
        for kind in TYPES:
            for mode in ('dark', 'light'):
                with self.subTest(kind=kind, mode=mode):
                    output = generate_theme([source], mode, kind,
                                            standout_candidates=(orange,), total_pixels=10000)
                    color, on, surface = (Color.from_hex(output[k]) for k in
                                          ('standout', 'on_standout', 'surface'))
                    self.assertGreaterEqual(contrast_ratio(color, on), 4.5)
                    self.assertGreaterEqual(contrast_ratio(color, surface), 3)
                    if kind not in ('monochrome', 'muted'):
                        self.assertLess(hue_distance(color.to_hct().hue, orange.hue), 2)

    def test_extraction_preserves_original_counts_and_source(self):
        pixels = [(20, 100, 200)] * 960 + [(220, 100, 20)] * 40
        source, clusters = extract_image_colors(pixels)
        self.assertEqual(source, extract_source_color(pixels))
        self.assertEqual(sum(clusters.values()), len(pixels))
        self.assertEqual(sum(c.population for c in image_candidates(clusters)), len(pixels))
        empty, clusters = extract_image_colors([])
        self.assertEqual(empty, extract_source_color([]))
        self.assertEqual(clusters, {})


if __name__ == '__main__':
    unittest.main(verbosity=2)
