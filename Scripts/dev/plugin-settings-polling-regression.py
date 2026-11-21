#!/usr/bin/env python3
"""G1a runtime representatives; all execution stays in the verified named guest."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'POLL_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, plugin, scope):
    name = plugin + '-' + scope
    case, out = args.work_root / name, args.output / name
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    (case / 'requests.jsonl').write_text('')
    shutil.copytree(args.plugins / plugin, case / ('config/plugins/' + plugin))
    wireless = plugin == 'battery-wireless-devices'
    shared = dict(refreshInterval=120 if wireless else 120000, opaque=dict(keep='shared'))
    if wireless:
        shared.update(showPercentage=True, showCharging=True, deviceOrder=['controlled'], devices={'controlled': dict(enabled=True)})
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:' + plugin, tag='sibling', instanceSettings=dict(refreshInterval=240 if wireless else 240000)),
                                 dict(id='plugin:' + plugin, tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    target = edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    target.update(refreshInterval=10 if wireless else 1000)
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('refreshInterval')
    following = deepcopy(reset); following['shared']['refreshInterval'] = 180 if wireless else 180000
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for path, value in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('observation.json', dict(connected=False, battery=19)),
                        ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])),
                        ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, value)
    # Disposable command endpoint: the original Main still owns the actual process.
    adapter = '''#!/usr/bin/python3
import fcntl, json, os, sys
from pathlib import Path
case = Path(os.environ['PHA_POLL_CASE'])
with (case / 'requests.jsonl').open('a') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX)
    stream.write(json.dumps(dict(argv=sys.argv[1:])) + '\\n'); stream.flush()
value = json.loads((case / 'observation.json').read_text())
if os.environ['PHA_POLL_PLUGIN'] == 'cloudflare-warp':
    if sys.argv[1:] != ['status']: raise SystemExit('unreviewed WARP action')
    print('Status update: ' + ('Connected' if value['connected'] else 'Disconnected') + '\\nDaemon Mode: Warp')
else:
    print(json.dumps([dict(id='controlled', name='Controlled mouse', type='mouse', battery=value['battery'], charging=False, source='controlled')]))
'''
    endpoint = case / ('config/plugins/' + plugin + '/scripts/scan.py') if wireless else case / 'bin/warp-cli'
    endpoint.write_text(adapter); endpoint.chmod(0o755)
    runner.write_json(out / 'endpoint.json', dict(path=str(endpoint.relative_to(case)), sha256=hashlib.sha256(endpoint.read_bytes()).hexdigest(), physicalProof=False))
    wanted = None
    if args.negative_control:
        if args.negative_control == 'shared-context':
            path = case / ('config/plugins/' + plugin + '/Main.qml')
            needle = 'sourceInterval: Qt.binding(function () {'
            source = path.read_text()
            if source.count(needle) != 1: raise RuntimeError('review polling shared-context anchor')
            source = source.replace('context.settingsView.refreshInterval', 'root.pluginApi.settingsView.refreshInterval')
            path.write_text(source); wanted = 'actual selected Timer interval preserves units'
        elif args.negative_control == 'missing-view':
            path = case / ('config/plugins/' + plugin + '/BarWidget.qml')
            source = path.read_text(); needle = 'readonly property var settingsConsumer:'
            lines = source.splitlines()
            matches = [i for i, line in enumerate(lines) if needle in line]
            if len(matches) != 1: raise RuntimeError('review polling view anchor')
            lines[matches[0]] = '  readonly property var settingsConsumer: null'
            path.write_text('\n'.join(lines) + '\n'); wanted = 'Bar has exact captured-context scheduling client'
        else:
            path = install / 'Services/Plugins/PluginSettingsPoller.qml'
            source = path.read_text(); needle = 'retire(root);'
            if source.count(needle) != 1: raise RuntimeError('review polling retirement anchor')
            path.write_text(source.replace(needle, '/* deliberately omit retirement */', 1))
            wanted = 'retired context leaves no cached schedule or view client'
    if args.expect_old_timer_red:
        wanted = 'old actual polling Timer follows saved instance interval'
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-polling.qml'
    env = dict(PHA_POLL_PLUGIN=plugin, PHA_POLL_SCOPE=scope, PHA_POLL_CASE=str(case), PHA_POLL_OUTPUT=str(out),
               PHA_POLL_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-polling-disk.py'),
               PHA_POLL_OLD_RED='1' if args.expect_old_timer_red else '0', PATH=str(case / 'bin') + ':' + __import__('os').environ['PATH'])
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, fixture, extra_env=dict(env, PHA_POLL_MODE=mode, PHA_POLL_BOUNDARY=boundary),
                timeout=130, extra_lint=tuple(path for member in ('cloudflare-warp', 'battery-wireless-devices', 'ip-monitor', 'monique')
                                            for path in sorted((args.plugins / member).glob('*.qml'))) + (install / 'Services/Plugins/PluginSettingsPoller.qml',))
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            if not wanted or not log.is_file() or not code.is_file() or code.read_text().strip() != '2' or wanted not in log.read_text(): raise
            if args.expect_old_timer_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('old red never published selected native interval')
            result = dict(status='PASS', kind='old-timer-red' if args.expect_old_timer_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        marker = 'POLL: COLD_PASS ' + plugin + ' ' + scope + ' ' + boundary if mode == 'cold' else 'POLL: PASS ' + plugin + ' ' + scope + ' ' + mode
        if marker not in text or any(item in text for item in BAD): raise RuntimeError('polling actual consumer failed: ' + name + '/' + mode)
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('polling cold reader published configuration')
        runner.write_json(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    if wanted: raise RuntimeError('polling rejecting control escaped')
    for boundary, value in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value): raise RuntimeError('independent polling documents differ')
    requests = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    result = dict(status='PASS', plugin=plugin, scope=scope, actualMainPageBar=True, actualPanel=not wireless, periodicSharedObservation=True,
                  independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'], requests=requests, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('POLLING ' + name + ': PASS', flush=True); return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugin', choices=('cloudflare-warp', 'battery-wireless-devices'))
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-context', 'missing-view', 'retirement'))
    parser.add_argument('--expect-old-timer-red', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-polling-regression.py': parser.error('execute from supplied source tree')
    if (args.negative_control or args.expect_old_timer_red) and (not args.plugin or args.scope != 'instance'): parser.error('controls require explicit plugin and instance scope')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        args.baseline_source = args.baseline_plugins = None
        runner.write_json(args.output / 'inputs.json', dict(native=runner.input_fingerprints(args), files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for root, paths in ((args.source, [Path(__file__), args.source / 'Services/Plugins/PluginSettingsPoller.qml', *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-polling*'))]),
                                (args.plugins, [p for plugin in ('cloudflare-warp', 'battery-wireless-devices') for p in sorted((args.plugins / plugin).rglob('*'))])) for p in paths if p.is_file()}))
        results = [run(args, profile, plugin, scope) for plugin in ((args.plugin,) if args.plugin else ('cloudflare-warp', 'battery-wireless-devices')) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False)); print('PLUGIN_SETTINGS_POLLING: PASS', flush=True)


if __name__ == '__main__': main()
