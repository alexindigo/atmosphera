#!/usr/bin/env python3
"""Standout D1/D2/D4/D5/D6/D8 contracts; run in the assigned project VM."""

from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python/src/theming'))
from lib.color import Color, hue_distance
from lib.contrast import contrast_ratio
from lib.hct import TonalPalette
from lib.standout import (
    Selection, RYB_HCT_HUES, MIN_DISTINCT_DELTA_E, MUTED_STANDOUT_CHROMA, accent_differences, clashes,
    hct_to_ryb, indistinct_accents, matched_chroma, perceptual_difference,
    on_standout_color, ryb_complement, ryb_midpoint, ryb_to_hct, select_hue, synthesize, synthesis_details,
)
from lib.theme import generate_theme

TYPES = ('tonal-spot', 'content', 'fruit-salad', 'rainbow', 'monochrome',
         'vibrant', 'faithful', 'dysfunctional', 'muted')

# Archived pre-D8 output for source #77c2da. Preserve other-role behaviour,
# rather than inventing a universal primary contrast floor the baseline does
# not meet (normal light 3.0376:1; muted light 4.2486:1).
PRIMARY_BASELINE = {
    'tonal-spot': {'dark': ('#59d5f8', '#003642'), 'light': ('#00677d', '#ffffff')},
    'content': {'dark': ('#86d1ea', '#003642'), 'light': ('#01677d', '#ffffff')},
    'fruit-salad': {'dark': ('#66dbb2', '#003829'), 'light': ('#006c51', '#ffffff')},
    'rainbow': {'dark': ('#59d5f8', '#003642'), 'light': ('#00677d', '#ffffff')},
    'monochrome': {'dark': ('#ffffff', '#1b1b1b'), 'light': ('#000000', '#e2e2e2')},
    'vibrant': {'dark': ('#6cc8e5', '#182225'), 'light': ('#229cc3', '#f9fafa')},
    'faithful': {'dark': ('#6cc8e5', '#182225'), 'light': ('#229cc3', '#f9fafa')},
    'dysfunctional': {'dark': ('#6cc8e5', '#182225'), 'light': ('#229cc3', '#f9fafa')},
    'muted': {'dark': ('#9cafb5', '#1c2022'), 'light': ('#627c84', '#fafafa')},
}


class StandoutTests(unittest.TestCase):
    def test_ryb_midpoint_shorter_arc_weight_and_rotation(self):
        for primary, tertiary, weight, expected in (
            (350, 20, 2, 0), (20, 350, 2, 10), (350, 20, 1, 5),
            (20, 350, 1, 5), (30, 120, 2, 60), (120, 30, 2, 90),
            (90, 90, 2, 90), (0, 240, 2, 320)):
            for rotation in (0, 15, 90, 180, 355):
                actual = ryb_midpoint((primary + rotation) % 360,
                                      (tertiary + rotation) % 360, weight)
                self.assertLess(hue_distance(actual, (expected + rotation) % 360), 1e-9)

    def test_ryb_midpoint_rejects_undefined_inputs(self):
        with self.assertRaisesRegex(ValueError, 'antipodal'):
            ryb_midpoint(0, 180)
        for primary, tertiary, weight in ((0, 20, 0), (0, 20, -1),
                                          (float('nan'), 20, 2), (0, float('inf'), 2)):
            with self.assertRaises(ValueError):
                ryb_midpoint(primary, tertiary, weight)

    def test_ryb_anchors_roundtrip_and_artist_complements(self):
        for r, h in RYB_HCT_HUES:
            self.assertAlmostEqual(ryb_to_hct(r), h % 360)
            self.assertAlmostEqual(hct_to_ryb(h), r % 360)
        for hue in range(360):
            self.assertLess(hue_distance(ryb_to_hct(hct_to_ryb(hue)), hue), 1e-9)
            self.assertLess(hue_distance(ryb_complement(ryb_complement(hue)), hue), 1e-9)
        self.assertAlmostEqual(ryb_complement(265), 55)
        self.assertAlmostEqual(ryb_complement(315), 100)
        self.assertAlmostEqual(ryb_complement(25), 155)

    def test_normal_selection_uses_actual_accents_not_wallpaper_source(self):
        primary, tertiary = (Color.from_hex(h) for h in ('#cba6f7', '#94e2d5'))
        first = select_hue(primary, tertiary, source=Color.from_hex('#00ffff'))
        second = select_hue(primary, tertiary, source=Color.from_hex('#ff0000'))
        self.assertEqual(first, second)
        self.assertEqual(first.rule, 'dual-complement-2:1')
        changed = select_hue(primary, Color.from_hex('#ff0000'))
        self.assertGreater(hue_distance(first.hue, changed.hue), 10)

    def test_catppuccin_approved_tangerine_is_perceptually_distinct(self):
        primary, tertiary = (Color.from_hex(h) for h in ('#cba6f7', '#94e2d5'))
        roles = synthesize(primary, Color.from_hex('#1e1e2e'), 'dark', select_hue(primary, tertiary))
        self.assertEqual(roles['standout'], '#f29f1a')  # user-approved D5 review result
        tangerine, peach = Color.from_hex('#f29f1a'), Color.from_hex('#fab387')
        self.assertLess(hue_distance(tangerine.to_hct().hue, peach.to_hct().hue), 30)
        self.assertAlmostEqual(perceptual_difference(tangerine, peach), 15.199633646889, places=6)
        self.assertGreaterEqual(perceptual_difference(tangerine, peach), MIN_DISTINCT_DELTA_E)
        self.assertEqual(indistinct_accents({'secondary': perceptual_difference(tangerine, peach)}), ())

    def test_perceptual_metric_detects_neighbours_and_tone_difference(self):
        color = Color.from_hex('#f29f1a')
        neighbour = Color.from_hex('#f29e1a')
        self.assertEqual(perceptual_difference(color, color), 0)
        self.assertAlmostEqual(perceptual_difference(color, neighbour),
                               perceptual_difference(neighbour, color))
        self.assertLess(perceptual_difference(color, neighbour), 1)
        self.assertGreater(perceptual_difference(Color(0, 0, 0), Color(255, 255, 255)), 90)
        self.assertEqual(indistinct_accents({'same': 0, 'near': .38, 'boundary': 12}), ('same', 'near'))

    def test_perceptual_flags_do_not_move_colours(self):
        color = Color.from_hex('#f29f1a')
        theme = {'primary': '#f29f1a', 'secondary': '#f29e1a', 'tertiary': '#fab387'}
        before = dict(theme)
        differences = accent_differences(color, theme)
        self.assertEqual(indistinct_accents(differences), ('primary', 'secondary'))
        self.assertEqual(theme, before)
        self.assertEqual(color.to_hex(), '#f29f1a')

    def test_vibration_check_and_moderation(self):
        self.assertTrue(clashes(25, 70, 265, 60))
        self.assertTrue(clashes(265, 60, 25, 70))
        self.assertFalse(clashes(25, 70, 265, 40))
        self.assertFalse(clashes(50, 70, 220, 60))
        self.assertLessEqual(matched_chroma(Color.from_hex('#ff0000'), 265), 40)
        self.assertLess(matched_chroma(Color.from_hex('#abcbd0'), 50),
                        matched_chroma(Color.from_hex('#00afff'), 50))
        for value in (-1, float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                matched_chroma(Color.from_hex('#ff0000'), 50, value)

    def test_tones_gamut_contrast_and_highest_chroma(self):
        primary = Color.from_hex('#00677d')
        for hue in range(0, 360, 15):
            for mode, surface in (('light', '#fafafa'), ('dark', '#202020')):
                roles = synthesize(primary, Color.from_hex(surface), mode, Selection(hue, 'test'))
                color, on = (Color.from_hex(roles[k]) for k in ('standout', 'on_standout'))
                self.assertGreaterEqual(contrast_ratio(color, on), 4.5)
                self.assertFalse(clashes(primary.to_hct().hue, primary.to_hct().chroma,
                                         color.to_hct().hue, color.to_hct().chroma))
                self.assertGreaterEqual(color.to_hct().tone, 59.75)
                self.assertLessEqual(color.to_hct().tone, 75.25)
                palette = TonalPalette(hue, matched_chroma(primary, hue))
                self.assertAlmostEqual(color.to_hct().chroma,
                                       max(Color.from_hex(palette.get_hex(t)).to_hct().chroma for t in range(60, 76)))

    def test_standout_has_no_surface_contrast_floor_in_either_mode(self):
        primary = Color.from_hex('#00677d')
        selection = Selection(50, 'test')
        canonical = synthesis_details(primary, Color(0, 0, 0), 'dark', selection)
        for mode in ('dark', 'light'):
            result = synthesis_details(primary, Color.from_hex(canonical.standout), mode, selection)
            self.assertEqual(result.standout, canonical.standout)
            self.assertEqual(result.surface_contrast, 1)
            self.assertGreaterEqual(contrast_ratio(Color.from_hex(result.on_standout), Color.from_hex(result.standout)), 4.5)

    def test_on_colour_is_chosen_independently_per_mode(self):
        # Both black and white clear4.5 on this grey; mode preference can differ.
        color = Color.from_hex('#757575')
        dark, light = (on_standout_color(color, mode) for mode in ('dark', 'light'))
        self.assertNotEqual(dark, light)
        for foreground in (dark, light):
            self.assertGreaterEqual(contrast_ratio(Color.from_hex(foreground), color), 4.5)
        for color in (Color(0, 0, 0), Color(255, 255, 255)):
            for mode in ('dark', 'light'):
                self.assertGreaterEqual(contrast_ratio(Color.from_hex(on_standout_color(color, mode)), color), 4.5)

    def test_light_only_is_independent_of_call_order(self):
        palette = [Color.from_hex('#77c2da')]
        for kind in TYPES:
            first = generate_theme(palette, 'light', kind)
            dark = generate_theme(palette, 'dark', kind)
            second = generate_theme(palette, 'light', kind)
            self.assertEqual(first, second)
            self.assertEqual(first['standout'], dark['standout'])

    def test_monochrome_muted_fixed_c24_source_complement(self):
        source = Color.from_hex('#d9690d')
        self.assertEqual(MUTED_STANDOUT_CHROMA, 24)
        for kind in ('monochrome', 'muted'):
            dark = generate_theme([source], 'dark', kind)
            for mode in ('dark', 'light'):
                output = generate_theme([source], mode, kind)
                choice = select_hue(Color.from_hex(dark['primary']), Color.from_hex(dark['tertiary']),
                                    source=source, scheme_type=kind)
                self.assertEqual(choice.rule, 'source-complement')
                self.assertAlmostEqual(choice.hue, ryb_complement(source.to_hct().hue))
                expected = synthesize(Color.from_hex(dark['primary']), Color.from_hex(output['surface']),
                                      mode, choice, muted_chroma=24)
                self.assertEqual(output['standout'], expected['standout'])
                self.assertEqual(output['on_standout'], expected['on_standout'])
                self.assertEqual(output['standout'], dark['standout'])
                with self.assertRaises(TypeError):
                    generate_theme([source], mode, kind, muted_standout_chroma=8)

    def test_source_required_for_monochrome_muted(self):
        for kind in ('monochrome', 'muted'):
            with self.assertRaisesRegex(ValueError, 'requires the source'):
                select_hue(Color(255, 255, 255), Color(128, 128, 128), scheme_type=kind)

    def test_all_scheme_types_modes_and_distinctness_flags(self):
        for kind in TYPES:
            reference = generate_theme([Color.from_hex('#77c2da')], 'dark', kind)
            for mode in ('dark', 'light'):
                with self.subTest(kind=kind, mode=mode):
                    with patch('lib.standout.select_hue', wraps=select_hue) as shared_selector:
                        output = generate_theme([Color.from_hex('#77c2da')], mode, kind)
                    shared_selector.assert_called_once()
                    self.assertEqual(shared_selector.call_args.args[0].to_hex(), reference['primary'])
                    self.assertEqual(shared_selector.call_args.args[1].to_hex(), reference['tertiary'])
                    self.assertEqual(shared_selector.call_args.kwargs['scheme_type'], kind)
                    color, on, surface = (Color.from_hex(output[k]) for k in ('standout', 'on_standout', 'surface'))
                    self.assertGreaterEqual(contrast_ratio(color, on), 4.5)
                    self.assertEqual(output['standout'], reference['standout'])
                    self.assertEqual((output['primary'], output['on_primary']), PRIMARY_BASELINE[kind][mode])
                    self.assertFalse(clashes(Color.from_hex(reference['primary']).to_hct().hue,
                                             Color.from_hex(reference['primary']).to_hct().chroma,
                                             color.to_hct().hue, color.to_hct().chroma))
                    differences = accent_differences(color, output)
                    self.assertEqual(set(differences), {'primary', 'secondary', 'tertiary'})
                    if kind not in ('monochrome', 'muted'):
                        self.assertEqual(indistinct_accents(differences), ())


if __name__ == '__main__':
    unittest.main(verbosity=2)
