#!/usr/bin/env python3
"""Actual scoped wallpaper Settings tools, with native documents and cold pages."""
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

spec = importlib.util.spec_from_file_location('wallpaper_native', Path(__file__).with_name('plugin-settings-wallpaper-native-regression.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
runner = native.runner


def run(args, profile, plugin, scope, choice):
    label = plugin+'-'+scope+'-'+choice
    case, out = args.work_root/label, args.output/label
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    for part in ('config/settings/plugins', 'home', 'cache', 'state', 'original-folder', 'draft-folder'):
        (case/part).mkdir(parents=True)
    for folder in ('original-folder', 'draft-folder'):
        (case/folder/'only.mp4').write_text('controlled file inventory, not media')
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    dest = case/'config/plugins'/plugin
    shutil.copytree(args.plugins/plugin, dest)
    video = plugin == 'video-wallpaper'
    shared = dict(opaque='shared', wallpapersFolder=str(case/'original-folder'))
    path = str(case/'original-folder/only.mp4')
    if video:
        shared.update(enabled=True, activeBackend='mpvpaper', monitorSpecific=True,
                      monitors={name:dict(currentWallpaper=path, volume=.3, isPlaying=True, opaque='monitor-'+name) for name in args.screens})
        sibling = dict(monitors={args.screens[0]:dict(currentWallpaper='sibling-choice', opaque='sibling-monitor')})
    else:
        shared.update(active=True, currentWallpaper=path, profile='default', isPlaying=True, isMuted=False)
        sibling = dict(currentWallpaper='sibling-choice')
    sibling['opaque'] = 'sibling'
    bar = dict(widgets=dict(left=[dict(id='plugin:'+plugin, instanceSettings=row) for row in (dict(opaque='selected'), sibling, dict(opaque='inherited'))]))
    initial = dict(shared=shared, bar=bar)
    applied = deepcopy(initial)
    owner = applied['shared'] if scope == 'shared' else applied['bar']['widgets']['left'][0]['instanceSettings']
    chosen = '' if choice == 'clear' else str(case/'draft-folder/only.mp4')
    if choice == 'random': owner['wallpapersFolder'] = str(case/'draft-folder')
    if video:
        # Atomic field intent preserves the complete selected presentation;
        # other outputs and opaque members survive the explicit replacement.
        monitors = deepcopy(shared['monitors'])
        monitors[args.screens[0]]['currentWallpaper'] = chosen
        owner['monitors'] = monitors
    else:
        owner['currentWallpaper'] = chosen
    for path, value in (
        ('input.json',dict(plugin=plugin)), ('expectations.json',dict(staged=initial,discarded=initial,applied=applied)),
        ('config/settings.json',dict(settingsVersion=62)), ('config/plugins.json',dict(version=6,states={},sources=[])),
        ('config/settings/plugins/'+plugin+'.json',shared), ('config/settings/bar.json',bar)):
        runner.write_json(case/path,value)
    runner.write_json(out/'sources.json',{str(p.relative_to(args.plugins/plugin)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins/plugin).rglob('*')) if p.is_file()})
    env = dict(PHA_WALLPAPER_PLUGIN=plugin,PHA_WALLPAPER_SCOPE=scope,PHA_WALLPAPER_CHOICE=choice,
               PHA_WALLPAPER_CASE=str(case),PHA_WALLPAPER_OUTPUT=str(out),
               PHA_WALLPAPER_CHOSEN=chosen,PHA_WALLPAPER_SCREEN=args.screens[0],
               PHA_WALLPAPER_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'))
    for mode in ('discard','apply','cold'):
        output = out/mode; output.mkdir(); before = native.hashes(case)
        text = runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-tools.qml',
                                  extra_env=dict(env,PHA_WALLPAPER_MODE=mode),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
        if 'WALLPAPER_TOOLS: PASS '+plugin+' '+scope+' '+choice+' '+mode not in text: raise RuntimeError('wallpaper tools incomplete')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')): raise RuntimeError('wallpaper tools diagnostics')
        if mode == 'cold' and native.hashes(case) != before: raise RuntimeError('cold Settings tools published')
    expected = json.loads((case/'expectations.json').read_text())
    for boundary, document in expected.items():
        assert json.loads((out/'persisted'/(boundary+'.json')).read_text()) == dict(status='PASS',values=document)
    runner.write_json(out/'result.json',dict(status='PASS',plugin=plugin,scope=scope,choice=choice,actualPages=3,
        completeDocuments=sorted(expected),coldReaders=1,immediateMainDispatches=0,physicalProof=False))
    runner.remove_completed_installs(case,out)
    print('WALLPAPER_TOOLS '+label+': PASS',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source','plugins','work-root','output'): parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--plugin',choices=('mpvpaper','video-wallpaper')); parser.add_argument('--scope',choices=('instance','shared'))
    parser.add_argument('--choice',choices=('clear','random'))
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-wallpaper-tools-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    sockets=list(Path('/run/user/'+str(os.getuid())).glob('niri.*.sock'))
    assert len(sockets)==1
    args.screens=sorted(json.loads(subprocess.check_output(['niri','msg','--json','outputs'],env=dict(os.environ,NIRI_SOCKET=str(sockets[0])),text=True)))
    assert args.screens
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-wallpaper-tools.qml')})
        for plugin in ((args.plugin,) if args.plugin else ('mpvpaper','video-wallpaper')):
            for scope in ((args.scope,) if args.scope else ('instance','shared')):
                for choice in ((args.choice,) if args.choice else ('clear','random')): run(args,profile,plugin,scope,choice)
        runner.write_json(args.output/'result.json',dict(status='PASS',completeWallpaperAcceptance=False))


if __name__=='__main__': main()
