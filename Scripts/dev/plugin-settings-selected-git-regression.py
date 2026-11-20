#!/usr/bin/env python3
"""P048 real page/query/Panel outcome with inert endpoints, verified VM only."""
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
        shutil.copytree(args.plugins / 'git-companion', case / 'config/plugins/git-companion', ignore=shutil.ignore_patterns('*.bak'))
        endpoint = case / 'bin/endpoint.py'
        shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-host-endpoint.py', endpoint)
        endpoint.chmod(0o700)
        for name in ('gh', 'glab'):
            (case / 'bin' / name).symlink_to(endpoint)
        calls = out / 'calls.jsonl'
        env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_CALLS=str(calls))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/git-companion.json'
        runner.write_json(shared, dict(platform='github', repo='synthetic/alpha', group='', refreshInterval=60, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-git.qml'
        text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        if 'GIT_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('actual Git Settings/query/Panel endpoint failed')
        rows = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left']
        if rows != [dict(id='plugin:git-companion', instanceSettings=dict(repo='synthetic/beta')),
                    dict(id='plugin:git-companion', instanceSettings=dict(repo='synthetic/other'))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        if not any('--repo' in item['argv'] and 'synthetic/beta' in item['argv'] for item in recorded):
            raise RuntimeError('selected real query endpoint was not observed')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_GIT_COLD='1'))
        if 'GIT_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Git Panel result failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((args.plugins / 'git-companion').glob('*.qml'))}
        runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, actualSettingsAndPanel=True,
            inertRealQueryEndpoint=True, oneClientPerContext=True, genuineKeyboardRepository=True,
            discardDoesNotPublish=True, nativeApply=True, sharedAndSiblingUnchanged=True,
            independentPersistedReadback=True, separateColdConsumer=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('GIT_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
