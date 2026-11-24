#!/usr/bin/env python3
"""Guest-only catalog native-operation controls: ordinary, slow write, never ready.

Slow delays one real evidence fsync by the measured 6331 ms, then calls fsync.
Never-ready changes only a disposable fixture's observation predicate. It must
fail explicitly at the finite opening budget. Neither control patches product
code, the installed native library, or normal catalog admission.
"""
from fixture_receipts import receipt_run, stage_receipt, staged_receipt
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

from guest_profile import activate_profile, profile_argument


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--mode', choices=('ordinary', 'slow', 'never-ready'), required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent) or path.exists():
            parser.error('fresh roots must belong to the verified guest profile')
    spec = importlib.util.spec_from_file_location('catalog_budget', Path(__file__).with_name('plugin-settings-catalog-pages-regression.py'))
    catalog = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(catalog)
    original = catalog.runner.run_fixture
    shim_source = args.source / 'Scripts/dev/fixtures/plugin-settings-evidence-sync-delay.c'

    def fixture(profile, install, case, output, source, **kwargs):
        text = source.read_text()
        if args.mode == 'slow':
            shim = case / 'evidence-sync-delay.so'
            subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-o', str(shim), str(shim_source), '-ldl'], check=True)
            anchor = '  property bool started: false\n'
            assert text.count(anchor) == 1
            text = text.replace(anchor, anchor + '''  property bool delayArmed: false
  FileView {
    id: syncMarker
    path: Quickshell.env("PHA_SYNC_MARKER")
    blockWrites: true
  }
''')
            anchor = '      if (scopeName === "instance") {\n'
            assert text.count(anchor) == 1
            text = text.replace(anchor, anchor + '''        if (!delayArmed) {
          delayArmed = true;
          syncMarker.setText("armed");
        }
''')
            kwargs['extra_env'].update(LD_PRELOAD=str(shim), PHA_SYNC_MARKER=str(case / 'sync-marker'), PHA_SYNC_DELAY_MS='6331')
        elif args.mode == 'never-ready':
            anchor = 'if (!selected || !selected.settingsReady) {'
            assert text.count(anchor) == 1
            text = text.replace(anchor, 'if (true) { // test-only never-ready observation')
        target = install / source.name
        target.write_text(text)
        kwargs['installed'] = True
        return original(profile, install, case, output, target, **kwargs)

    catalog.runner.run_fixture = fixture
    sys.argv = [str(spec.origin), '--guest-profile', str(args.guest_profile), '--source', str(args.source),
                '--plugins', str(args.plugins), '--work-root', str(args.work_root), '--output', str(args.output), '--ids', 'music-search']
    code = 0
    try:
        catalog.main()
    except SystemExit as failure:
        code = failure.code
    result = staged_receipt(args.output / 'result.json')
    log = (args.output / 'runtime.log').read_text()
    instance = result['results']['music-search']['rows'].get('instance', {})
    expiry = re.search(r'CATALOG_FATAL instance api music-search:.*elapsedMs=(\d+), budgetMs=(\d+)', log)
    passed = code == 0 and result['status'] == 'PASS'
    if args.mode == 'slow':
        passed = passed and log.count('PHA_SYNC_DELAY start=') == log.count('PHA_SYNC_DELAY end=') == 1 and 6331 <= instance['instanceOpenMs'] < instance['nativeOpenBudgetMs']
    elif args.mode == 'never-ready':
        passed = code == 1 and result['status'] == 'FAIL' and expiry is not None and 15000 <= int(expiry[1]) <= 17000 and int(expiry[2]) == 15000
    report = dict(status='PASS' if passed else 'FAIL', mode=args.mode, catalogStatus=result['status'], catalogExit=code,
                  instanceOpeningMs=instance.get('instanceOpenMs'), expiryMs=int(expiry[1]) if expiry else None,
                  nativeOpenBudgetMs=15000, injectedSyncDelayMs=6331 if args.mode == 'slow' else 0,
                  shimSourceSha256=hashlib.sha256(shim_source.read_bytes()).hexdigest(),
                  interpretation='negative catalog failure is expected only for never-ready; no retries or missing-row waiver')
    stage_receipt(args.output / 'budget-control.json', report)
    print('CATALOG_OPERATION_BUDGET: ' + json.dumps(report), flush=True)
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
