#!/usr/bin/env python3
"""Negative calibration of retained-state acceptance, including provenance."""
import argparse
import copy
import json

from filechooser_isolation import ROOT, enter
from filechooser_leaks import KINDS, retention_acceptance


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label', required=True)
    a = p.parse_args()
    enter(runtime_seconds=180)
    output = ROOT / 'evidence' / a.label
    output.mkdir()
    base = [{'cycle': i, 'pid': 123, 'forced_gc': True, 'THP_enabled': 0, 'AnonHugePages_kib': 0,
             'js_live_bytes': 11000000, 'js_regular_live_bytes': 11000000, 'js_large_live_bytes': 0,
             'native': {'pid': 123, 'error': 0, 'exec_env_cleared': True, 'allocated_bytes': 440000000},
             'Pss_kib': 440000, 'fds': 95, 'chooser_live': {kind: 0 for kind in KINDS},
             'chooser_totals': {'created': {kind: i * 2 for kind in KINDS}, 'destroyed': {kind: i * 2 for kind in KINDS}}}
            for i in range(51)]
    cases = []
    def check(name, rows, failed=None, invalid=False):
        try:
            data = retention_acceptance(rows)
        except AssertionError:
            condition = invalid
            data = {'invalid_observation': True}
        else:
            rejected = {key for key, value in data['checks'].items() if not value}
            condition = not invalid and rejected == (set() if failed is None else {failed})
        cases.append({'case': name, 'pass': condition, 'detail': data})
        print(name, 'PASS' if condition else 'FAIL', flush=True)
        assert condition, (name, data)
    check('retained-plateau', base)
    physical = copy.deepcopy(base)
    for row in physical: row['Pss_kib'] += row['cycle'] * 512
    check('physical-page-slope-does-not-imply-retention', physical)
    for name, slope, failed in (('js-native-independent', 32 * 1024, 'post-warmup-js-live-slope'),
                                ('js-limit-equality-rejected', 16 * 1024, 'post-warmup-js-live-slope')):
        rows = copy.deepcopy(base)
        for row in rows:
            row['js_regular_live_bytes'] += row['cycle'] * slope
            row['js_live_bytes'] = row['js_regular_live_bytes']
        check(name, rows, failed)
    for name, slope in (('native-live-leak-rejected', 128 * 1024), ('native-limit-equality-rejected', 64 * 1024)):
        rows = copy.deepcopy(base)
        for row in rows: row['native']['allocated_bytes'] += row['cycle'] * slope
        check(name, rows, 'post-warmup-native-live-slope')
    decreasing = copy.deepcopy(base)
    for row in decreasing:
        row['native']['allocated_bytes'] -= row['cycle'] * 128 * 1024
        row['js_live_bytes'] -= row['cycle'] * 32 * 1024
        row['js_regular_live_bytes'] = row['js_live_bytes']
    check('decreasing-live-memory-is-not-a-leak', decreasing)
    rows = copy.deepcopy(base); rows[-1]['fds'] += 1
    check('actual-descriptor-retention-rejected', rows, 'twenty-post-warmup-descriptor-counts-flat')
    rows = copy.deepcopy(base); rows[10]['chooser_live']['held_replies'] = 1
    check('idle-owner-even-during-warmup-rejected', rows, 'all-idle-chooser-objects-released')
    rows = copy.deepcopy(base); rows[-1]['chooser_totals']['destroyed']['players'] -= 1
    check('inconsistent-lifetime-ledger-rejected', rows, 'all-idle-lifetime-totals-balanced')
    rows = copy.deepcopy(base); rows[-1]['Pss_kib'] += 32 * 1024
    check('coarse-physical-bound-still-enforced', rows, 'post-warmup-pss-coarse-span')
    rows = copy.deepcopy(base); rows[-1]['forced_gc'] = False
    check('missing-explicit-GC-cannot-pass', rows, invalid=True)
    rows = copy.deepcopy(base); rows[-1]['native']['pid'] = 999
    check('wrong-native-subject-cannot-pass', rows, invalid=True)
    rows = copy.deepcopy(base); del rows[-1]['chooser_live']['held_replies']
    check('missing-lifetime-observation-cannot-pass', rows, invalid=True)
    check('missing-cycle-cannot-pass', base[:-1], invalid=True)
    (output / 'result.json').write_text(json.dumps({'passed': True, 'cases': cases}, indent=2))


if __name__ == '__main__':
    main()
