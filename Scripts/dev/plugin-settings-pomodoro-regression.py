#!/usr/bin/env python3
"""Pomodoro native page, selected timers and independent complete documents."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument
spec = importlib.util.spec_from_file_location('pomo_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
KEYS = ['workDuration', 'shortBreakDuration', 'longBreakDuration', 'sessionsBeforeLongBreak', 'autoStartBreaks', 'autoStartWork', 'compactMode', 'playSound']
EDIT = dict(zip(KEYS, [30, 7, 20, 3, True, True, True, False]))
FOLLOW = dict(zip(KEYS, [35, 8, 25, 5, False, False, False, False]))
def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'): (case/part).mkdir(parents=True)
    dest = case/'config/plugins/pomodoro'; shutil.copytree(args.plugins/'pomodoro', dest)
    controls = {
        'bar': ('BarWidget.qml', 'pluginApi?.mainInstance?.timerFor(pluginApi)', 'pluginApi?.mainInstance?.settingsConsumer', 'both entries share exact timer'),
        'panel': ('Panel.qml', 'pluginApi?.mainInstance?.timerFor(pluginApi)', 'pluginApi?.mainInstance?.settingsConsumer', 'actual Panel selected policy'),
        'child': ('BarWidget.qml', 'return formatTime(mainInstance.pomodoroRemainingSeconds)', 'return "wrong"', 'actual Bar time Text'),
    }
    if args.control:
        name, old, new, _ = controls[args.control]; path=dest/name; text=path.read_text()
        assert text.count(old)==1; path.write_text(text.replace(old,new))
        runner.write_json(out/'mutation.json',dict(file=name,old=old,new=new,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    shared = dict(workDuration=25, shortBreakDuration=5, longBreakDuration=15, sessionsBeforeLongBreak=4, autoStartBreaks=False, autoStartWork=False, compactMode=False, playSound=True, opaque={'keep':'shared'})
    bar = dict(widgets=dict(left=[dict(id='plugin:pomodoro', tag='selected', instanceSettings={'opaque':{'keep':'selected'}}), dict(id='plugin:pomodoro', tag='sibling', instanceSettings=dict(workDuration=45, compactMode=False, opaque={'keep':'sibling'})), dict(id='plugin:pomodoro', tag='inherited', instanceSettings={'opaque':{'keep':'inherited'}})]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(EDIT)
    reset = deepcopy(edited)
    for key in KEYS: (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following = deepcopy(reset); following['shared'].update(FOLLOW)
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged':edited}, reset=reset, following=following)
    for name, value in [('input.json',dict(plugin='pomodoro')), ('expectations.json',expected), ('config/settings.json',dict(settingsVersion=62)), ('config/plugins.json',dict(version=6, states={}, sources=[])), ('config/settings/plugins/pomodoro.json',shared), ('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    wanted = 'original timer consumes saved selected duration' if args.old_red else controls[args.control][3] if args.control else None
    env = dict(PHA_POMO_SCOPE=scope, PHA_POMO_CASE=str(case), PHA_POMO_OUTPUT=str(out), PHA_POMO_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'), PHA_POMO_RED='1' if args.old_red else '0', PHA_POMO_LIFETIME='1' if args.native_lifetime else '0')
    modes = [('edit','')] if args.native_lifetime else [('edit',''), ('cold','edited'), ('reset',''), ('cold','reset'), ('follow',''), ('cold','following')]
    for mode, boundary in modes:
        output=out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before=hashes(case)
        try:
            text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-pomodoro-native.qml',extra_env=dict(env,PHA_POMO_MODE=mode,PHA_POMO_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=100)
        except RuntimeError:
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2': raise
            if not (out/'persisted/edited.json').is_file(): raise RuntimeError('red preceded native publication')
            result=dict(status='PASS',originalRed=args.old_red,control=args.control,rejectedAt=wanted,completePlanAcceptance=False)
            stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
        if 'POMO_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','POMO_ASSERT:')): raise RuntimeError('Pomodoro consumer/diagnostic failure')
        if mode=='cold' and hashes(case)!=before: raise RuntimeError('cold reader published')
        stage_receipt(output/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('original red escaped')
    if args.native_lifetime:
        if 'POMO_NATIVE_LIFETIME: PASS' not in text: raise RuntimeError('native retirement marker absent')
        expected={key:expected[key] for key in ('initial','discarded','edited')}
    for boundary,value in expected.items():
        if json.loads((out/'persisted'/(boundary+'.json')).read_text())!=dict(status='PASS',values=value): raise RuntimeError('independent documents: '+boundary)
    result=dict(status='PASS',scope=scope,independentBoundaries=sorted(expected),coldReaders=[] if args.native_lifetime else ['edited','reset','following'],nativeLifetime=args.native_lifetime,physicalProof=False,completePlanAcceptance=False)
    stage_receipt(out/'result.json',result); runner.remove_completed_installs(case,out); return result
@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared')); parser.add_argument('--old-red',action='store_true')
    parser.add_argument('--control',choices=('bar','panel','child'))
    parser.add_argument('--native-lifetime',action='store_true')
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-pomodoro-regression.py': parser.error('execute supplied source')
    if args.old_red and args.scope!='instance': parser.error('explicit instance red required')
    if args.control and (args.scope!='instance' or args.old_red): parser.error('explicit candidate instance control required')
    if args.native_lifetime and (args.scope!='instance' or args.control or args.old_red): parser.error('explicit candidate instance lifetime required')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-pomodoro-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'pomodoro').rglob('*') if p.is_file()}))
        rows=[run(args,profile,scope) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        stage_receipt(args.output/'result.json',dict(status='PASS',cases=rows,completePlanAcceptance=False))
if __name__=='__main__': main()
