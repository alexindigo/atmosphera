#!/usr/bin/env python3
"""Native shared MPV cache publication and captured/retired delayed color input."""
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

spec=importlib.util.spec_from_file_location('wallpaper_native',Path(__file__).with_name('plugin-settings-wallpaper-native-regression.py'))
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
runner=native.runner


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for key in ('source','plugins','work-root','output'):parser.add_argument('--'+key,type=Path,required=True)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-mpv-lifecycle-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        case,out=args.work_root,args.output;case.mkdir();out.mkdir();(out/'persisted').mkdir()
        for part in ('config/settings/plugins','home','bin','cache','state','empty-folder'):(case/part).mkdir(parents=True)
        install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        product=args.plugins/'mpvpaper';dest=case/'config/plugins/mpvpaper';shutil.copytree(product,dest)
        shared=dict(thumbCacheReady=False,opaque='shared')
        bar=dict(widgets=dict(left=[dict(id='plugin:mpvpaper',instanceSettings=dict(currentWallpaper='selected-original',opaque='selected')),dict(id='plugin:mpvpaper',instanceSettings=dict(currentWallpaper='sibling',opaque='sibling'))]))
        initial=dict(shared=shared,bar=bar);ready=deepcopy(initial);ready['shared']['thumbCacheReady']=True
        retired=deepcopy(ready);retired['bar']['widgets']['left'][0]['id']='plugin:retired-wallpaper'
        expected=dict(initial=initial,ready=ready,retired=retired)
        for path,value in [('input.json',dict(plugin='mpvpaper')),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/mpvpaper.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/path,value)
        (case/'requests.jsonl').write_text('')
        endpoint=case/'bin/ffmpeg';endpoint.write_text(native.runtime.ENDPOINT);endpoint.chmod(0o755)
        runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
        runner.write_json(out/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-mpv-lifecycle.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-mpv-lifecycle.qml',
            extra_env=dict(PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_OUTPUT=str(out),PHA_WALLPAPER_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),
            extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
        assert 'WALLPAPER_MPV_LIFETIME: PASS' in text
        assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected'))
        for boundary,value in expected.items():assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=value)
        rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        assert len(rows)==1 and rows[0]['endpoint']=='ffmpeg'
        assert rows[0]['argv'][rows[0]['argv'].index('-i')+1]==str(case/'original-color.mp4')
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
        for row in rows:
            path=Path('/proc')/str(row['pid'])/'stat'
            assert not path.exists() or path.read_text().split(') ',1)[1].split()[19]!=row['start']
        runner.write_json(out/'result.json',dict(status='PASS',completeDocuments=sorted(expected),sharedCacheNativeWriter=True,capturedColorInput=True,retiredDelayedCallback=True,physicalProof=False))
        runner.remove_completed_installs(case,out)
        print('WALLPAPER_MPV_LIFETIME: PASS',flush=True)


if __name__=='__main__':main()
