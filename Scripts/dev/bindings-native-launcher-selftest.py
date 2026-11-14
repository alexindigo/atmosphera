#!/usr/bin/env python3
"""VM-only reviewed native captures and missing-geometry rejection controls."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, action='append', required=True)
    parser.add_argument('--footer', type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('bindings', Path(__file__).with_name('bindings-regression.py'))
    bindings = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bindings)
    checks = []
    for path in args.capture:
        pixels = subprocess.check_output(['timeout', '10', 'magick', str(path), '-depth', '8', 'rgb:-'], timeout=15)
        assert len(pixels) == 500 * 120 * 3, path
        assert bindings.native_launcher_app_signature(pixels), path
        for name, top, bottom in [('search-missing', 8, 49), ('categories-missing', 60, 100),
                                   ('layout-control-missing', 0, 60)]:
            damaged = bytearray(pixels)
            left = 460 if name == 'layout-control-missing' else 0
            for y in range(top, bottom):
                for x in range(left, 500):
                    start = (y * 500 + x) * 3
                    damaged[start:start + 3] = b'\x1e\x1e\x1e'
            assert not bindings.native_launcher_app_signature(damaged), (path, name)
        checks.append(dict(capture=str(path),positive=True,missingGeometryRejected=3))
    assert not bindings.native_launcher_app_signature(b'')
    assert not bindings.native_launcher_app_signature(bytes(500 * 120 * 3))
    footer = None
    if args.footer:
        spec = importlib.util.spec_from_file_location('deployment', Path(__file__).with_name('bindings-deployment-regression.py'))
        deployment = importlib.util.module_from_spec(spec); spec.loader.exec_module(deployment)
        pixels = subprocess.check_output(['timeout', '10', 'magick', str(args.footer), '-depth', '8', 'rgb:-'], timeout=15)
        points = deployment.Runner.wizard_local_geometry(pixels, 19, 1260)
        assert points['skip'][0] < points['reset'][0] < 204, points
        shifted = bytearray(pixels)
        for y in range(640, 741):
            start = (y * 1280 + 43) * 3
            shifted[start:(y * 1280 + 639) * 3] = b'\x1e\x1e\x1e' * (639 - 43)
            shifted[(y * 1280 + 103) * 3:(y * 1280 + 639) * 3] = pixels[start:(y * 1280 + 579) * 3]
        moved = deployment.Runner.wizard_local_geometry(shifted, 19, 1260)
        assert all(moved[k] == [points[k][0] + 60, points[k][1]] for k in points), (points, moved)
        try:
            deployment.Runner.wizard_local_geometry(bytes(1280 * 800 * 3), 19, 1260)
            raise AssertionError('blank footer accepted')
        except deployment.HarnessBlocked:
            pass
        footer = dict(points=points,translatedBy60=moved,blankRejected=True)
    print(json.dumps(dict(status='PASS',captures=checks,malformedAndBlankRejected=True,footer=footer), indent=2))


if __name__ == '__main__':
    main()
