#!/usr/bin/env python3
"""Native originating Syncthing writers and inert captured Kubernetes actions."""
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
import fcntl,json,os,sys,time
from pathlib import Path
case=Path(os.environ['PHA_ACTION_CASE']); name=Path(sys.argv[0]).name; args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (case/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX)
 stream.write(json.dumps(dict(command=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
if name=='terminal-selected': pass
elif name=='syncthing-status.py':
 ids=args[args.index('--folders')+1].split(',') if '--folders' in args else []
 url=args[args.index('--url')+1]
 print(json.dumps(dict(state='idle',sources=dict(resolvedUrl=url),devices={},totals=dict(monitoredFolders=len(ids)),folders=[dict(id=value,label=value,state='idle') for value in ids],availableFolders=[],recentErrors=[])))
else:
 label=args[args.index('--kubeconfig')+1]
 if 'get-contexts' in args: print('* '+label+' controlled-user controlled-cluster')
 elif 'namespaces' in args: print(label+'-ns Active 1d')
 elif 'delete' in args:
  (case/'action-held').write_text('held')
  engine=Path('/proc')/str(os.getsid(0))/'stat'; identity=engine.read_text().split(') ',1)[1].split()[19]
  while not (case/'release').exists():
   try:
    if engine.read_text().split(') ',1)[1].split()[19]!=identity: raise SystemExit(0)
   except FileNotFoundError: raise SystemExit(0)
   time.sleep(0.02)
 elif 'rollout' in args: pass
 elif 'pods' in args: print(label+'-pod 1/1 Running 0 1d')
 elif not any(value in args for value in ['deployments','statefulsets','daemonsets','services','ingresses','configmaps','secrets']): raise SystemExit('unreviewed controlled action '+repr(args))
'''


def run(args, profile, plugin):
    case, out = args.work_root / plugin, args.output / plugin
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin); shutil.copytree(args.plugins / plugin, dest)
    syncthing = plugin == 'syncthing-status'
    shared = dict(apiUrl='http://shared.invalid', configPath='', folderIds=['shared']) if syncthing else dict(kubeconfigPath='shared', terminal='terminal-selected')
    selected = dict(apiUrl='http://selected.invalid', folderIds=['selected']) if syncthing else dict(kubeconfigPath='selected')
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, instanceSettings=dict(selected, opaque='retain')), dict(id='plugin:' + plugin, instanceSettings=dict(opaque='sibling'))]))
    initial = dict(shared=shared, bar=bar)
    changed = deepcopy(initial)
    changed['bar']['widgets']['left'][0]['instanceSettings'].update(dict(folderIds=['selected', 'extra']) if syncthing else dict(kubeconfigPath='replacement'))
    expected = dict(initial=initial, refused=initial, changed=changed, retired=changed)
    for name, value in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)),
                        ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / name, value)
    (case / 'requests.jsonl').write_text(''); (case / 'action-held').write_text('')
    for name in ('kubectl', 'terminal-selected'):
        path = case / ('bin/' + name); path.write_text(ENDPOINT); path.chmod(0o755)
    if syncthing:
        (dest / 'syncthing-status.py').write_text(ENDPOINT)
    runner.write_json(out / 'sources.json', {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins / plugin).rglob('*')) if p.is_file()})
    wanted = None
    if args.negative_control:
        path = dest / ('SyncthingSettingsClient.qml' if syncthing else 'KubectlSettingsClient.qml')
        text = path.read_text()
        if syncthing:
            if text.count('runtimeApi.pluginSettings.folderIds') != 1 or text.count('runtimeApi.saveSettings()') != 1:
                raise RuntimeError('review native writer control anchors')
            text = text.replace('runtimeApi.pluginSettings.folderIds', 'pluginApi.pluginSettings.folderIds').replace('runtimeApi.saveSettings()', 'pluginApi.saveSettings()')
            wanted = 'originating native folder writer updates selected leaf'
        else:
            if text.count('old.stop(); old.destroy();') != 1:
                raise RuntimeError('review worker retirement control anchor')
            text = text.replace('old.stop(); old.destroy();', 'old.destroy();')
            wanted = 'native source handoff fences held action worker'
        path.write_text(text)
    rejected = False
    try:
        try:
            text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-query-actions.qml',
                extra_env=dict(PHA_ACTION_PLUGIN=plugin, PHA_ACTION_CASE=str(case), PHA_ACTION_OUTPUT=str(out), PHA_ACTION_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH']),
                extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=65)
        except RuntimeError:
            if not wanted or not (out / 'runtime.log').is_file() or wanted not in (out / 'runtime.log').read_text() or (out / 'runtime.exit').read_text().strip() != '2':
                raise
            rejected = True
    finally:
        (case / 'release').touch()
        shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    if not rejected and ('QUERY_ACTIONS: PASS ' + plugin not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed'))):
        raise RuntimeError('actual native action boundary failed')
    if not rejected:
        for boundary, value in expected.items():
            if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=value):
                raise RuntimeError('native action documents differ')
    requests = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    for row in requests:
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']:
            raise RuntimeError('owned action endpoint survived engine')
    if rejected:
        result = dict(status='PASS', kind='rejecting-action-control', rejectedAt=wanted, endpointProcessesQuiescent=True)
        runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
        print('QUERY_ACTION_CONTROL ' + plugin + ': PASS', flush=True); return result
    if wanted:
        raise RuntimeError('native action control escaped')
    if not syncthing:
        deletes = [row['argv'] for row in requests if 'delete' in row['argv']]
        restarts = [row['argv'] for row in requests if 'rollout' in row['argv']]
        if deletes != [['--kubeconfig','selected','delete','pods','captured-pod','--context','selected','-n','selected-ns','--wait=false']]:
            raise RuntimeError('held action did not capture originating targets')
        if restarts != [['--kubeconfig','replacement','rollout','restart','deployments/replacement-deploy','--context','replacement','-n','replacement-ns']]:
            raise RuntimeError('replacement action target differs')
        terminals = [row['argv'] for row in requests if row['command'] == 'terminal-selected']
        if len(terminals) != 1 or "'selected'" not in terminals[0][-1] or "'selected-ns'" not in terminals[0][-1]:
            raise RuntimeError('terminal action did not capture originating inputs')
    result = dict(status='PASS', plugin=plugin, nativeWriter=True, independentBoundaries=sorted(expected), endpointProcessesQuiescent=True, externalEffects=False, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('QUERY_ACTIONS ' + plugin + ': PASS', flush=True); return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('syncthing-status', 'kubectl-ctx'))
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if args.negative_control and not args.plugin:
        parser.error('action control requires explicit plugin')
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-query-actions-regression.py':
        parser.error('execute from supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-query-actions.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py']})
        results = [run(args, profile, plugin) for plugin in ((args.plugin,) if args.plugin else ('syncthing-status', 'kubectl-ctx'))]
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
