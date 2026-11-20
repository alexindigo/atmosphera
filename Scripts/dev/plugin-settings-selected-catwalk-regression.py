#!/usr/bin/env python3
"""Selected Catwalk configuration at actual Bar/Desktop consumers, VM only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    injector = Path(os.environ['PHA_INPUT_INJECTOR']).resolve()
    if not injector.is_relative_to(profile.work_base) or not injector.is_file():
        parser.error('task-owned input injector required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        shutil.copytree(args.plugins / 'catwalk', case / 'config/plugins/catwalk')
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/catwalk.json'
        runner.write_json(shared, dict(minimumThreshold=10, hideBackground=False, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-catwalk.qml'
        try:
            text = runner.run_fixture(profile, install, case, out, fixture)
        finally:
            (case / 'config/settings').chmod(0o700)
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        if 'CATWALK_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('selected Catwalk runtime endpoint failed')
        rows = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left']
        if rows != [dict(id='plugin:catwalk', instanceSettings=dict(opaque=dict(keep=True))),
                    dict(id='plugin:catwalk', instanceSettings=dict(minimumThreshold=20, hideBackground=True))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(PHA_CATWALK_COLD='1'))
        if 'CATWALK_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Catwalk consumer failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((args.plugins / 'catwalk').glob('*.qml'))}
        runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, actualBarDesktop=True,
            controlledCpuSample=15, oneClientPerContext=True, genuineKeyboardSlider=True,
            nativeApplyAndReset=True, sharedAndSiblingUnchanged=True, separateColdConsumer=True,
            realIoFailureRetry=True, failedCloseRetainsPage=True, signalBeforeCallback=True, ownerRetiresClients=True,
            physicalCpuSamplingNotCertified=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('CATWALK_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
