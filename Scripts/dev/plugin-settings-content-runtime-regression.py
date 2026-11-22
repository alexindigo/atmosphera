#!/usr/bin/env python3
"""Controlled real content-owner lifetimes; no physical clipboard/media actions."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('content_native', Path(__file__).with_name('plugin-settings-content-native-regression.py'))
native = importlib.util.module_from_spec(spec); spec.loader.exec_module(native)
runner = native.runner

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_CONTENT_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='which':print(str(b/'bin/wtype'))
elif name=='wl-paste':
 while (b/'hold-selection').exists():time.sleep(.02)
 print('Admitted selection')
elif name=='cliphist' and args[:1]==['list']:print('1\\tClipboard text')
elif name=='hyprctl':print('{"x":1,"y":1}')
elif name=='music-helper':
 action=args[0]
 while (b/('hold-'+action)).exists():time.sleep(.02)
 if action=='play':print(json.dumps(dict(isPlaying=True,id=args[1],title=args[2],url=args[3],uploader=args[4],duration=int(args[5]),updatedAt='1')))
 elif action=='status':print('{}')
 elif action=='download-mp3':print('/inert/download.mp3')
 elif action=='queue-load-library':print(json.dumps([dict(id='auto',title='Auto',url='https://inert.invalid/auto')]))
 elif action=='queue-enqueue':print(json.dumps([dict(id=args[1],title=args[2],url=args[3])]))
 elif action=='queue-clear':print('[]')
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--plugin',choices=('clipper','music-search'),required=True)
    parser.add_argument('--mutation',choices=('shared-playback','queue-recapture','retired-playback','retired-paste','retired-todo'))
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-content-runtime-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        case,out=args.work_root,args.output;case.mkdir();out.mkdir()
        install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        product=args.plugins/args.plugin;dest=case/'plugin';shutil.copytree(product,dest)
        controls={
            'shared-playback':('music-search','policy.autoSaveMp3AfterPlayback) {','root.autoSaveMp3AfterPlayback) {','captured policy and scalar track after held completion'),
            'queue-recapture':('music-search','root.launchQueueEntry(root.queueEntries[0], undefined, root.queuePolicy);','root.launchQueueEntry(root.queueEntries[0]);','queue continuation retains admitted policy'),
            'retired-playback':('music-search','exitCode === 0 && policy?.context?.current() && policy.autoSaveMp3AfterPlayback','exitCode === 0 && policy.autoSaveMp3AfterPlayback','retired playback cannot download'),
            'retired-paste':('clipper','root.pastePolicy?.context?.current() && root.wtypeAvailable','root.wtypeAvailable','retired delayed paste refused'),
            'retired-todo':('clipper','function addTodoWithText(text, pageId, context, retainedPolicy) {\n    const policy = retainedPolicy || capturePolicy(context);\n    if (!policy?.context?.current() || !policy.enableTodoIntegration)','function addTodoWithText(text, pageId, context, retainedPolicy) {\n    const policy = retainedPolicy || capturePolicy(context);\n    if (!policy || !policy.enableTodoIntegration)','retired selector cannot write shared Todo')}
        if args.mutation:
            member,old,new,wanted=controls[args.mutation]
            if member!=args.plugin:parser.error('mutation belongs to another member')
            path=dest/'Main.qml';text=path.read_text()
            if text.count(old)!=1:raise RuntimeError('stale runtime mutation '+args.mutation)
            path.write_text(text.replace(old,new))
            if args.mutation=='retired-playback':
                text=path.read_text();old='function maybeAutoDownloadCurrentTrack(policy) {\n    if (!policy?.context?.current()) return;'
                if text.count(old)!=1:raise RuntimeError('stale follow-up retirement control')
                path.write_text(text.replace(old,'function maybeAutoDownloadCurrentTrack(policy) {\n    if (!policy) return;'))
        for name in ('config','bin','home','cache','state'):(case/name).mkdir()
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62));runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
        for name in ('cliphist','which','wtype','wl-copy','wl-paste','hyprctl','music-helper'):
            path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)
        if args.plugin=='music-search':(dest/'musicctl.sh').write_text('#!/usr/bin/env bash\nexec "'+str(case/'bin/music-helper')+'" "$@"\n')
        content=case/'home/.config/noctalia/plugins/clipper';(content/'notecards').mkdir(parents=True)
        runner.write_json(content/'pinned.json',dict(items=[dict(id='pin',content='Keep pin')]))
        runner.write_json(content/'notecards/keep.json',dict(id='note',content='Keep note'))
        before={str(p.relative_to(content)):hashlib.sha256(p.read_bytes()).hexdigest() for p in content.rglob('*.json')}
        (case/'requests.jsonl').write_text('')
        runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
        runner.write_json(out/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/plugin-settings-content-native-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-content-runtime.qml')})
        rejected=False
        try:
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-content-runtime.qml',extra_env=dict(PHA_CONTENT_CASE=str(case),PHA_CONTENT_PLUGIN=args.plugin,HOME=str(case/'home'),MUSIC_CACHE_DIR=str(case/'cache'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=120)
        except RuntimeError:
            text=(out/'runtime.log').read_text()
            if not args.mutation or wanted not in text or (out/'runtime.exit').read_text().strip()!='2':raise
            rejected=True
        if args.mutation and not rejected:raise RuntimeError('runtime control escaped')
        if not rejected and 'CONTENT_RUNTIME: PASS '+args.plugin not in text:raise RuntimeError('content lifetime incomplete')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('content runtime diagnostic')
        if before!={str(p.relative_to(content)):hashlib.sha256(p.read_bytes()).hexdigest() for p in content.rglob('*.json')}:raise RuntimeError('shared pin/note bytes changed')
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
        cases=[json.loads(line.split('CONTENT_LIFETIME ',1)[1]) for line in text.splitlines() if 'CONTENT_LIFETIME ' in line]
        runner.write_json(out/'result.json',dict(status='PASS',plugin=args.plugin,kind='runtime-control' if rejected else 'runtime',mutation=args.mutation,rejectedAt=wanted if rejected else None,cases=cases,protectedContent=before,nativeAcceptance=False,physicalProof=False,completeGroupAcceptance=False))
        runner.remove_completed_installs(case,out)


if __name__=='__main__':main()
