#!/usr/bin/env python3
"""Actual capture page/native publication joined to inert originating actions."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('capture_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys
from pathlib import Path
case=Path(os.environ['PHA_CAPTURE_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='endpoint.py':name=args.pop(0)
if name=='pidof':raise SystemExit(1 if args==['wf-recorder'] else 0)
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (case/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def run(args, profile, plugin, scope):
    case, out = args.work_root/(plugin+'-'+scope), args.output/(plugin+'-'+scope)
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'): (case/part).mkdir(parents=True)
    product, dest = args.plugins/plugin, case/('config/plugins/'+plugin)
    shutil.copytree(product, dest)
    runner.write_json(out/'sources.json', {str(p.relative_to(args.plugins)): dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(), mode=p.stat().st_mode & 0o777) for p in sorted(product.rglob('*')) if p.is_file()})
    recorder = plugin == 'screen-recorder'
    field = 'directory' if recorder else 'recordingSavePath'
    shared = {field: str(case/'shared-output'), 'opaque': 'shared'}
    if recorder: shared.update(audioSource='none', videoSource='portal', frameRate='30', copyToClipboard=False)
    else: shared['recordingNotifications'] = False
    sibling = {field: str(case/'sibling-output'), 'opaque': 'sibling'}
    bar = dict(widgets=dict(left=[dict(id='plugin:'+plugin, instanceSettings=row) for row in (dict(opaque='selected'), sibling, dict(opaque='inherited'))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = str(case/'edited-output')
    reset = deepcopy(edited); (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = str(case/'following-output')
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for path, value in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/'+plugin+'.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case/path, value)
    (case/'requests.jsonl').write_text(''); (case/'bin/endpoint.py').write_text(ENDPOINT)
    adapters = []
    if args.original_plugins:
        for name in sorted(path.name for path in (args.original_plugins/plugin).glob('*.qml') if path.name != 'Settings.qml'):
            original = args.original_plugins/plugin/name
            if original.exists():
                shutil.copy2(original, dest/name)
                adapters.append(dict(path=name, original=str(original), sha256=hashlib.sha256(original.read_bytes()).hexdigest()))
    if args.omitted_caller:
        path = dest/('BarWidget.qml' if recorder else 'Panel.qml')
        old, new = ('toggleRecording(pluginApi.settingsContext)', 'toggleRecording()') if recorder else ('capturePolicy(pluginApi?.settingsContext)', 'capturePolicy()')
        text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('review omitted capture caller')
        path.write_text(text.replace(old, new))
    if not recorder:
        path = dest/'Main.qml'; text = path.read_text(); old = 'if (CompositorService.isNiri)'
        if text.count(old) != 1: raise RuntimeError('review supported-selector adapter')
        path.write_text(text.replace(old, 'if (false)'))
        adapters.append(dict(path='Main.qml', old=old, new='if (false)', reason='supported selector with inert helpers on niri'))
        endpoint = dest/'record.sh'; endpoint.write_text('#!/bin/sh\nexec python3 "$PHA_CAPTURE_CASE/bin/endpoint.py" record.sh "$@"\n'); endpoint.chmod(0o755)
        if args.original_plugins:
            # Hold only the original selector's post-command presentation until
            # the independent endpoint has been read. Its real command builder,
            # old Main/Panel, native documents and originating action are intact.
            # Repeated original teardown otherwise crashes QtWayland before the
            # wrong shared argv can reach the oracle (retained failed attempts).
            path = dest/'ScreenShot.qml'; text = path.read_text()
            old = '        root.closeSelector()\n    }\n\n    ScreenShotOverlayCommon'
            new = '        // Inert original-control presentation hold.\n    }\n\n    ScreenShotOverlayCommon'
            if text.count(old) != 1: raise RuntimeError('review original selector presentation hold')
            path.write_text(text.replace(old,new))
            adapters.append(dict(path='ScreenShot.qml',old=old,new=new,reason='retain original selector through independent wrong-argv assertion; no selected policy change'))
    for name in ('gpu-screen-recorder', 'pidof', 'wl-copy', 'xdg-open'):
        endpoint = case/'bin'/name; endpoint.write_text(ENDPOINT); endpoint.chmod(0o755)
    runner.write_json(out/'adapters.json', adapters)
    control = bool(args.original_plugins) or args.omitted_caller
    wanted = 'actual inert capture endpoint receives selected output'
    env = dict(PHA_CAPTURE_PLUGIN=plugin, PHA_CAPTURE_SCOPE=scope, PHA_CAPTURE_CONTROL='1' if control else '0', PHA_CAPTURE_CASE=str(case), PHA_CAPTURE_OUTPUT=str(out), PHA_CAPTURE_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    modes = [('edit',''), ('cold','edited'), ('reset',''), ('cold','reset'), ('follow',''), ('cold','following')]
    for mode, boundary in ([('edit','')] if control else modes):
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-capture-native.qml', extra_env=dict(env, PHA_CAPTURE_MODE=mode, PHA_CAPTURE_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=120)
        except RuntimeError:
            if not control or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2': raise
            if not (out/'persisted/edited.json').exists(): raise RuntimeError('capture control lacks independent native edited publication')
            runner.write_json(out/'result.json', dict(status='PASS', kind='original-red' if args.original_plugins else 'omitted-caller', rejectedAt=wanted, nativeEditedBoundary=True, completeGroupAcceptance=False))
            runner.remove_completed_installs(case, out); return
        if control: raise RuntimeError('capture control escaped')
        if 'CAPTURE_NATIVE: PASS '+plugin+' '+scope+' '+mode+' '+boundary not in text: raise RuntimeError('capture native did not finish')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')): raise RuntimeError('capture native diagnostic failure')
        if mode == 'cold' and hashes(case) != before: raise RuntimeError('cold capture reader published')
    for boundary, value in expected.items():
        if json.loads((out/('persisted/'+boundary+'.json')).read_text()) != dict(status='PASS', values=value): raise RuntimeError('capture complete native documents differ')
    rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        stat = Path('/proc')/str(row['pid'])/'stat'; deadline = time.monotonic()+5
        while stat.exists() and stat.read_text().split(') ',1)[1].split()[19] == row['start']:
            if time.monotonic() > deadline: raise RuntimeError('capture native endpoint survived')
            time.sleep(.02)
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    runner.write_json(out/'result.json', dict(status='PASS', plugin=plugin, scope=scope, actualPageAndOriginatingView=True, completeNativeBoundaries=sorted(expected), nonpublishingColdReaders=['edited','reset','following'], inertActions=len(rows), physicalProof=False, completeGroupAcceptance=False))
    runner.remove_completed_installs(case, out); print('CAPTURE_NATIVE '+plugin+' '+scope+': PASS', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--'+key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('screen-recorder', 'screen-shot-and-record')); parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--original-plugins', type=Path); parser.add_argument('--omitted-caller', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-capture-native-regression.py': parser.error('execute supplied source')
    if (args.original_plugins or args.omitted_caller) and (not args.plugin or args.scope != 'instance'): parser.error('control requires explicit instance representative')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-capture-native.qml', args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for plugin in ((args.plugin,) if args.plugin else ('screen-recorder', 'screen-shot-and-record')):
            for scope in ((args.scope,) if args.scope else ('instance', 'shared')): run(args, profile, plugin, scope)
        runner.write_json(args.output/'result.json', dict(status='PASS', completeGroupAcceptance=False))


if __name__ == '__main__': main()
