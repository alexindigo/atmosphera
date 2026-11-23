#!/usr/bin/env python3
"""Native selected projection policy, with independent files and cold children."""
from fixture_receipts import receipt_run, stage_receipt
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

spec = importlib.util.spec_from_file_location('projection_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, plugin, scope):
    case, out = args.work_root / (plugin + '-' + scope), args.output / (plugin + '-' + scope)
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    privacy, kde = plugin == 'privacy-indicator', plugin == 'kde-connect'
    field, value = ('micFilterRegex', 'Controlled') if privacy else ('hideIfNoDeviceConnected', True) if kde else ('precision', 2)
    shared = dict(opaque=dict(keep='shared'))
    shared.update(dict(micFilterRegex='', camFilterRegex='', enableToast=False) if privacy else dict(hideIfNoDeviceConnected=False, mainDeviceId='phone-a') if kde else dict(precision=8, showBarValue=True))
    overrides = dict(opaque=dict(keep='selected'))
    if kde:
        overrides['mainDeviceId'] = 'phone-b'
    sibling = {field: value}
    if kde:
        sibling['mainDeviceId'] = 'phone-a'
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, tag='selected', instanceSettings=overrides), dict(id='plugin:' + plugin, tag='sibling', instanceSettings=sibling), dict(id='plugin:' + plugin, tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = value
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = value
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    if kde:
        actions = deepcopy(following)
        actions['bar']['widgets']['left'][0]['instanceSettings'].pop('mainDeviceId')
        expected['actions'] = actions
    for path, data in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, data)
    (case / 'requests.jsonl').write_text('')
    endpoint = (args.source / 'Scripts/dev/fixtures/plugin-settings-projection-endpoint.py').read_text()
    for command in ('sh', 'busctl', 'which', 'wl-copy'):
        path = case / 'bin' / command; path.write_text(endpoint); path.chmod(0o755)
    wanted = 'original shared projection does not render saved selected policy' if args.old_red else None
    if args.negative_control:
        path = dest / 'BarWidget.qml'
        if args.negative_control == 'shared-client':
            old, new = 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'
            wanted = 'actual views share exact selected projection client'
        elif args.negative_control == 'retirement':
            path = dest / 'Main.qml'; old, new = 'root._settingsConsumers.delete(context)', 'context'
            wanted = 'retirement releases every context projection'
        else:
            old, new = ('icon: micActive ? "microphone" : "microphone-off"', 'icon: "wrong-controlled-child"') if privacy else ('text: badge', 'text: "wrong-controlled-child"')
            wanted = 'actual child Bar renders selected projection'
        text = path.read_text()
        if text.count(old) != 1:
            raise RuntimeError('stale projection mutation: ' + old)
        path.write_text(text.replace(old, new))
    env = dict(PHA_PROJECTION_PLUGIN=plugin, PHA_PROJECTION_SCOPE=scope, PHA_PROJECTION_CASE=str(case), PHA_PROJECTION_OUTPUT=str(out), PHA_PROJECTION_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_PROJECTION_WAIT_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-projection-disk.py'), PHA_PROJECTION_REQUESTS=str(case / 'requests.jsonl'), PHA_PROJECTION_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    sequence = [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    if kde:
        sequence += [('actions', ''), ('cold', 'actions')]
    for mode, boundary in sequence:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-projection-native.qml', extra_env=dict(env, PHA_PROJECTION_MODE=mode, PHA_PROJECTION_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=100)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2':
                raise
            if args.old_red and not (out / 'persisted/edited.json').is_file():
                raise RuntimeError('original red never reached independent native publication')
            result = dict(status='PASS', kind='original-shared-projection-red' if args.old_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        marker = 'PROJECTION_NATIVE: ' + ('COLD_PASS ' + plugin + ' ' + scope + ' ' + boundary if mode == 'cold' else 'PASS ' + plugin + ' ' + scope + ' ' + mode)
        if marker not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'PROJECTION_NATIVE_ASSERT:')):
            raise RuntimeError('native projection consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('cold projection reader published configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', configurationHashes=hashes(case)))
    if wanted:
        raise RuntimeError('projection control escaped')
    for boundary, data in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=data):
            raise RuntimeError('complete projection documents differ')
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    rows = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    for row in rows:
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']:
            raise RuntimeError('projection endpoint survived engine')
    result = dict(status='PASS', plugin=plugin, scope=scope, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'] + (['actions'] if kde else []), physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('PROJECTION_NATIVE ' + plugin + '/' + scope + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('privacy-indicator', 'noctalia-calculator', 'kde-connect'))
    parser.add_argument('--scope', choices=('shared', 'instance'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red', action='store_true')
    oracle.add_argument('--negative-control', choices=('shared-client', 'child', 'retirement'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-projection-regression.py':
        parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and (not args.plugin or args.scope != 'instance'):
        parser.error('control requires explicit instance member')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-projection-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-projection-endpoint.py', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py', args.source / 'Scripts/dev/fixtures/plugin-settings-projection-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for member in ((args.plugin,) if args.plugin else ('privacy-indicator', 'noctalia-calculator', 'kde-connect')) for p in (args.plugins / member).rglob('*') if p.is_file()}))
        results = [run(args, profile, plugin, scope) for plugin in ((args.plugin,) if args.plugin else ('privacy-indicator', 'noctalia-calculator', 'kde-connect')) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
