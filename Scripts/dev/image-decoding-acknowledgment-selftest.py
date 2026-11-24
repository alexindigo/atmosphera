#!/usr/bin/env python3
"""Exercise the actual desktop assertion against authored event/pixel receipts."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace
from unittest.mock import patch

from guest_profile import activate_profile, profile_argument
from image_decoding_fixtures import COLORS, colored_png


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    assert args.output == args.output.resolve() and args.output.is_relative_to(profile.journal_base)
    args.output.mkdir(mode=0o700)
    spec = importlib.util.spec_from_file_location('image_regression', Path(__file__).with_name('image-decoding-regression.py'))
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    transitions = ('none', 'fade', 'wipe', 'disc', 'stripes', 'pixelate', 'honeycomb')
    sample = dict(effective=dict(overviewBlur=0, overviewTint=0, transitionDuration=200),
                  snapshots=[dict(name=n, result=dict(format='png', frames=1), reason='test unavailable')
                             for n in ('valid', 'newest', 'invalid', 'solid-invalid')],
                  completions=[dict(path='/fixtures/frame-0.png', visible=True, transitioning=False) for _ in range(9)],
                  interests=0, requests=0, workerRunning=False)
    rows = []
    for variant in ('valid', 'invisible-with-valid-pixels', 'unknown-without-captures', 'known-without-captures', 'transitioning'):
        output = args.output / variant
        output.mkdir()
        result = copy.deepcopy(sample)
        for endpoint in ('desktop', 'overview'):
            for name in ('valid', 'invalid', 'newest'):
                (output / (name + '-' + endpoint + '.png')).write_bytes(colored_png(COLORS[0]))
            for index, name in enumerate(transitions):
                (output / (name + '-' + endpoint + '.png')).write_bytes(colored_png(COLORS[index % 2 + 1]))
            for name in ('solid', 'solid-invalid'):
                (output / (name + '-' + endpoint + '.png')).write_bytes(colored_png((18, 52, 86, 255)))
        if variant not in ('unknown-without-captures', 'known-without-captures'):
            for index in range(9):
                (output / ('ack-' + str(index) + '.png')).write_bytes(colored_png(COLORS[0]))
        for event in result['completions']:
            if variant == 'invisible-with-valid-pixels':
                event['visible'] = False
            if variant == 'unknown-without-captures':
                event['path'] = '/fixtures/unknown-source'
            if variant == 'transitioning':
                event['transitioning'] = True
        checks = []

        def check(name, condition, detail, red=False):
            checks.append(dict(id=name, passed=bool(condition)))
            if not condition:
                raise AssertionError(name)

        run = SimpleNamespace(command=lambda *a: subprocess.CompletedProcess([], 0), check=check,
                              work=output, out=output, commands=[],
                              args=SimpleNamespace(qt_webp='present', source=Path('/source'), baseline_source=None),
                              qt=lambda *a: (result, output))
        try:
            with patch.object(regression, 'create_fixtures', return_value={}):
                regression.Run.desktop_wallpaper(run)
        except AssertionError as error:
            rejected = str(error)
        else:
            rejected = None
        expected = None if variant == 'valid' else 'desktop-wallpaper-acknowledgment-after-presented-ready'
        passed = rejected == expected
        rows.append(dict(id=variant, passed=passed, rejection=rejected, expected=expected, checks=checks))
        print('CASE ' + variant + ': ' + ('PASS' if passed else 'FAIL'), flush=True)
    profile.verify()
    (args.output / 'result.json').write_text(json.dumps(dict(passed=all(r['passed'] for r in rows), cases=rows), indent=2) + '\n')
    return 0 if all(r['passed'] for r in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
