#!/usr/bin/env python3
"""Provider-chain native representative; original reds follow native publication."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('provider_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config/settings').rglob('*.json'))}


def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case / part).mkdir(parents=True)
    install = case / 'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
    dest = case / 'config/plugins/github-feed'; shutil.copytree(args.plugins / 'github-feed', dest)
    endpoint = case / 'bin/curl'; shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-provider-endpoint.py', endpoint); endpoint.chmod(0o755)
    requests = case / 'requests.jsonl'; requests.write_text('')
    shared = dict(username='shared', token='controlled-token', githubUrl='', refreshInterval=1800, enableSystemNotifications=False, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:github-feed', instanceSettings=dict(opaque=dict(keep='selected'))), dict(id='plugin:github-feed', instanceSettings=dict(username='selected')), dict(id='plugin:github-feed', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['username'] = 'selected'
    reset = deepcopy(edited); (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('username')
    following = deepcopy(reset); following['shared']['username'] = 'selected'
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for path, data in [('input.json', dict(plugin='github-feed')), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/github-feed.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case / path, data)
    wanted = 'original shared provider result does not render saved selected source' if args.old_red else None
    if args.negative_control:
        path = dest / 'Panel.qml'; text = path.read_text(); old = 'settingsConsumerFor(pluginApi.settingsContext)'
        if text.count(old) != 1: raise RuntimeError('stale provider selected-view control')
        path.write_text(text.replace(old, 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'))
        runner.write_json(out / 'mutation.json', dict(path='github-feed/Panel.qml', before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest(), control='shared-view'))
        wanted = 'actual views share exact selected provider client'
    env = dict(PHA_PROVIDER_CASE=str(case), PHA_PROVIDER_OUTPUT=str(out), PHA_PROVIDER_SCOPE=scope, PHA_PROVIDER_OLD_RED='1' if args.old_red else '0', PHA_PROVIDER_REQUESTS=str(requests), PHA_PROVIDER_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-http-disk.py'), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    for mode, boundary in [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-provider-native.qml', extra_env=dict(env, PHA_PROVIDER_MODE=mode, PHA_PROVIDER_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2': raise
            if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('original provider red did not reach independent native publication')
            result = dict(status='PASS', kind='original-provider-red' if args.old_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'PROVIDER_NATIVE: PASS ' + scope + ' ' + mode not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PROVIDER_ASSERT:')): raise RuntimeError('provider native consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('cold provider reader published configuration')
        runner.write_json(output / 'observed.json', dict(status='PASS', configurationHashes=hashes(case)))
    if wanted: raise RuntimeError('provider control escaped')
    for boundary, data in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=data): raise RuntimeError('complete provider documents differ')
    rows = [json.loads(line) for line in requests.read_text().splitlines()]
    for row in rows:
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('provider endpoint survived engine')
    result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    runner.write_json(out / 'requests.json', rows); runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('PROVIDER_NATIVE ' + scope + ': PASS', flush=True); return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance')); parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-provider-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and args.scope != 'instance': parser.error('control requires explicit instance scope')
    if args.old_red and args.negative_control: parser.error('one control per run')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-provider-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-provider-endpoint.py', args.source / 'Scripts/dev/fixtures/plugin-settings-http-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'github-feed').rglob('*') if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
