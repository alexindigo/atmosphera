#!/usr/bin/env python3
"""Independent native tablet restore documents and omitted-origin controls."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
from types import SimpleNamespace

from guest_profile import activate_profile, profile_argument

spec=importlib.util.spec_from_file_location('automatic_native',Path(__file__).with_name('plugin-settings-automatic-native-regression.py'))
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
runner=native.runner

DISK='''import json,sys,time
from pathlib import Path
b,o,phase=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
expected=json.loads((b/'expectations.json').read_text())[phase]
start=time.monotonic();observations=[]
while True:
 actual={key:json.loads((b/'config/settings'/name).read_text()) for key,name in [('shared','plugins/2-in-1-tools.json'),('bar','bar.json'),('dock','dock.json')]}
 if not observations or observations[-1]['values']!=actual:observations.append(dict(elapsed=time.monotonic()-start,values=actual))
 if actual==expected:break
 if time.monotonic()-start>6:
  (o/(phase+'-failed.json')).write_text(json.dumps(dict(observations=observations,expected=expected),indent=2)+'\\n')
  raise SystemExit('NATIVE_RESTORE_DOCUMENTS '+repr((actual,expected)))
 time.sleep(.03)
(o/(phase+'-settlement.json')).write_text(json.dumps(dict(observations=observations,elapsed=time.monotonic()-start),indent=2)+'\\n')
(o/(phase+'.json')).write_text(json.dumps(dict(status='PASS',values=actual),indent=2)+'\\n')
print('NATIVE_RESTORE_DOCUMENTS: PASS '+phase)
'''


def run_writer(args,profile):
    case,out=args.work_root/'restore',args.output/'restore';case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    dest=case/'config/plugins/2-in-1-tools';shutil.copytree(args.plugins/'2-in-1-tools',dest)
    for name in ('bin','home','cache','state'):(case/name).mkdir()
    (case/'config/settings/plugins').mkdir(parents=True)
    shared=dict(tabletModeStateFile=str(case/'tablet-state'),autoRotateInTabletMode=False,autoTabletBarDensity=False,exclusiveDockInTabletMode=False,lastNonTabletBarDensity='',lastNonTabletDockType='',lastNonTabletDockEnabled=True,opaque=dict(retain=['shared']))
    bar=dict(density='compact',widgets=dict(left=[dict(id='plugin:2-in-1-tools',instanceSettings=dict(autoTabletBarDensity=True,exclusiveDockInTabletMode=True,tabletBarDensity='comfortable',opaque='selected')),dict(id='plugin:2-in-1-tools',instanceSettings=dict(tabletBarDensity='default',opaque='sibling'))]),opaque='bar')
    dock=dict(dockType='floating',enabled=False,opaque='dock')
    initial=dict(shared=shared,bar=bar,dock=dock);active=deepcopy(initial)
    active['shared'].update(lastNonTabletBarDensity='compact',lastNonTabletDockType='floating',lastNonTabletDockEnabled=False)
    active['bar']['density']='comfortable';active['dock'].update(dockType='exclusive',enabled=True)
    for name,value in [('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/2-in-1-tools.json',shared),('config/settings/bar.json',bar),('config/settings/dock.json',dock),('expectations.json',dict(initial=initial,active=active,restored=initial))]:runner.write_json(case/name,value)
    (case/'tablet-state').write_text('off\n');(case/'requests.jsonl').write_text('');(case/'signals.jsonl').write_text('');(case/'disk.py').write_text(DISK)
    # Read only this fixture's state file. Every compositor/debug/watch effect stays inert.
    endpoint=native.ENDPOINT.replace("elif 'if [ -f \"$1\" ]' in code:print('off')", "elif 'if [ -f \"$1\" ]' in code:print(Path(args[-1]).read_text().strip())")
    for name in ('sh','niri','hyprctl','monitor-sensor'):
        path=case/'bin'/name;path.write_text(endpoint);path.chmod(0o755)
    runner.write_json(out/'sources.json',{str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.rglob('*') if p.is_file()})
    text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-automatic-writers.qml',extra_env=dict(PHA_AUTO_CASE=str(case),PHA_AUTO_OUTPUT=str(out),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=100)
    if 'AUTOMATIC_WRITERS: PASS' not in text:raise RuntimeError('native restore incomplete')
    for boundary,expected in [('initial',initial),('active',active),('restored',initial)]:
        if json.loads((out/'persisted'/(boundary+'.json')).read_text())!=dict(status='PASS',values=expected):raise RuntimeError('complete native restore mismatch')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    runner.write_json(out/'result.json',dict(status='PASS',kind='native-operational-writer',completeDocuments=['initial','active','restored'],configurationAndOpaquePreserved=True,physicalProof=False,completeGroupAcceptance=False))
    runner.remove_completed_installs(case,out)


def controls(args,profile):
    for member in ('2-in-1-tools','osk-toggle'):
        product=args.work_root/(member+'-control');product.mkdir();shutil.copytree(args.plugins/member,product/member)
        name,old,new=('BarWidget.qml','activatePrimaryButton(outputName, pluginApi?.settingsContext)','activatePrimaryButton(outputName)') if member=='2-in-1-tools' else ('Main.qml','root.toggleKeyboard(context);','root.toggleKeyboard();')
        path=product/member/name;text=path.read_text()
        if old not in text:raise RuntimeError('stale omitted-origin control')
        path.write_text(text.replace(old,new))
        work=args.work_root/(member+'-native');out=args.output/(member+'-native');work.mkdir();out.mkdir()
        child=SimpleNamespace(work_root=work,output=out,source=args.source,plugins=args.plugins,original_plugins=product)
        native.run(child,profile,member,'instance')
        receipt=out/(member+'-instance')/'result.json'
        result=json.loads(receipt.read_text());result.update(kind='omitted-origin-native-red',mutation=dict(file=name,old=old,new=new))
        runner.write_json(receipt,result)


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--case',choices=('writers','controls','all'),default='all')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-automatic-writers-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-automatic-writers.qml',args.source/'Scripts/dev/plugin-settings-automatic-native-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-automatic-native.qml')})
        if args.case in ('writers','all'):run_writer(args,profile)
        if args.case in ('controls','all'):controls(args,profile)
        runner.write_json(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
