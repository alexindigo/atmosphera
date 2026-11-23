#!/usr/bin/env python3
"""Two real outputs: Video's native automation, backend and delayed writer owners."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import base64
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
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
runner=native.runner


@receipt_run
def run(args,profile,scenario):
    case,out=args.work_root/scenario,args.output/scenario;case.mkdir();out.mkdir();(out/'persisted').mkdir();install=case/'install'
    shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    plugin='video-wallpaper';product=args.plugins/plugin;dest=case/'config/plugins'/plugin;shutil.copytree(product,dest)
    for part in ('config/settings/plugins','home','bin','cache','state','selected-folder','shared-folder'):(case/part).mkdir(parents=True)
    image=case/'baseline.png';image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII='))
    media=case/'selected-folder/controlled.mp4';media.write_text('controlled media path, inert playback only')
    defaults={name:dict(currentWallpaper='',volume=.3,isPlaying=True,noctaliaWallpaper=str(image),opaque='shared-'+name) for name in args.screens}
    monitors=deepcopy(defaults)
    for index,name in enumerate(args.screens):
        monitors[name].update(currentWallpaper=str(case/('selected-'+str(index)+'.mp4')),profile='fast' if index==0 else 'low-latency',volume=.2 if index==0 else .6,opaque='selected-'+name)
    shared=dict(enabled=False,activeBackend='mpvpaper',monitorSpecific=True,monitors=defaults,wallpapersFolder=str(case/'shared-folder'),
                automation=False,mpvSocket=str(profile.runtime_base/'video-lifecycle'),opaque='shared')
    selected=dict(enabled=scenario=='backend',monitors=monitors,wallpapersFolder=str(case/'selected-folder'),opaque='selected')
    if scenario=='automation':
        for index,name in enumerate(args.screens):selected['monitors'][name].update(automation=index==0,automationMode='random',automationTime=.08)
    bar=dict(widgets=dict(left=[dict(id='plugin:'+plugin,instanceSettings=row) for row in (selected,dict(enabled=False,opaque='sibling'),dict(opaque='inherited'))]))
    initial=dict(shared=shared,bar=bar);applied=deepcopy(initial)
    if scenario=='automation':
        applied['bar']['widgets']['left'][0]['instanceSettings']['monitors'][args.screens[0]].update(currentWallpaper=str(media),isPlaying=True)
    if scenario=='baseline':applied['bar']['widgets']['left'][0]['instanceSettings']['monitors'][args.screens[0]]['noctaliaWallpaper']=str(case/'captured-baseline')
    retired=deepcopy(applied);retired['bar']['widgets']['left'][0]['id']='plugin:retired-wallpaper'
    expected=dict(applied=applied,retired=retired)
    for path,value in [('input.json',dict(plugin=plugin)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),
        ('config/settings/colorSchemes.json',dict(useWallpaperColors=False)),('config/plugins.json',dict(version=6,states={},sources=[])),
        ('config/settings/plugins/'+plugin+'.json',shared),('config/settings/bar.json',bar),
        ('cache/wallpapers.json',dict(wallpapers={name:dict(light=str(image),dark=str(image)) for name in args.screens}))]:runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text('')
    for name in ('mpvpaper','ffmpeg'):
        path=case/'bin'/name;path.write_text(native.runtime.ENDPOINT);path.chmod(0o755)
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    try:
        text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-video-lifecycle.qml',
            extra_env=dict(PHA_WALLPAPER_LIFETIME=scenario,PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_OUTPUT=str(out),
                PHA_WALLPAPER_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),
                HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
    finally:(case/'release-engine').touch()
    if 'WALLPAPER_VIDEO_LIFETIME: PASS '+scenario not in text:raise RuntimeError('Video individual lifetime incomplete')
    if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('Video individual diagnostics')
    for boundary,value in expected.items():assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=value)
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        path=Path('/proc')/str(row['pid'])/'stat';end=time.monotonic()+5
        while path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:
            if time.monotonic()>end:raise RuntimeError('Video endpoint survived')
            time.sleep(.02)
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    stage_receipt(out/'result.json',dict(status='PASS',scenario=scenario,actualOutputs=args.screens,completeDocuments=sorted(expected),inertEndpoints=len(rows),physicalProof=False))
    runner.remove_completed_installs(case,out);print('WALLPAPER_VIDEO_LIFETIME '+scenario+': PASS',flush=True)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for key in ('source','plugins','work-root','output'):parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--scenario',choices=('automation','backend','baseline'));args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-video-lifecycle-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    sockets=list(Path('/run/user/'+str(os.getuid())).glob('niri.*.sock'));assert len(sockets)==1
    args.screens=sorted(json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=dict(os.environ,NIRI_SOCKET=str(sockets[0])),text=True)))
    assert len(args.screens)==2,'two actual outputs are required, never fake screen labels'
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-video-lifecycle.qml')})
        for scenario in ((args.scenario,) if args.scenario else ('automation','backend','baseline')):run(args,profile,scenario)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeWallpaperAcceptance=False))


if __name__=='__main__':main()
