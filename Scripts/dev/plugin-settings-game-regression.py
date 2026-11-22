#!/usr/bin/env python3
"""Actual Tamagotchi page, native documents, game and rendered stat consumers."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument
spec=importlib.util.spec_from_file_location('game_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
def hashes(case): return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
def run(args,profile,scope):
    case,out=args.work_root/scope,args.output/scope; case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install=case/'install'; shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    for part in ('config/settings/plugins','cache','state'): (case/part).mkdir(parents=True)
    dest=case/'config/plugins/tamagotchi'; shutil.copytree(args.plugins/'tamagotchi',dest)
    shared=dict(hunger=80,happiness=90,cleanliness=70,energy=60,difficulty=50,volume=0.5,showDebug=True,showPercentage=True,opaque=dict(keep='shared'))
    bar=dict(widgets=dict(left=[dict(id='plugin:tamagotchi',tag='selected',instanceSettings=dict(hunger=40,happiness=50,cleanliness=60,energy=70,opaque=dict(keep='selected'))),dict(id='plugin:tamagotchi',tag='sibling',instanceSettings=dict(difficulty=80,hunger=10,opaque=dict(keep='sibling'))),dict(id='plugin:tamagotchi',tag='inherited',instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial=dict(shared=shared,bar=bar); edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']).update(difficulty=0,volume=0.25,showDebug=False,showPercentage=False)
    reset=deepcopy(edited)
    for key in ('difficulty','volume','showDebug','showPercentage'): (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(key)
    following=deepcopy(reset); following['shared'].update(difficulty=100,volume=0.75,showDebug=False,showPercentage=False)
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    for name,value in [('input.json',dict(plugin='tamagotchi')),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/tamagotchi.json',shared),('config/settings/bar.json',bar)]: runner.write_json(case/name,value)
    wanted='original game consumes saved selected difficulty' if args.old_red else None
    env=dict(PHA_GAME_SCOPE=scope,PHA_GAME_CASE=str(case),PHA_GAME_OUTPUT=str(out),PHA_GAME_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_GAME_RED='1' if args.old_red else '0')
    for mode,boundary in [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]:
        output=out/(mode+('-'+boundary if boundary else '')); output.mkdir(); before=hashes(case)
        try:
            text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-game-native.qml',extra_env=dict(env,PHA_GAME_MODE=mode,PHA_GAME_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=100)
        except RuntimeError:
            if not wanted or not (output/'runtime.log').is_file() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2': raise
            if not (out/'persisted/edited.json').is_file(): raise RuntimeError('game red preceded actual native publication')
            result=dict(status='PASS',originalRed=True,rejectedAt=wanted,completePlanAcceptance=False)
            runner.write_json(out/'result.json',result); runner.remove_completed_installs(case,out); return result
        if 'GAME_NATIVE: PASS '+scope+' '+mode not in text or any(v in text for v in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected','GAME_ASSERT:')): raise RuntimeError('game consumer/diagnostic failure')
        if mode=='cold' and hashes(case)!=before: raise RuntimeError('game cold reader published')
        runner.write_json(output/'observed.json',dict(status='PASS',configurationBefore=before,configurationAfter=hashes(case)))
    if wanted: raise RuntimeError('game original red escaped')
    for boundary,value in expected.items():
        if json.loads((out/'persisted'/(boundary+'.json')).read_text())!=dict(status='PASS',values=value): raise RuntimeError('independent game documents: '+boundary)
    result=dict(status='PASS',scope=scope,independentBoundaries=sorted(expected),coldReaders=['edited','reset','following'],physicalProof=False,completePlanAcceptance=False)
    runner.write_json(out/'result.json',result); runner.remove_completed_installs(case,out); return result
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scope',choices=('instance','shared')); parser.add_argument('--old-red',action='store_true')
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-game-regression.py': parser.error('execute supplied source')
    if args.old_red and args.scope!='instance': parser.error('explicit instance red required')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-game-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},pluginFiles={str(p.relative_to(args.plugins)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'tamagotchi').rglob('*') if p.is_file()}))
        rows=[run(args,profile,scope) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        runner.write_json(args.output/'result.json',dict(status='PASS',cases=rows,completePlanAcceptance=False))
if __name__=='__main__': main()
