#!/usr/bin/env python3
"""P054/P161 selected Settings and real AQI consumers, verified VM only."""
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
        shutil.copytree(args.plugins / 'air-quality', case / 'config/plugins/air-quality', ignore=shutil.ignore_patterns('*.bak'))
        endpoint = case / 'bin/endpoint.py'
        shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-host-endpoint.py', endpoint)
        endpoint.chmod(0o700)
        (case / 'bin/curl').symlink_to(endpoint)
        calls = out / 'calls.jsonl'
        env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_CALLS=str(calls),
                   PHA_HOLD_ROOT=str(out))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/air-quality.json'
        runner.write_json(shared, dict(dataSource='open-meteo', useNoctaliaLocation=False,
            customLatitude='1', customLongitude='2', aqiScale='us', refreshInterval=30, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-air.qml'
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
        finally:
            (case / 'config/settings').chmod(0o700)
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        if 'AIR_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('actual Air Settings/AQI endpoint failed')
        rows = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left']
        if rows != [dict(id='plugin:air-quality', instanceSettings=dict(customLatitude='')),
                    dict(id='plugin:air-quality', instanceSettings=dict(aqiScale='eu'))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        if not any('latitude=3&' in item['argv'][-1] for item in recorded):
            raise RuntimeError('selected real curl argv endpoint missing')
        if not (out / 'entered').is_file():
            raise RuntimeError('held old-location response never entered')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_AIR_COLD='1'))
        if 'AIR_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Air AQI consumer failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((args.plugins / 'air-quality').glob('*.qml'))}
        runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, actualSettingsBarDesktop=True,
            inertRealCurlEndpoint=True, genuineKeyboardLatitude=True, discardDoesNotPublish=True,
            realIoFailureRetry=True, sharedAndSiblingUnchanged=True, incompleteLocationClearsData=True,
            oldResponseRetired=True, independentPersistedReadback=True, separateColdConsumer=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('AIR_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
