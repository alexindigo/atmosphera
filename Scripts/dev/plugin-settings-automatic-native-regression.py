#!/usr/bin/env python3
"""Scoped automatic-policy pages/native documents and inert tablet/OSK actions."""
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

spec = importlib.util.spec_from_file_location('automatic_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,signal,sys,time
from pathlib import Path
b=Path(os.environ['PHA_AUTO_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='sh':
 code=args[1]
 if 'HYPRLAND_INSTANCE_SIGNATURE' in code and 'printf niri' in code:print('niri')
 elif 'if [ -f "$1" ]' in code:print('off')
 elif 'inotifywait -m' in code:
  while True:time.sleep(.1)
 elif '/tmp/2-in-1-tools.log' in code or code.startswith('command -v monitor-sensor'):pass
 elif str(b) in code and code.startswith(("test -f '", "find '", "for d in '")):os.execv('/usr/bin/sh',['sh',*args])
 else:raise SystemExit('Unreviewed shell endpoint: '+repr(args))
elif name=='which':print(str(b/'bin'/args[0]))
elif name=='pgrep':sys.exit(1)
elif name=='niri' and '--json' in args:print(json.dumps({'eDP-test':{'logical':{'transform':'Normal'}}}))
elif name.startswith('wvkbd-'):
 def observed(sig,frame):
  with (b/'signals.jsonl').open('a') as f:f.write(json.dumps(dict(pid=os.getpid(),signal=sig,endpoint=name))+'\\n')
 signal.signal(signal.SIGUSR1,observed);signal.signal(signal.SIGUSR2,observed)
 while True:time.sleep(.1)
elif name=='busctl':sys.exit(1)
elif name=='gsettings':print('false')
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


@receipt_run
def run(args, profile, member, scope):
    case, out = args.work_root/(member+'-'+scope), args.output/(member+'-'+scope)
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = args.plugins/member
    dest = case/('config/plugins/'+member)
    shutil.copytree(product, dest)
    if args.original_plugins:
        for name in ('Main.qml', 'BarWidget.qml', 'WvkbdBackend.qml', 'SqueekboardBackend.qml'):
            if (args.original_plugins/member/name).exists(): shutil.copy2(args.original_plugins/member/name, dest/name)
    osk = member == 'osk-toggle'
    field = 'wvkbdBin' if osk else 'buttonBehavior'
    shared = {field: 'wvkbd-shared' if osk else 'toggle-auto-rotate-lock', 'opaque': 'shared'}
    if osk: shared['backend'] = 'wvkbd'
    else: shared.update(tabletModeStateFile=str(case/'tablet-state'), autoRotateInTabletMode=False)
    bar = dict(widgets=dict(left=[dict(id='plugin:'+member, instanceSettings=row) for row in (dict(opaque='selected'), {field: 'wvkbd-sibling' if osk else 'manual-rotate', 'opaque':'sibling'}, dict(opaque='inherited'))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = 'wvkbd-selected' if osk else 'manual-rotate'
    reset = deepcopy(edited)
    (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = 'wvkbd-following' if osk else 'manual-rotate'
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    (case/'config/settings/plugins').mkdir(parents=True)
    for name, value in [('input.json', dict(plugin=member)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/'+member+'.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case/name, value)
    for name in ('bin','home','cache','state'): (case/name).mkdir()
    (case/'tablet-state').write_text('off\n'); (case/'requests.jsonl').write_text(''); (case/'signals.jsonl').write_text('')
    for name in ('sh','niri','hyprctl','which','pgrep','pkill','busctl','gsettings','wvkbd-mobintl','wvkbd-shared','wvkbd-sibling','wvkbd-selected','wvkbd-following'):
        path = case/'bin'/name; path.write_text(ENDPOINT); path.chmod(0o755)
    runner.write_json(out/'sources.json', {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env = dict(PHA_AUTO_PLUGIN=member, PHA_AUTO_SCOPE=scope, PHA_AUTO_CASE=str(case), PHA_AUTO_OUTPUT=str(out), PHA_AUTO_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    controlled = args.original_plugins is not None
    modes = [('edit', '')] if controlled else [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    rejected = False
    for mode, boundary in modes:
        output = out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source/'Scripts/dev/fixtures/plugin-settings-automatic-native.qml', extra_env=dict(env, PHA_AUTO_MODE=mode, PHA_AUTO_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=120)
        except RuntimeError:
            text = (output/'runtime.log').read_text()
            wanted = 'originating keyboard binary reaches physical backend' if osk else 'originating manual rotation reaches compositor endpoint'
            if not controlled or wanted not in text or (output/'runtime.exit').read_text().strip() != '2': raise
            rejected = True
        if not rejected and 'AUTOMATIC_NATIVE: PASS '+scope+' '+mode+' '+boundary not in text: raise RuntimeError('incomplete automatic native case')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')): raise RuntimeError('automatic runtime diagnostics')
        after = hashes(case)
        runner.write_json(output/'configuration-hashes.json', dict(before=before, after=after, nonpublishing=before == after))
        if mode == 'cold' and after != before: raise RuntimeError('cold reader published')
    if controlled and not rejected: raise RuntimeError('original policy escaped')
    wanted_boundaries = ['initial', 'discarded', 'edited'] if rejected else list(expected)
    for name in wanted_boundaries:
        if json.loads((out/'persisted'/(name+'.json')).read_text()) != dict(status='PASS', values=expected[name]): raise RuntimeError('native complete documents differ: '+name)
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    shutil.copy2(case/'signals.jsonl', out/'signals.jsonl')
    stage_receipt(out/'result.json', dict(status='PASS', plugin=member, scope=scope, kind='original-native-red' if rejected else 'native', completeNativeBoundaries=wanted_boundaries, nonpublishingColdReaders=[] if rejected else ['edited','reset','following'], physicalProof=False, completeGroupAcceptance=False))
    runner.remove_completed_installs(case, out)


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared')); parser.add_argument('--plugin',choices=('2-in-1-tools','osk-toggle'))
    parser.add_argument('--original-plugins',type=Path)
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-automatic-native-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-automatic-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for member in ((args.plugin,) if args.plugin else ('2-in-1-tools','osk-toggle')):
            for scope in ((args.scope,) if args.scope else ('instance','shared')): run(args,profile,member,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__': main()
