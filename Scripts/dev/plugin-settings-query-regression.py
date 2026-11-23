#!/usr/bin/env python3
"""G1b native query representatives with final children and independent cold readers."""
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

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(runner)

ENDPOINT = '''#!/usr/bin/python3
import fcntl, json, os, sys
from pathlib import Path
from urllib.parse import urlparse, parse_qs
case=Path(os.environ['PHA_QUERY_CASE'])
with (case/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream, fcntl.LOCK_EX)
 stream.write(json.dumps(dict(command=Path(sys.argv[0]).name, argv=sys.argv[1:]))+'\\n'); stream.flush()
name=Path(sys.argv[0]).name
if name.startswith('terminal-') or name=='ghostty':
 if sys.argv[1:]!=['-e','ssh','Active']: raise SystemExit('unreviewed terminal action')
elif name=='which': print('/controlled/'+sys.argv[-1])
elif name=='pgrep': print('12345 ssh Active')
elif name=='ping':
 value=int(sys.argv[sys.argv.index('-W')+1])+1
 print('64 bytes: time='+str(value)+' ms')
else:
 city=parse_qs(urlparse(sys.argv[-1]).query)['city'][0]
 times=dict(Base='23:11',Selected='23:22',Sibling='23:33',London='23:44',Following='23:55')
 value=times[city]
 print(json.dumps(dict(code=200, data=dict(timings={key:value for key in ['Imsak','Fajr','Sunrise','Dhuhr','Asr','Maghrib','Isha']},date=dict(hijri=dict(date='01-09-1448',month=dict(number=9,en='Ramadan'),year='1448'),readable='Controlled '+city)))))
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, plugin, scope):
    name = plugin + '-' + scope
    case, out = args.work_root / name, args.output / name
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    latency = plugin == 'latency-monitor'
    ssh = plugin == 'ssh-sessions'
    field, base, edit, sibling, following = ('intervalSeconds', 12, 10, 24, 18) if latency else ('terminalCommand', 'terminal-base', 'terminal-selected', 'terminal-sibling', 'terminal-following') if ssh else ('city', 'Base', 'Selected', 'Sibling', 'Following')
    shared = {field: base, 'opaque': dict(keep='shared')}
    if latency:
        shared.update(hosts=[dict(name='Controlled', address='192.0.2.1')], animations=False)
    elif ssh:
        shared.update(pollInterval=12, showInactiveHosts=True)
    else:
        shared.update(country='UK', method=3, showCountdown=False)
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:' + plugin, tag='sibling', instanceSettings={field: sibling}),
                                 dict(id='plugin:' + plugin, tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar)
    if ssh:
        bar['widgets']['left'][0]['instanceSettings'].update(showInactiveHosts=False, pollInterval=1.5)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = edit
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    after = deepcopy(reset); after['shared'][field] = following
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=after)
    for path, value in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)),
                        ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, value)
    (case / 'requests.jsonl').write_text('')
    for command in ('ping', 'curl', 'which', 'pgrep', 'ghostty', 'terminal-base', 'terminal-selected', 'terminal-sibling', 'terminal-following'):
        path = case / ('bin/' + command); path.write_text(ENDPOINT); path.chmod(0o755)
    (case / 'home/.ssh').mkdir(parents=True)
    (case / 'home/.ssh/config').write_text('Host Active\n Hostname 192.0.2.1\nHost Inactive\n Hostname 192.0.2.2\n')
    wanted = 'original shared Main does not render the saved selected query' if args.expect_shared_main_red else None
    if args.negative_control:
        if args.negative_control == 'shared-client':
            path = dest / 'BarWidget.qml'
            old, new = 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'
            wanted = 'Bar has exact selected query client'
        elif args.negative_control == 'child-text':
            path = dest / 'BarWidget.qml'
            old, new = 'text: root.displayText', 'text: "wrong-controlled-child"'
            wanted = 'actual child Bar Text reflects selected query result'
        else:
            path = dest / ('LatencySettingsClient.qml' if latency else 'PrayerSettingsClient.qml')
            old, new = 'retire(root);', '/* omit selected retirement */'
            wanted = 'retired contexts release every query client'
        text = path.read_text()
        if text.count(old) != (2 if not latency and args.negative_control == 'child-text' else 1):
            raise RuntimeError('review native query mutation anchor')
        path.write_text(text.replace(old, new))
    env = dict(PHA_QUERY_PLUGIN=plugin, PHA_QUERY_SCOPE=scope, PHA_QUERY_CASE=str(case), PHA_QUERY_OUTPUT=str(out),
               PHA_QUERY_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    for mode, boundary in (('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')):
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
        before = hashes(case)
        requests_before = len((case / 'requests.jsonl').read_text().splitlines())
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-query.qml',
                extra_env=dict(env, PHA_QUERY_MODE=mode, PHA_QUERY_BOUNDARY=boundary, PHA_QUERY_OLD_RED='1' if args.expect_shared_main_red else '0'), extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=130)
        except RuntimeError:
            log, code = output / 'runtime.log', output / 'runtime.exit'
            if not wanted or not log.is_file() or wanted not in log.read_text() or code.read_text().strip() != '2':
                raise
            if args.expect_shared_main_red and not (out / 'persisted/edited.json').is_file():
                raise RuntimeError('original shared Main red did not reach native publication')
            result = dict(status='PASS', kind='original-shared-main-red' if args.expect_shared_main_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        marker = 'QUERY_NATIVE: COLD_PASS ' + plugin + ' ' + scope + ' ' + boundary if mode == 'cold' else 'QUERY_NATIVE: PASS ' + plugin + ' ' + scope + ' ' + mode
        if marker not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'QUERY_ASSERT:')):
            raise RuntimeError('native query consumer/diagnostic failure: ' + name + '/' + mode)
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('cold query reader published configuration')
        if ssh:
            rows = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()[requests_before:]]
            actions = [row for row in rows if row['command'].startswith('terminal-') or row['command'] == 'ghostty']
            state = expected[boundary if mode == 'cold' else dict(edit='edited', reset='reset', follow='following')[mode]]
            manifest = json.loads((dest / 'manifest.json').read_text())
            base_settings = dict(manifest['metadata']['defaultSettings'], **state['shared'])
            configs = [base_settings] + [dict(base_settings, **row['instanceSettings']) for row in state['bar']['widgets']['left']]
            wanted_actions = sorted(value['terminalCommand'] or 'ghostty' for value in configs)
            if sorted(row['command'] for row in actions) != wanted_actions or any(row['argv'] != ['-e', 'ssh', 'Active'] for row in actions):
                raise RuntimeError('originating native terminal targets differ from action endpoints')
        stage_receipt(output / 'observed.json', dict(status='PASS', mode=mode, boundary=boundary, configurationHashes=hashes(case)))
    if wanted:
        raise RuntimeError('native query control escaped')
    for boundary, value in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value):
            raise RuntimeError('complete query documents differ')
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    result = dict(status='PASS', plugin=plugin, scope=scope, actualPageMainBarPanel=True, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'], physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('QUERY_NATIVE ' + name + ': PASS', flush=True); return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('latency-monitor', 'ramadan-iftar', 'ssh-sessions'))
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-client', 'child-text', 'retirement'))
    parser.add_argument('--expect-shared-main-red', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-query-regression.py':
        parser.error('execute from supplied source')
    if (args.negative_control or args.expect_shared_main_red) and (not args.plugin or args.scope != 'instance'):
        parser.error('controls require explicit plugin and instance scope')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', dict(files={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for root, paths in ((args.source, [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-query*'))]),
                                (args.plugins, [p for name in ('latency-monitor', 'ramadan-iftar', 'ssh-sessions') for p in sorted((args.plugins / name).rglob('*'))])) for p in paths if p.is_file()}))
        results = [run(args, profile, plugin, scope) for plugin in ((args.plugin,) if args.plugin else ('latency-monitor', 'ramadan-iftar', 'ssh-sessions')) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
