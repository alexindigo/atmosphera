#!/usr/bin/env python3
"""Independent real-input canary for the task-owned Wayland fixture injector."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output', 'injector'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh work/output children must belong to the verified guest profile roots')
    if not args.injector.resolve().is_relative_to(profile.work_base) or not args.injector.is_file() or not os.access(args.injector, os.X_OK):
        parser.error('injector must be an executable inside the guest work root')
    profile.prepare_roots()
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        install = args.work_root / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config', 'cache', 'state'):
            (args.work_root / part).mkdir()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-host-input.qml'
        text = runner.run_fixture(profile, install, args.work_root, args.output, fixture,
                                  extra_env=dict(PHA_INPUT_INJECTOR=str(args.injector)))
        if 'PLUGIN_SETTINGS_INPUT: PASS' not in text or any(marker in text for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:')):
            raise RuntimeError('real input canary failed; inspect runtime.log')
        result = dict(status='PASS', injector=str(args.injector), sha256=hashlib.sha256(args.injector.read_bytes()).hexdigest(),
                      nativeTextField=True, nativeModalField=True, nativeButton=True, literalSlash=True,
                      shiftedPunctuationAndCase=True, namedEscape=True, namedSpace=True, controlA=True)
        stage_receipt(args.output / 'result.json', result)
        print('PLUGIN_SETTINGS_INPUT: PASS (plain/modal native fields, physical text/control keys, native Button)')


if __name__ == '__main__':
    main()
