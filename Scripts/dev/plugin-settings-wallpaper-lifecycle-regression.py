#!/usr/bin/env python3
"""LWE's individual captured engine, query and color lifetimes on native owners."""
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
import time
from guest_profile import activate_profile, profile_argument

spec=importlib.util.spec_from_file_location('wallpaper_native',Path(__file__).with_name('plugin-settings-wallpaper-native-regression.py'))
native=importlib.util.module_from_spec(spec); spec.loader.exec_module(native)
runner=native.runner
ENDPOINT='''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_WALLPAPER_CASE']); name=Path(sys.argv[0]).name; args=sys.argv[1:]
if name=='endpoint.py':name=args.pop(0)
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
if name=='scan-wallpapers.sh':
 if args[0].endswith('/held-source'):
  end=time.monotonic()+20
  while not (b/'release-scan').exists():
   if time.monotonic()>end:raise SystemExit('held scan deadline')
   time.sleep(.02)
 print(args[0]+'/controlled\\tControlled')
if name=='linux-wallpaperengine':
 end=time.monotonic()+25
 while not (b/'release-engine').exists():
  if (b/'fail-engine').exists():
   (b/'fail-engine').unlink();print('assets missing: controlled engine failure',file=sys.stderr);raise SystemExit(1)
  if time.monotonic()>end:raise SystemExit('held engine deadline')
  time.sleep(.02)
'''


@receipt_run
def run(args,profile,scenario):
    case,out=args.work_root/scenario,args.output/scenario
    case.mkdir();out.mkdir();(out/'persisted').mkdir();install=case/'install'
    shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    plugin='linux-wallpaperengine-controller';product=args.plugins/plugin;dest=case/'config/plugins'/plugin
    shutil.copytree(product,dest)
    for part in ('config/settings/plugins','home','cache','state','bin','shared-folder','selected-folder','held-source','replacement-folder'):(case/part).mkdir(parents=True)
    screen=args.screens[0];original={screen:dict(path=str(case/'original-wallpaper'))}
    shared=dict(defaultFps=13,autoApplyOnStartup=False,screens=original,lastKnownGoodScreens={},runtimeRecoveryPending=False,
                wallpaperProperties={'color-original':dict(tint='old')},wallpaperColorScreenshots={},wallpapersFolder=str(case/'shared-folder'),opaque='shared')
    selected=dict(defaultFps=29,wallpapersFolder=str(case/'selected-folder'),opaque='selected')
    bar=dict(widgets=dict(left=[dict(id='plugin:'+plugin,instanceSettings=row) for row in (selected,dict(defaultFps=41,opaque='sibling'),dict(opaque='inherited'))]))
    initial=dict(shared=shared,bar=bar);expected={}
    if scenario=='engine':
        stable=deepcopy(initial);stable['shared']['screens']={screen:dict(path=str(case/'newer-wallpaper'))};stable['shared']['lastKnownGoodScreens']=deepcopy(original)
        stable['bar']['widgets']['left'][0]['instanceSettings']['defaultFps']=37
        recovered=deepcopy(stable);recovered['shared']['screens']=deepcopy(original)
        expected=dict(stable=stable,recovered=recovered)
        final=deepcopy(recovered)
    elif scenario=='source':
        final=deepcopy(initial);final['bar']['widgets']['left'][0]['instanceSettings']['wallpapersFolder']=str(case/'replacement-folder')
        expected['replaced']=deepcopy(final)
    else:
        final=deepcopy(initial);final['bar']['widgets']['left'][0]['instanceSettings']['defaultFps']=37
        final['shared']['wallpaperProperties']['color-original']['tint']='new'
        final['shared']['wallpaperColorScreenshots']={screen:dict(path='@capture',wallpaperPath=str(case/'color-original'),scaling='fill',updatedAt='@timestamp')}
        expected['color']=deepcopy(final)
    final['bar']['widgets']['left'][0]['id']='plugin:retired-wallpaper'
    expected['retired']=final
    for path,value in [('input.json',dict(plugin=plugin,startedAt=int(time.time()*1000),screen=screen)),('expectations.json',expected),
                       ('config/settings.json',dict(settingsVersion=62)),('config/settings/colorSchemes.json',dict(useWallpaperColors=False)),
                       ('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+plugin+'.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text('');(case/'bin/endpoint.py').write_text(ENDPOINT)
    endpoint=case/'bin/linux-wallpaperengine';endpoint.write_text(ENDPOINT);endpoint.chmod(0o755)
    adapters=[]
    for name in ('force-stop-engine.sh','scan-wallpapers.sh','capture-wallpaper-colors.sh','check-file-exists.sh','update-noctalia-wallpapers-cache.sh'):
        path=dest/'scripts'/name;adapters.append(dict(path=str(path.relative_to(dest)),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),reason='inert physical endpoint, real consumer/lifetime unchanged'))
        path.write_text('#!/bin/sh\nexec python3 "$PHA_WALLPAPER_CASE/bin/endpoint.py" '+name+' "$@"\n');path.chmod(0o755)
    runner.write_json(out/'adapters.json',adapters)
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    try:
        text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-lifecycle.qml',
            extra_env=dict(PHA_WALLPAPER_LIFETIME=scenario,PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_OUTPUT=str(out),PHA_WALLPAPER_SCREEN=screen,
                           PHA_WALLPAPER_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-lifecycle-disk.py'),
                           HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
    finally:(case/'release-engine').touch();(case/'release-scan').touch()
    if 'WALLPAPER_LIFETIME: PASS '+scenario not in text:raise RuntimeError('individual LWE lifetime incomplete')
    if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('individual LWE diagnostics')
    for boundary in expected:assert json.loads((out/'persisted'/(boundary+'.json')).read_text())['status']=='PASS'
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        path=Path('/proc')/str(row['pid'])/'stat';end=time.monotonic()+5
        while path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:
            if time.monotonic()>end:raise RuntimeError('individual endpoint survived')
            time.sleep(.02)
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    stage_receipt(out/'result.json',dict(status='PASS',scenario=scenario,completeDocuments=sorted(expected),inertEndpoints=len(rows),physicalProof=False))
    runner.remove_completed_installs(case,out);print('WALLPAPER_LIFETIME '+scenario+': PASS',flush=True)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for key in ('source','plugins','work-root','output'):parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--scenario',choices=('engine','source','color'));args=parser.parse_args()
    profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-lifecycle-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    sockets=list(Path('/run/user/'+str(os.getuid())).glob('niri.*.sock'));assert len(sockets)==1
    args.screens=sorted(json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=dict(os.environ,NIRI_SOCKET=str(sockets[0])),text=True)))
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-lifecycle.qml',args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-lifecycle-disk.py')})
        for scenario in ((args.scenario,) if args.scenario else ('engine','source','color')):run(args,profile,scenario)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeWallpaperAcceptance=False))


if __name__=='__main__':main()
