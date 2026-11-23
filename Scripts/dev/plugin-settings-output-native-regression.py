#!/usr/bin/env python3
"""Real output Settings/native documents and actual selected Panel consumers."""
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
from guest_profile import activate_profile,profile_argument

spec=importlib.util.spec_from_file_location('output_runtime',Path(__file__).with_name('plugin-settings-output-runtime-regression.py'))
runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime)
runner=runtime.runner


def hashes(case):return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


@receipt_run
def run(args,profile,member,scope):
    case,out=args.work_root/(member+'-'+scope),args.output/(member+'-'+scope);case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=args.plugins/member;dest=case/('config/plugins/'+member);shutil.copytree(product,dest)
    for name in ('config/settings/plugins','home','bin','cache','state'):(case/name).mkdir(parents=True)
    display=member=='display-settings';field='niriConfigPath' if display else 'gridSize'
    for name in ('Shared','Selected','Following','Sibling'):
        (case/(name+'.kdl')).write_text('output "'+name+'" {\n mode "1280x720"\n scale 1\n}\n')
    shared=dict(opaque='shared')
    if display:shared[field]=str(case/'Shared.kdl')
    else:shared.update(gridSize=13,backend='sway',swayCommand=str(case/'bin/shared-output'),hyprctlCommand=str(case/'bin/selected-output'),snapToGrid=True)
    bar=dict(widgets=dict(left=[dict(id='plugin:'+member,instanceSettings=row) for row in (dict(opaque='selected'),{field:str(case/'Sibling.kdl') if display else 41,'opaque':'sibling'},dict(opaque='inherited'))]))
    initial=dict(shared=shared,bar=bar);edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field]=str(case/'Selected.kdl') if display else 25
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset);following['shared'][field]=str(case/'Following.kdl') if display else 37
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    for name,value in [('input.json',dict(plugin=member)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+member+'.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/name,value)
    # The authored Display fallback is home-relative. Keep its ordinary lookup
    # inside the isolated HOME and make the Reset outcome an actual parsed card.
    fallback=case/'home/.config/niri';fallback.mkdir(parents=True);(fallback/'config.kdl').write_text('output "Default" {\n scale 1\n}\n')
    for name in ('niri','wlr-randr','udevadm','shared-output','selected-output'):
        path=case/'bin'/name;path.write_text(runtime.ENDPOINT);path.chmod(0o755)
    (case/'requests.jsonl').write_text('')
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env=dict(PHA_OUTPUT_PLUGIN=member,PHA_OUTPUT_SCOPE=scope,PHA_OUTPUT_CASE=str(case),PHA_OUTPUT_OUTPUT=str(out),PHA_OUTPUT_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    for mode,boundary in [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]:
        output=out/(mode+('-'+boundary if boundary else ''));output.mkdir();before=hashes(case)
        text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-output-native.qml',extra_env=dict(env,PHA_OUTPUT_MODE=mode,PHA_OUTPUT_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=120)
        if 'OUTPUT_NATIVE: PASS '+member+' '+scope+' '+mode+' '+boundary not in text:raise RuntimeError('output native incomplete')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('output native diagnostics')
        if mode=='cold' and hashes(case)!=before:raise RuntimeError('cold output reader published')
    for name,value in expected.items():
        if json.loads((out/'persisted'/(name+'.json')).read_text())!=dict(status='PASS',values=value):raise RuntimeError('complete native output documents differ')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    stage_receipt(out/'result.json',dict(status='PASS',plugin=member,scope=scope,actualPageAndPanel=True,completeNativeBoundaries=list(expected),nonpublishingColdReaders=['edited','reset','following'],physicalProof=False,completeGroupAcceptance=False))
    runner.remove_completed_installs(case,out);print('OUTPUT_NATIVE '+member+' '+scope+': PASS',flush=True)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--plugin',choices=('display-settings','monitor-layout'));parser.add_argument('--scope',choices=('instance','shared'))
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-output-native-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-output-native.qml',args.source/'Scripts/dev/plugin-settings-output-runtime-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for member in ((args.plugin,) if args.plugin else ('display-settings','monitor-layout')):
            for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,member,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
