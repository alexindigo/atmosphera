#!/usr/bin/env python3
"""P056/P143 native selected page and actual contribution graph, VM only."""
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

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


@receipt_run
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
        plugin = 'github-contributions'
        shutil.copytree(args.plugins / plugin, case / 'config/plugins' / plugin, ignore=shutil.ignore_patterns('*.bak'))
        endpoint = case / 'bin/endpoint.py'
        shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-host-endpoint.py', endpoint)
        endpoint.chmod(0o700)
        (case / 'bin/curl').symlink_to(endpoint)
        calls = out / 'calls.jsonl'
        env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_CALLS=str(calls), PHA_HOLD_ROOT=str(out))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/github-contributions.json'
        runner.write_json(shared, dict(username='synthetic-alpha', token='', weeksShown=52, refreshInterval=60, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-contributions.qml'
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
        finally:
            (case / 'config/settings').chmod(0o700)
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        if 'CONTRIBUTIONS_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('actual Contributions Settings/graph endpoint failed')
        rows = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left']
        if rows != [dict(id='plugin:github-contributions', instanceSettings=dict(username='', token='synthetic', weeksShown=4)),
                    dict(id='plugin:github-contributions', instanceSettings=dict(username='synthetic-beta', weeksShown=10))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        if not any('https://api.github.com/graphql' in item['argv'] for item in recorded) or not (out / 'entered').is_file():
            raise RuntimeError('actual GraphQL/held-response endpoint missing')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_CONTRIBUTIONS_COLD='1'))
        if 'CONTRIBUTIONS_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Contributions graph failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((args.plugins / plugin).glob('*.qml'))}
        stage_receipt(out / 'result.json', dict(status='PASS', inputs=inputs, actualDesktopGraph=True,
            genuineUsernameTokenWeeksInput=True, inertHtmlAndGraphql=True, realIoFailureRetry=True,
            incompleteAccountClearsGraph=True, heldResponseRetired=True, independentPersistedReadback=True,
            separateColdConsumer=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('CONTRIBUTIONS_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
