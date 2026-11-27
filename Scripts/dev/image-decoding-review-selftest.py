#!/usr/bin/env python3
"""Negative controls for independent result review and real guest job leases."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
from types import SimpleNamespace

from guest_profile import activate_profile, profile_argument
from image_decoding_bus import private_bus
from image_decoding_fixtures import COLORS, colored_png
from image_decoding_jobs import linger_lease
from image_decoding_review import endpoint as review_endpoint, inspect, packages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    out = args.output
    if out != out.resolve() or out.exists() or not out.is_relative_to(profile.journal_base):
        raise ValueError('Fresh canonical guest evidence directory required')
    out.mkdir()
    expected = dict(source='source-pin', plugins='plugins-pin')
    fixture = out / 'fixture'
    fixture.mkdir()
    endpoint = fixture / 'owner'
    endpoint.mkdir()
    consumer = dict(formats=[dict(name='Still.webp', consumer=dict(state='ready'))], raw=3,
                    motion=dict(state='ready', frameCount=3, result=dict(frames=3, format='webp')),
                    retired=[dict(state='idle', status=0, url='') for _ in range(11)])
    report = dict(inputs=expected, state='complete', qtWebp='absent', case='owner', cases=[dict(id='required', result='PASS')])
    (fixture / 'result.json').write_text(json.dumps(report))
    (endpoint / 'consumer.json').write_text(json.dumps(consumer))
    (endpoint / 'process.json').write_text(json.dumps(dict(exit=0, imagePlugins=[])))
    grabs = []
    for name, color in [('format-0', COLORS[0]), *[('motion-' + str(i), color) for i, color in enumerate(COLORS)]]:
        (endpoint / (name + '.png')).write_bytes(colored_png(color))
        grabs.append(dict(name=name, saved=True))
    (endpoint / 'qt.log').write_text('IMAGE_BASELINE|' + json.dumps(consumer) + '\n' + ''.join('IMAGE_GRAB|' + json.dumps(r) + '\n' for r in grabs))
    locker = fixture / 'owner-locker'
    shutil.copytree(endpoint, locker)
    checks = []

    def check(name, action, refused=False):
        try:
            action()
        except (AssertionError, OSError, KeyError) as error:
            if not refused:
                raise
            detail = str(error)
        else:
            if refused:
                raise AssertionError('Invalid evidence was accepted: ' + name)
            detail = 'accepted'
        checks.append(dict(id=name, detail=detail))
        print('CASE ' + name + ': PASS', flush=True)

    check('review-valid-independent-endpoint', lambda: inspect(fixture, ['required'], expected, 'absent'))
    (locker / 'consumer.json').rename(locker / 'consumer.missing')
    check('review-rejects-missing-owner-locker', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (locker / 'consumer.missing').rename(locker / 'consumer.json')
    log_text = (endpoint / 'qt.log').read_text()
    for key in ('motion', 'formats', 'retired'):
        incomplete = {name: value for name, value in consumer.items() if name != key}
        (endpoint / 'consumer.json').write_text(json.dumps(incomplete))
        (endpoint / 'qt.log').write_text(log_text.replace(json.dumps(consumer), json.dumps(incomplete)))
        check('review-rejects-owner-without-' + key, lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    for label, retired in (
        ('short', consumer['retired'][:-1]),
        ('malformed', [None, *consumer['retired'][1:]]),
        ('live', [dict(state='ready', status=1, url='file:///still.webp'), *consumer['retired'][1:]]),
    ):
        incomplete = dict(consumer, retired=retired)
        (endpoint / 'consumer.json').write_text(json.dumps(incomplete))
        (endpoint / 'qt.log').write_text(log_text.replace(json.dumps(consumer), json.dumps(incomplete)))
        check('review-rejects-' + label + '-retirement', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (endpoint / 'consumer.json').write_text(json.dumps(consumer))
    (endpoint / 'qt.log').write_text(log_text.replace('"name": "format-0"', '"name": "format-0.png"'))
    check('review-accepts-exact-filename-schema', lambda: inspect(fixture, ['required'], expected, 'absent'))
    (endpoint / 'format-0.png.png').write_bytes(colored_png(COLORS[0]))
    check('review-rejects-ambiguous-filename-and-stem', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (endpoint / 'format-0.png.png').unlink()
    (endpoint / 'qt.log').write_text(log_text)
    unnamed = out / 'unnamed'
    unnamed.mkdir()
    (unnamed / 'consumer.json').write_text('{}')
    (unnamed / 'process.json').write_text(json.dumps(dict(exit=0, imagePlugins=[])))
    (unnamed / 'qt.log').write_text('IMAGE_BASELINE|{}\nIMAGE_GRAB|{"saved":true}\n')
    (unnamed / 'scan.png').write_bytes(colored_png(COLORS[0]))
    check('review-accepts-unique-unnamed-frame', lambda: review_endpoint(unnamed, 'present'))
    (unnamed / 'other.png').write_bytes(colored_png(COLORS[1]))
    check('review-rejects-ambiguous-unnamed-frame', lambda: review_endpoint(unnamed, 'present'), True)
    check('review-rejects-missing-case-id', lambda: inspect(fixture, ['required', 'omitted'], expected, 'absent'), True)
    check('review-rejects-stale-tree', lambda: inspect(fixture, ['required'], dict(expected, source='stale'), 'absent'), True)
    check('review-rejects-wrong-lane', lambda: inspect(fixture, ['required'], expected, 'present'), True)
    original = (endpoint / 'motion-1.png').read_bytes()
    (endpoint / 'motion-1.png').write_bytes(colored_png(COLORS[0]))
    check('review-rejects-false-animation-pixels', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (endpoint / 'motion-1.png').write_bytes(original[:-10])
    check('review-rejects-truncated-frame', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (endpoint / 'motion-1.png').write_bytes(original)
    (endpoint / 'consumer.json').write_text(json.dumps(dict(consumer, raw=1)))
    check('review-rejects-rewritten-consumer', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    (endpoint / 'consumer.json').write_text(json.dumps(consumer))
    (endpoint / 'process.json').write_text(json.dumps(dict(exit=0, imagePlugins=['/foreign/libqwebp.so'])))
    check('review-rejects-fake-codec-absence', lambda: inspect(fixture, ['required'], expected, 'absent'), True)
    check('review-rejects-missing-package-receipts', lambda: packages(fixture), True)
    spec = importlib.util.spec_from_file_location('driver', Path(__file__).with_name('image-decoding-regression.py'))
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    probe = driver.Run.__new__(driver.Run)
    probe.profile = profile
    probe.work = profile.work_base / ('long-aggregate-' * 20)
    address = probe.private_bus_address()
    with private_bus(profile, out, address=address) as observed:
        check('nested-aggregate-uses-owned-short-private-bus', lambda: ensure(observed.startswith(address)
              and Path(address.removeprefix('unix:path=')).is_relative_to(profile.runtime_base)))
    lease_root = out / 'lease'
    lease_root.mkdir()
    lease_profile = SimpleNamespace(home=profile.home, journal_base=lease_root, uid=profile.uid)
    original = subprocess.run(['loginctl', 'show-user', str(profile.uid), '-p', 'Linger', '--value'],
                              capture_output=True, text=True, check=True).stdout.strip()
    units = [('image-decoding-review-a', out / 'a'), ('image-decoding-review-b', out / 'b')]
    acquired = []
    try:
        for unit, control in units:
            linger_lease(lease_profile, unit, control, True)
            acquired.append((unit, control))
        linger_lease(lease_profile, *acquired.pop(0), False)
        current = subprocess.run(['loginctl', 'show-user', str(profile.uid), '-p', 'Linger', '--value'],
                                 capture_output=True, text=True, check=True).stdout.strip()
        check('job-lease-retains-other-owned-job', lambda: ensure(current == 'yes'))
    finally:
        for unit, control in acquired:
            linger_lease(lease_profile, unit, control, False)
    current = subprocess.run(['loginctl', 'show-user', str(profile.uid), '-p', 'Linger', '--value'],
                             capture_output=True, text=True, check=True).stdout.strip()
    check('job-final-lease-restores-original-linger', lambda: ensure(current == original))
    (out / 'result.json').write_text(json.dumps(dict(checks=checks, originalLinger=original, finalLinger=current), indent=2) + '\n')
    shutil.rmtree(fixture)
    shutil.rmtree(unnamed)


def ensure(condition):
    if not condition:
        raise AssertionError('Lease contract failed')


if __name__ == '__main__':
    main()
