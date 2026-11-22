#!/usr/bin/env python3
"""Selected Agent service admission through actual pages, native files and Bar."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import time

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('resource_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

# An isolated protocol endpoint, not the host MCP or an external account.
ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
b=Path(os.environ['PHA_RESOURCE_CASE']);args=sys.argv[1:]
if not args or not args[0].endswith('/agent-session-status/server.py'):
 os.execv('/usr/bin/python3',['python3',*args])
def record(kind,**values):
 start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
 with (b/'requests.jsonl').open('a') as f:
  fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(kind=kind,pid=os.getpid(),start=start,**values))+'\\n');f.flush()
host=args[args.index('--host')+1];port=int(args[args.index('--port')+1]);token=args[args.index('--token')+1]
record('start',argv=args,host=host,port=port,token=token)
class Handler(BaseHTTPRequestHandler):
 def call(self):
  record('request',method=self.command,path=self.path,port=port,token=self.headers.get('Authorization',''))
  while (b/('hold-'+str(port))).exists() and not (b/('release-'+str(port))).exists():time.sleep(.02)
  failure=b/('fail-'+str(port));failed=failure.exists() and bool(failure.read_text().strip())
  payload=dict(runningCount=port,updatedAt=port,agents=[dict(agent='synthetic-'+str(port),runningCount=port,sessions=[])])
  if self.command=='POST':payload=dict(snapshot=payload)
  self.send_response(503 if failed else 200);self.send_header('Content-Type','application/json');self.end_headers()
  try:self.wfile.write(json.dumps(payload).encode())
  except (BrokenPipeError,ConnectionResetError):pass
 def do_GET(self):self.call()
 def do_POST(self):self.call()
 def log_message(self,*args):pass
ThreadingHTTPServer((host,port),Handler).serve_forever()
'''


def ports():
    sockets = [socket.socket() for _ in range(4)]
    for item in sockets:
        item.bind(('127.0.0.1', 0))
    values = [item.getsockname()[1] for item in sockets]
    for item in sockets:
        item.close()
    return values


def seed(case, plugins):
    for name in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case/name).mkdir(parents=True)
    shutil.copytree(plugins/'agent-session-status', case/'config/plugins/agent-session-status')
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    (case/'requests.jsonl').write_text('')
    endpoint = case/'bin/python3'
    endpoint.write_text(ENDPOINT)
    endpoint.chmod(0o755)


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    seed(case, args.original_plugins or args.plugins)
    plugin = args.plugin
    field = 'port' if plugin == 'agent-session-status' else 'inhibitorWho'
    if plugin == 'clamshell':
        shutil.copytree((args.original_plugins or args.plugins)/plugin, case/'config/plugins'/plugin)
        lifetime_spec = importlib.util.spec_from_file_location('inhibitor_endpoints', Path(__file__).with_name('plugin-settings-resource-lifetime-regression.py'))
        lifetime = importlib.util.module_from_spec(lifetime_spec); lifetime_spec.loader.exec_module(lifetime)
        for name in ('systemd-inhibit', 'niri', 'which'):
            endpoint = case/'bin'/name; endpoint.write_text(lifetime.INHIBITOR); endpoint.chmod(0o755)
    if args.omit_origin:
        path = case/'config/plugins'/plugin/('BarWidget.qml' if field == 'port' else 'Settings.qml')
        text = path.read_text()
        old = 'restartService(pluginApi.settingsContext)' if field == 'port' else 'applySettings(root.pluginApi.runtimeContext)'
        new = 'restartService()' if field == 'port' else 'applySettings()'
        assert text.count(old) == 1
        path.write_text(text.replace(old, new))
    if args.wrong_writer:
        assert field == 'inhibitorWho' and scope == 'instance'
        path = case/'config/plugins/clamshell/BarWidget.qml'
        text = path.read_text(); assert text.count('toggle(pluginApi)') == 1
        path.write_text(text.replace('toggle(pluginApi)', 'toggle()'))
    base, edited_port, sibling, following_port = ports()
    shared = dict(bindAddress='127.0.0.1', port=base, token='synthetic-shared', pollIntervalSec=1, hideWhenEmpty=False, opaque='shared') if field == 'port' else dict(enabled=True, internalConnectorRegex='^eDP', inhibitorWho='shared-who', notify=False, alwaysShowBarWidget=True, opaque='shared')
    edit_value = edited_port if field == 'port' else 'selected-who'
    follow_value = following_port if field == 'port' else 'following-who'
    bar = dict(widgets=dict(left=[dict(id='plugin:'+plugin, instanceSettings=row) for row in ({'opaque': 'selected'}, {field: sibling if field == 'port' else 'sibling-who', 'opaque': 'sibling'}, {'opaque': 'inherited'})]))
    initial = dict(shared=shared, bar=bar)
    edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = edit_value
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = follow_value
    # Shared Reset reveals the manifest port. Keep it isolated too, without
    # changing the native descriptor or supplying a preference workaround.
    manifest = case/'config/plugins'/plugin/'manifest.json'
    descriptor = json.loads(manifest.read_text()); descriptor['metadata']['defaultSettings'][field] = base if field == 'port' else 'default-who'
    runner.write_json(manifest, descriptor)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    if field != 'port' and not (args.original_plugins or args.omit_origin):
        disabled = deepcopy(edited)
        (disabled['shared'] if scope == 'shared' else disabled['bar']['widgets']['left'][0]['instanceSettings'])['enabled'] = False
        expected.update({'runtime-disabled': disabled, 'runtime-enabled': edited})
    runner.write_json(case/'input.json', dict(plugin=plugin, field=field, editValue=edit_value, followValue=follow_value))
    runner.write_json(case/'expectations.json', expected)
    runner.write_json(case/('config/settings/plugins/'+plugin+'.json'), shared)
    runner.write_json(case/'config/settings/bar.json', bar)
    product = (args.original_plugins or args.plugins)/plugin
    runner.write_json(out/'sources.json', {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env = dict(PHA_RESOURCE_CASE=str(case), PHA_RESOURCE_SCOPE=scope, PHA_RESOURCE_OUTPUT=str(out), PHA_RESOURCE_CONTROL='1' if args.original_plugins or args.omit_origin else '0', PHA_RESOURCE_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    rejected = False
    modes = [('edit', '')] if args.original_plugins or args.omit_origin else [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    for mode, boundary in modes:
        part = out/(mode+('-'+boundary if boundary else '')); part.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, part, args.source/'Scripts/dev/fixtures/plugin-settings-resource-native.qml', extra_env=dict(env, PHA_RESOURCE_MODE=mode, PHA_RESOURCE_BOUNDARY=boundary), extra_lint=tuple(sorted((case/'config/plugins'/plugin).glob('*.qml'))), timeout=120)
        except RuntimeError:
            if not args.wrong_writer:
                raise
            log = (part/'runtime.log').read_text()
            assert 'complete resource native documents' in log, log
            actual = dict(shared=json.loads((case/'config/settings/plugins/clamshell.json').read_text()), bar=json.loads((case/'config/settings/bar.json').read_text()))
            assert actual['shared']['enabled'] is False and 'enabled' not in actual['bar']['widgets']['left'][0]['instanceSettings'], actual
            assert actual != expected['runtime-disabled'], actual
            runner.write_json(out/'wrong-writer.json', dict(status='REJECTED', actual=actual, expected=expected['runtime-disabled']))
            # The complete-document oracle, not a receipt, rejects the wrong
            # native writer. Keep the engine's failing outcome explicit.
            rejected = True
            break
        if 'RESOURCE_NATIVE: PASS '+scope+' '+mode+' '+boundary not in text:
            raise RuntimeError('incomplete resource native case')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')):
            raise RuntimeError('resource native diagnostic')
        after = hashes(case)
        runner.write_json(part/'configuration-hashes.json', dict(before=before, after=after, nonpublishing=before == after))
        if mode == 'cold' and before != after:
            raise RuntimeError('resource cold reader published')
        effect = boundary or {'edit': 'edited', 'reset': 'reset', 'follow': 'following'}[mode]
        values = dict(expected[effect]['shared'])
        if scope == 'instance':
            values.update(expected[effect]['bar']['widgets']['left'][0]['instanceSettings'])
        wanted = values.get(field, descriptor['metadata']['defaultSettings'][field])
        observed = json.loads(text.split('RESOURCE_NATIVE_CONSUMER ')[1].splitlines()[0])
        if field == 'port':
            good = observed['url'] == 'http://127.0.0.1:'+str(wanted) and observed['count'] == wanted and observed['rendered']
        else:
            starts = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines() if json.loads(line).get('endpoint') == 'systemd-inhibit' and json.loads(line)['kind'] == 'start']
            good = observed['who'] == wanted and observed['active'] and starts and '--who='+wanted in starts[-1]['argv']
        if not good:
            if not (args.original_plugins or args.omit_origin):
                raise AssertionError(('selected daemon reaches actual service and Panel', wanted, observed))
            rejected = True
        elif args.original_plugins or args.omit_origin:
            raise AssertionError('wrong service origin escaped actual endpoint')
        runner.write_json(part/'consumer.json', dict(status='REJECTED' if rejected else 'PASS', expectedPort=wanted, observed=observed))
    wanted_boundaries = ['initial', 'discarded', 'edited'] if rejected else list(expected)
    for boundary in wanted_boundaries:
        if json.loads((out/'persisted'/(boundary+'.json')).read_text()) != dict(status='PASS', values=expected[boundary]):
            raise RuntimeError('complete resource native documents differ')
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    rows = [json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for _ in range(100):
        live = []
        for row in rows:
            try:
                actual = (Path('/proc')/str(row['pid'])/'stat').read_text().split(') ', 1)[1].split()[19]
            except FileNotFoundError:
                continue
            if actual == row['start']:
                live.append(row)
        if not live:
            break
        time.sleep(.02)
    if live:
        raise RuntimeError('live resource endpoints '+repr(live))
    runner.write_json(out/'result.json', dict(status='PASS', scope=scope, kind='wrong-native-writer-control' if args.wrong_writer else 'original-native-red' if args.original_plugins else 'omitted-origin-control' if args.omit_origin else 'native', completeNativeBoundaries=wanted_boundaries, nonpublishingColdReaders=[] if rejected else ['edited', 'reset', 'following'], endpointRows=len(rows), allEndpointIdentitiesAbsent=True, physicalProof=False))
    runner.remove_completed_installs(case, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scope', choices=('instance', 'shared'))
    parser.add_argument('--plugin', choices=('agent-session-status', 'clamshell'), default='agent-session-status')
    parser.add_argument('--original-plugins', type=Path)
    parser.add_argument('--omit-origin', action='store_true')
    parser.add_argument('--wrong-writer', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-resource-native-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), args.source/'Scripts/dev/plugin-settings-resource-lifetime-regression.py', args.source/'Scripts/dev/fixtures/plugin-settings-resource-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for scope in ((args.scope,) if args.scope else ('instance', 'shared')):
            run(args, profile, scope)
        runner.write_json(args.output/'result.json', dict(status='PASS', completeGroupAcceptance=False))


if __name__ == '__main__':
    main()
