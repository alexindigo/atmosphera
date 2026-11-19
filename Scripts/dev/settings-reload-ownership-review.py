#!/usr/bin/env python3
"""Actual FileView completion/reentry and full-scan receipt ownership controls."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile
from presentation_harness import run_harness
from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--case', default='all')
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    profile = activate_profile(Path('/home/tester/Projects/atcq/tools/ark/guest-profiles/atmosphera-configqml-settings.json'))
    if profile.uuid != '12f17a02-25e9-474c-9dae-fea092c2d2be':
        raise RuntimeError('assigned guest required')
    output.mkdir(parents=True, exist_ok=False)
    # Complete snapshots bypass the legacy normalizer subprocess, preserving the
    # actual FileView onLoaded reentry boundary rather than an asynchronous proxy.
    keys = ('mPrimary mOnPrimary mSecondary mOnSecondary mTertiary mOnTertiary '
            'mStandout mOnStandout mError mOnError mSurface mOnSurface mSurfaceVariant '
            'mOnSurfaceVariant mOutline mShadow mHover mOnHover').split()
    def colors(primary):
        return {mode: {key: primary if key == 'mPrimary' else '#223344' for key in keys}
                for mode in ('dark', 'light')}
    rows = []
    cases = ('colors-live', 'colors-reentry', 'registry-live', 'registry-invalid', 'registry-missing', 'registry-write')
    if args.case != 'all' and args.case not in cases:
        raise ValueError('unknown case')
    for case in cases if args.case == 'all' else (args.case,):
        work = output / case
        config = work / 'c'
        plugin = config / 'plugins/example'
        plugin.mkdir(parents=True)
        (config / 'settings.json').write_text('{"settingsVersion":62,"general":{"animationDisabled":true}}')
        (config / 'plugins.json').write_text(json.dumps(dict(version=6, sources=[], states={'original': {'enabled': False, 'sourceUrl': None}})))
        (plugin / 'manifest.json').write_text(json.dumps(dict(id='example', name='Example', version='1.0.0',
            author='Regression fixture', description='Read ownership', entryPoints={})))
        (config / 'colors.json').write_text(json.dumps(colors('#654321')))
        runtime = profile.child_environment('ro-')
        env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
                   ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
                   ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(work / 'state'),
                   RELOAD_REVIEW_CASE=case, RELOAD_REVIEW_PALETTE=json.dumps(colors('#123456')))
        execution = None
        try:
            with closing(ProbeFiles(source, Path(__file__).parent / 'fixtures/settings-reload-ownership.qml')) as probes:
                live = work / 'execution'
                live.mkdir()
                execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(probes.probe), '--no-color'], live, env, 15)
                log = (live / 'shell.log').read_text()
                passed = execution['exit_code'] == 0 and execution['cleanup_complete'] and not execution['timed_out'] and (
                    'RELOAD_REVIEW: PASS ' + case in log) and not any(token in log for token in (
                    'TypeError:', 'ReferenceError:', 'SyntaxError:', 'RELOAD_REVIEW_ASSERT:', 'Failed to load configuration'))
        finally:
            if execution and execution['cleanup_complete']:
                shutil.rmtree(runtime['XDG_RUNTIME_DIR'])
        rows.append(dict(id=case, status='PASS' if passed else 'FAIL', execution=execution))
        print(json.dumps(rows[-1]), flush=True)
    (output / 'result.json').write_text(json.dumps(rows, indent=2) + '\n')
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
