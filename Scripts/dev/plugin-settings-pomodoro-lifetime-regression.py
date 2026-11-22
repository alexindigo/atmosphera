#!/usr/bin/env python3
"""Controlled source/int/phase/timer/alarm and retirement Pomodoro endpoints."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument
spec=importlib.util.spec_from_file_location('pomo_life_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
def main():
    p=argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source','plugins','work-root','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--control',choices=('retirement','auto','destroy'))
    args=p.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source/'Scripts/dev/plugin-settings-pomodoro-lifetime-regression.py': p.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): p.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        case=args.work_root; install=case/'install'
        shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        for part in ('config/settings','cache','state'): (case/part).mkdir(parents=True)
        dest=case/'config/plugins/pomodoro'; shutil.copytree(args.plugins/'pomodoro',dest)
        controls={
            'retirement': ('if (!current) return;', 'if (false) return;', 'retired action and queued auto-start refuse'),
            'auto': ('generation !== root.actionGeneration', 'false', 'later action fences delayed auto-start'),
            'destroy': ('Component.onDestruction: release()', 'Component.onDestruction: {}', 'Main destruction joins owned alarm before engine exit'),
        }
        if args.control:
            old,new,wanted=controls[args.control]; path=dest/'TimerClient.qml'; text=path.read_text(); assert old in text
            path.write_text(text.replace(old,new)); runner.write_json(args.output/'mutation.json',dict(file='TimerClient.qml',old=old,new=new,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62)); runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
        # Inert physical collaborators expose actual call outcomes without audio.
        (install/'Services/System/SoundService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int plays: 0; property int stops: 0; property bool active: false; function playSound(path, options) { if (!path.endsWith("alarm.mp3") || options.repeat !== true || options.volume !== 0.3) throw new Error("alarm arguments"); plays++; active=true; } function stopSound(path) { stops++; active=false; } }\n')
        (install/'Services/UI/ToastService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int notices: 0; function showNotice(title,message,icon) { if (icon !== "clock") throw new Error("notice icon"); notices++; } }\n')
        fixture=args.source/'Scripts/dev/fixtures/plugin-settings-pomodoro-lifetime.qml'
        runner.write_json(args.output/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),fixture,*sorted(dest.glob('*.qml'))]},physicalCollaborators='inert SoundService and ToastService'))
        try:
            text=runner.run_fixture(profile,install,case,args.output,fixture,extra_env=dict(PHA_POMO_MAIN=(dest/'Main.qml').as_uri()),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=60)
        except RuntimeError:
            text=(args.output/'runtime.log').read_text()
            if not args.control or wanted not in text or (args.output/'runtime.exit').read_text().strip()!='2': raise
            runner.write_json(args.output/'result.json',dict(status='PASS',control=args.control,rejectedAt=wanted,completePlanAcceptance=False))
            runner.remove_completed_installs(case,args.output); return
        if args.control: raise RuntimeError('lifetime control escaped')
        if 'POMO_LIFETIME: PASS ' not in text or any(v in text for v in ('TypeError:','ReferenceError:','SyntaxError:','POMO_LIFE_ASSERT:','Binding loop detected')): raise RuntimeError('lifetime endpoint failure')
        runner.write_json(args.output/'result.json',dict(status='PASS',checks=text.count('POMO_LIFE_CHECK: '),physicalProof=False,completePlanAcceptance=False))
        runner.remove_completed_installs(case,args.output)
if __name__=='__main__': main()
