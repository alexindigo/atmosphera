#!/usr/bin/env python3
"""G1c native representatives: actual controls, complete files and cold children."""
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


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


runner = load('observation_runner', 'plugin-settings-host-assets-regression.py')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, plugin, scope):
    name = plugin + '-' + scope
    case, out = args.work_root / name, args.output / name
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    port = plugin == 'port-monitor'
    netbird = plugin == 'netbird'
    field = 'hideSystemPorts' if port else 'showIpAddress' if netbird else 'showCityName'
    shared = {field: False, 'refreshInterval': 8000 if not port else 8, 'opaque': dict(keep='shared')}
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:' + plugin, tag='sibling', instanceSettings={field: True, 'refreshInterval': 16000 if not port else 16}),
                                  dict(id='plugin:' + plugin, tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    if netbird:
        shared.update(compactMode=False, showPing=False)
    elif not port:
        shared.update(clickAction='panel', relayClickConnects=True)
        bar['widgets']['left'][0]['instanceSettings'].update(clickAction='toggle', relayClickConnects=False)
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = True
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = True
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following, actions=following)
    for path, value in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)),
                        ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, value)
    (case / 'requests.jsonl').write_text('')
    endpoint = (args.source / 'Scripts/dev/fixtures/plugin-settings-observation-endpoint.py').read_text()
    compile(endpoint, '<inert-native-observation-endpoint>', 'exec')
    for command in ('which', 'ss', 'mullvad', 'netbird', 'kill', 'ghostty'):
        path = case / 'bin' / command; path.write_text(endpoint); path.chmod(0o755)
    wanted = 'original shared observation does not render saved selected policy' if args.old_red else None
    if args.negative_control:
        path = dest / 'BarWidget.qml'
        if args.negative_control == 'relay-policy':
            path = dest / 'MullvadSettingsClient.qml'
            old, new = 'cfg.relayClickConnects ?? defaults.relayClickConnects ?? true', 'observation.relayClickConnects'
            wanted = 'selected relay policy reaches actual action controls'
        elif args.negative_control == 'shared-client':
            old, new = 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'
            wanted = 'actual views share exact selected observation policy client'
        else:
            old, new = ('text: root.portCount.toString()', 'text: "wrong-controlled-child"') if port else ('text: mainInstance?.netbirdIp || ""', 'text: "wrong-controlled-child"') if netbird else ('text: root.main?.currentLocation?.city || ""', 'text: "wrong-controlled-child"')
            wanted = 'actual child Bar Text renders selected policy'
        text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('review native observation mutation anchor')
        path.write_text(text.replace(old, new))
    env = dict(PHA_OBSERVATION_PLUGIN=plugin, PHA_OBSERVATION_SCOPE=scope, PHA_OBSERVATION_CASE=str(case), PHA_OBSERVATION_OUTPUT=str(out),
               PHA_OBSERVATION_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_OBSERVATION_REQUESTS=str(case / 'requests.jsonl'),
               PHA_OBSERVATION_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-observation-native.qml',
                extra_env=dict(env, PHA_OBSERVATION_MODE=mode, PHA_OBSERVATION_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=100)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2': raise
            if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('old observation red did not reach independent native publication')
            result = dict(status='PASS', kind='original-shared-policy-red' if args.old_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        marker = 'OBSERVATION_NATIVE: ' + ('COLD_PASS ' + plugin + ' ' + scope + ' ' + boundary if mode == 'cold' else 'PASS ' + plugin + ' ' + scope + ' ' + mode)
        if marker not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'OBSERVATION_NATIVE_ASSERT:')):
            raise RuntimeError('native observation consumer/diagnostic failure: ' + name + '/' + mode)
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('cold observation reader published configuration')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    if wanted: raise RuntimeError('native observation control escaped')
    for boundary, value in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value): raise RuntimeError('complete observation documents differ')
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    requests = list(map(json.loads, (case / 'requests.jsonl').read_text().splitlines()))
    actions = [row for row in requests if row['command'] in ('kill', 'ghostty') or row['command'] == 'mullvad' and row['argv'] in (['connect'], ['disconnect'], ['relay', 'set', 'location'], ['lockdown-mode', 'set', 'on'])]
    expected_actions = [] if netbird else [('kill', ['90002']), ('ghostty', ['-e', 'sh', '-c', 'echo \'Killing process on port 9090/udp...\' && sudo fuser -k 9090/udp && echo \'Done.\' || echo \'Failed.\'; read -n 1 -p "Press any key to exit..."'])] if port else [('mullvad', ['relay', 'set', 'location']), ('mullvad', ['relay', 'set', 'location']), ('mullvad', ['connect']), ('mullvad', ['disconnect']), ('mullvad', ['lockdown-mode', 'set', 'on'])]
    if sorted((row['command'], row['argv']) for row in actions) != sorted(expected_actions): raise RuntimeError('originating inert action endpoints differ')
    for row in requests:
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('native observation endpoint survived engine')
    result = dict(status='PASS', plugin=plugin, scope=scope, actualPageMainBarPanel=True, originatingInertActions=actions, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('OBSERVATION_NATIVE ' + name + ': PASS', flush=True); return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('port-monitor', 'mullvad', 'netbird'))
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--negative-control', choices=('shared-client', 'child-text', 'relay-policy'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-observation-native-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and (not args.plugin or args.scope != 'instance'): parser.error('control requires explicit instance member')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-observation-endpoint.py', args.source / 'Scripts/dev/fixtures/plugin-settings-observation-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py')}))
        results = [run(args, profile, plugin, scope) for plugin in ((args.plugin,) if args.plugin else ('port-monitor', 'mullvad')) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
