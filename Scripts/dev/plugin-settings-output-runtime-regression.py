#!/usr/bin/env python3
"""Actual output Main/Panel consumers with inert compositor collaborators."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

spec=importlib.util.spec_from_file_location('output_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
from guest_profile import activate_profile,profile_argument

ENDPOINT='''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_OUTPUT_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
if name in ('shared-output','selected-output'):
 selected=name=='selected-output'
 if args==['monitors','-j']:
  print(json.dumps([dict(name='Selected' if selected else 'Shared',width=1280,height=720,refreshRate=59.94,scale=1,x=0,y=0)]))
 elif args==['-t','get_outputs','-r']:
  print(json.dumps([dict(name='Shared' if not selected else 'Selected',current_mode=dict(width=1280,height=720,refresh=59940),rect=dict(x=0,y=0,width=1280,height=720),scale=1)]))
elif name=='niri' and 'outputs' in args:
 print(json.dumps({'Physical':dict(name='Physical',modes=[dict(width=1280,height=720,refresh_rate=60000)],current_mode=0,logical=dict(x=0,y=0,scale=1))}))
'''


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--plugin',choices=('display-settings','monitor-layout'),required=True)
    parser.add_argument('--original-plugins',type=Path)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-output-runtime-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        case,out=args.work_root,args.output;case.mkdir();out.mkdir()
        install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        product=(args.original_plugins or args.plugins)/args.plugin;dest=case/'plugin';shutil.copytree(product,dest)
        for name in ('config','bin','home','cache','state'):(case/name).mkdir()
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62));runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
        for name in ('Shared','Selected'):
            (case/(name+'.kdl')).write_text('output "'+name+'" {\n mode "1280x720"\n scale 1\n}\n')
        for name in ('niri','wlr-randr','udevadm','shared-output','selected-output'):
            path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)
        (case/'requests.jsonl').write_text('')
        runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
        runner.write_json(out/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-output-runtime.qml')})
        wanted='selected config path reaches actual Panel card' if args.plugin=='display-settings' else 'selected backend reaches shared draft layout'
        rejected=False
        try:
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-output-runtime.qml',extra_env=dict(PHA_OUTPUT_CASE=str(case),PHA_OUTPUT_PLUGIN=args.plugin,HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=90)
        except RuntimeError:
            text=(out/'runtime.log').read_text()
            if not args.original_plugins or wanted not in text or (out/'runtime.exit').read_text().strip()!='2':raise
            rejected=True
        if args.original_plugins and not rejected:raise RuntimeError('original output consumer escaped')
        if not rejected and 'OUTPUT_RUNTIME: PASS '+args.plugin not in text:raise RuntimeError('output consumer incomplete')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('unrelated output runtime diagnostics')
        rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
        stage_receipt(out/'result.json',dict(status='PASS',plugin=args.plugin,kind='original-red' if rejected else 'focused-runtime',rejectedAt=wanted if rejected else None,nativeAcceptance=False,physicalProof=False,completeGroupAcceptance=False))
        runner.remove_completed_installs(case,out)


if __name__=='__main__':main()
