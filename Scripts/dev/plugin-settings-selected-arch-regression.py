#!/usr/bin/env python3
"""P055 selected Arch Updater check client at the actual Desktop list, VM only."""
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
        for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
            (case / part).mkdir(parents=True)
        shutil.copytree(args.plugins / 'arch-updater', case / 'config/plugins/arch-updater', ignore=shutil.ignore_patterns('*.bak'))
        calls = out / 'calls.jsonl'
        check = case / 'bin/pha-check'
        # Inert read-only check endpoint; never a package manager.
        check.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                         'with open(os.environ["PHA_CALLS"], "a") as f: f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                         'if sys.argv[1:] != ["none"]: print(sys.argv[1] + "-pkg 1.0 -> 2.0")\n')
        check.chmod(0o700)
        env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_CALLS=str(calls), PHA_ARCH_CHECK=str(check))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/arch-updater.json'
        runner.write_json(shared, dict(systemCmd=str(check) + ' alpha', aurCmd=str(check) + ' none', updateCmd='false',
                                       flatpak=False, toast=False, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-arch.qml'
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
        finally:
            (case / 'config/settings').chmod(0o700)
        if 'ARCH_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('actual Arch Settings/check/Desktop endpoint failed')
        rows = json.loads((case / 'config/settings/desktopWidgets.json').read_text())['monitorWidgets'][0]['widgets']
        if rows != [dict(id='plugin:arch-updater', instanceSettings=dict(systemCmd=str(check) + ' beta')),
                    dict(id='plugin:arch-updater', instanceSettings=dict(systemCmd=str(check) + ' other'))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        if ['beta'] not in recorded:
            raise RuntimeError('selected inert check endpoint was not observed')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_ARCH_COLD='1'))
        if 'ARCH_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Arch Desktop result failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((args.plugins / 'arch-updater').glob('*.qml'))}
        runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, actualSettingsAndDesktop=True,
            inertCheckEndpoint=True, oneClientPerContext=True, genuineKeyboardCommand=True, discardDoesNotPublish=True,
            realIoFailureRetry=True, failedPersistenceNoRefresh=True, refreshOnlyAfterCurrentSuccess=True,
            sharedAndSiblingUnchanged=True, independentPersistedReadback=True, separateColdConsumer=True,
            ownerRetiresClients=True, noPackageManagerMutation=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('ARCH_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
