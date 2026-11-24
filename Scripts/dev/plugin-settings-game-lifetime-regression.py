#!/usr/bin/env python3
"""Actual game actions, native operational writers, timer and retirement."""
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
import subprocess
from guest_profile import activate_profile, profile_argument
spec = importlib.util.spec_from_file_location('game_life_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
pointer_spec = importlib.util.spec_from_file_location('game_pointer', Path(__file__).with_name('plugin-settings-pomodoro-input-regression.py'))
pointer_module = importlib.util.module_from_spec(pointer_spec); pointer_spec.loader.exec_module(pointer_module)

def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}

@receipt_run
def run(args, profile):
    case, out = args.work_root/'instance', args.output/'instance'
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state'): (case/part).mkdir(parents=True)
    dest = case/'config/plugins/tamagotchi'; shutil.copytree(args.plugins/'tamagotchi', dest)
    shared = dict(hunger=80, happiness=90, cleanliness=70, energy=60, difficulty=50, volume=0.5, showDebug=False, showPercentage=False, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:tamagotchi', tag='selected', instanceSettings=dict(hunger=40, happiness=50, cleanliness=30, energy=50, difficulty=0, volume=0.25, showDebug=True, showPercentage=True, opaque=dict(keep='selected'))), dict(id='plugin:tamagotchi', tag='sibling', instanceSettings=dict(difficulty=80, hunger=10, opaque=dict(keep='sibling'))), dict(id='plugin:tamagotchi', tag='inherited', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    expected = {}; current = dict(shared=shared, bar=bar)
    for name, stats in [('initial', (40,50,30,50)), ('fed',(50,50,30,50)), ('cleaned',(50,50,32,50)), ('played',(50,68,32,47)), ('debugged',(40,58,22,47)), ('sleep-decay',(39,57,21,40)), ('timer',(34,31,35,50)), ('retired',(34,31,35,50))]:
        current = deepcopy(current); current['bar']['widgets']['left'][0]['instanceSettings'].update(zip(('hunger','happiness','cleanliness','energy'),stats)); expected[name] = current
    for name, energies in [('sleep-decay',range(38,43)),('timer',range(48,53)),('retired',range(48,53))]:
        alternatives=[]
        for energy in energies:
            value=deepcopy(expected[name]); value['bar']['widgets']['left'][0]['instanceSettings']['energy']=energy; alternatives.append(value)
        expected[name]=alternatives
    for name, value in [('input.json',dict(plugin='tamagotchi')),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/tamagotchi.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    wanted = None
    if args.control:
        name, old, new, wanted = {
            'game': ('Panel.qml','mainInstance?.gameFor(pluginApi)','mainInstance?.sharedGame','same-context sharing and independent games'),
            'child': ('Pet.qml','root.game?.feed(10)','pluginApi.mainInstance.sharedGame.feed(10)','real Food drop feeds selected game'),
            'writer': ('GameClient.qml','runtimeApi.pluginSettings.hunger = hunger','runtimeApi.mainInstance.pluginApi.pluginSettings.hunger = hunger','independent complete lifetime documents: fed'),
            'retirement': ('GameClient.qml','root.retired = true; root.retire(root)','root.retired = true','native retirement destroys exact game and timer'),
        }[args.control]
        path = dest/name; text = path.read_text(); assert old in text, args.control; path.write_text(text.replace(old,new))
    pointer = pointer_module.build_pointer(args.source,case/'pointer-build')
    sockets = list(profile.session_runtime.glob('niri.'+profile.wayland_display+'.*.sock'))
    assert len(sockets)==1,sockets
    outputs = json.loads(subprocess.run(['niri','msg','--json','outputs'],env=dict(os.environ,NIRI_SOCKET=str(sockets[0])),check=True,capture_output=True,text=True).stdout)
    active = {key:value['logical'] for key,value in outputs.items() if value['logical'] is not None}
    screen = sorted(active)[0]; geometry = active[screen]
    assert min(v['x'] for v in active.values())==0 and min(v['y'] for v in active.values())==0
    layout = dict(x=geometry['x'],y=geometry['y'],width=max(v['x']+v['width'] for v in active.values()),height=max(v['y']+v['height'] for v in active.values()))
    runner.write_json(out/'pointer-layout.json',dict(outputs=outputs,screen=screen,layout=layout))
    env = dict(PHA_GAME_CASE=str(case), PHA_GAME_OUTPUT=str(out), PHA_GAME_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-game-disk.py'),PHA_POINTER=str(pointer),PHA_GAME_SCREEN=screen,PHA_GAME_LAYOUT=json.dumps(layout))
    for mode in ('life','cold'):
        output = out/mode; output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-game-lifetime.qml',extra_env=dict(env,PHA_GAME_MODE=mode),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=100)
        except RuntimeError:
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip() != '2': raise
            stage_receipt(out/'result.json',dict(status='PASS',control=args.control,rejectedAt=wanted,completePlanAcceptance=False)); runner.remove_completed_installs(case,out); return
        finally:
            release = subprocess.run([str(pointer)],input='button 272 0\n',text=True,capture_output=True,timeout=5,env=dict(os.environ,**profile.session_environment()))
            (output/'pointer-release.log').write_text(release.stdout+release.stderr)
            assert release.returncode==0 and 'OK' in release.stdout,'virtual pointer release/join failed'
        marker = 'GAME_LIFETIME: '+('PASS' if mode=='life' else 'COLD_PASS')
        if marker not in text or any(v in text for v in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','GAME_LIFE_ASSERT:')): raise RuntimeError('game lifetime consumer/diagnostic failure')
        if mode=='cold' and before != hashes(case): raise RuntimeError('cold operational reader published')
        stage_receipt(output/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('game lifetime control escaped')
    for name, value in expected.items():
        row=json.loads((out/'persisted'/(name+'.json')).read_text()); assert row['status']=='PASS' and row['values'] in (value if isinstance(value,list) else [value]),name
    final=dict(shared=json.loads((case/'config/settings/plugins/tamagotchi.json').read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
    assert final==json.loads((out/'persisted/timer.json').read_text())['values']==json.loads((out/'persisted/retired.json').read_text())['values']
    elapsed = [float(line.split('GAME_TIMER_ELAPSED ',1)[1]) for line in (out/'life/runtime.log').read_text().splitlines() if 'GAME_TIMER_ELAPSED ' in line]
    assert len(elapsed)==1 and 29500 <= elapsed[0] <= 34000,elapsed
    stage_receipt(out/'result.json',dict(status='PASS',completeDocuments=len(expected),coldReader=True,timerElapsedMs=elapsed[0],physicalProof=False,completePlanAcceptance=False)); runner.remove_completed_installs(case,out)

@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--control',choices=('game','child','writer','retirement')); args=parser.parse_args()
    profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-game-lifetime-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-game-lifetime.qml',args.source/'Scripts/dev/fixtures/plugin-settings-game-disk.py',args.source/'Scripts/dev/plugin-settings-pomodoro-input-regression.py',args.source/'Scripts/dev/edge-scroll-test-pointer.c',args.source/'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'tamagotchi').rglob('*') if p.is_file()}))
        run(args,profile); stage_receipt(args.output/'result.json',dict(status='PASS',completePlanAcceptance=False))
if __name__=='__main__': main()
