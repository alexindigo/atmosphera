#!/usr/bin/env python3
"""Held output parser/backend/apply lifetimes with actual Main owners."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
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
BARRIER='''
tag=''
scenario=os.environ['PHA_OUTPUT_SCENARIO']
if name=='cat':tag=Path(args[0]).name
elif name=='selected-output':
 if args in (['monitors','-j'],['-t','get_outputs','-r']):tag='fetch'
 else:tag='apply'
if (b/('hold-'+tag)).exists():
 end=time.monotonic()+30
 while not (b/('release-'+tag)).exists():
  if time.monotonic()>end:raise SystemExit('held output endpoint deadline')
  time.sleep(.02)
if name=='cat':os.execv('/usr/bin/cat',['cat',*args])
'''


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--case',choices=('all','parser','fetch','retire-fetch','apply','retire-apply'),default='all')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-output-lifecycle-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-output-lifecycle.qml',args.source/'Scripts/dev/plugin-settings-output-runtime-regression.py',args.source/'Assets/ColorScheme/MacOS/MacOS.json')})
        for scenario in (('parser','fetch','retire-fetch','apply','retire-apply') if args.case=='all' else (args.case,)):
            member='display-settings' if scenario=='parser' else 'monitor-layout';case,out=args.work_root/scenario,args.output/scenario;case.mkdir();out.mkdir()
            install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
            product=args.plugins/member;dest=case/'plugin';shutil.copytree(product,dest)
            for name in ('config','bin','home','cache','state'):(case/name).mkdir()
            runner.write_json(case/'config/settings.json',dict(settingsVersion=62));runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
            # Seed the real reference palette so ENOENT recovery by AtmoColor is
            # outside this query/action witness. Compare every JSON file exactly.
            shutil.copy2(args.source/'Assets/ColorScheme/MacOS/MacOS.json',case/'config/colors.json')
            for name in ('Shared','Selected','Replacement','Retired','Foreign','RetiredChild'):
                (case/(name+'.kdl')).write_text('output "'+name+'" {\n scale 1\n}\n'+('include "Foreign.kdl"\n' if name=='Selected' else 'include "RetiredChild.kdl"\n' if name=='Retired' else ''))
            holds=('Selected.kdl','Retired.kdl') if scenario=='parser' else ('fetch',) if 'fetch' in scenario else ('apply',)
            for name in holds:(case/('hold-'+name)).touch()
            anchor="if name in ('shared-output','selected-output'):"
            if runtime.ENDPOINT.count(anchor)!=1:raise RuntimeError('output barrier anchor stale')
            endpoint=runtime.ENDPOINT.replace(anchor,BARRIER+'\n'+anchor,1)
            for name in ('niri','wlr-randr','udevadm','shared-output','selected-output','cat'):
                path=case/'bin'/name;path.write_text(endpoint);path.chmod(0o755)
            (case/'requests.jsonl').write_text('')
            runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
            before={str(p.relative_to(case)):p.read_bytes() for p in (case/'config').rglob('*.json')}
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-output-lifecycle.qml',extra_env=dict(PHA_OUTPUT_CASE=str(case),PHA_OUTPUT_SCENARIO=scenario,HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=100)
            if 'OUTPUT_LIFETIME: PASS '+scenario not in text or any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('output lifetime incomplete/diagnostic')
            if before!={str(p.relative_to(case)):p.read_bytes() for p in (case/'config').rglob('*.json')}:raise RuntimeError('query/action lifecycle changed native documents')
            rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
            for row in rows:
                stat=Path('/proc')/str(row['pid'])/'stat'
                if stat.exists() and stat.read_text().split(') ',1)[1].split()[19]==row['start']:raise RuntimeError('output endpoint survived')
            shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
            stage_receipt(out/'result.json',dict(status='PASS',plugin=member,scenario=scenario,unchangedNativeDocuments=True,absentEndpointIdentities=len(rows),physicalProof=False,completeGroupAcceptance=False))
            runner.remove_completed_installs(case,out);print('OUTPUT_LIFETIME '+scenario+': PASS',flush=True)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
