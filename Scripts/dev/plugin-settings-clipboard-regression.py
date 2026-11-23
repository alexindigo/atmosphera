#!/usr/bin/env python3
"""Actual clipboard pages, complete native documents and cold Panel consumers."""
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

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('host', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

# Intercept bash before it interprets the original /tmp decode redirects. Only
# list and JSON persistence are exercised here; no real clipboard is accessed.
ENDPOINT = '''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
b=Path(os.environ['PHA_CLIPBOARD_CASE']);args=sys.argv[1:]
if args and args[0].endswith('/Scripts/dev/qmllint.sh'):os.execv('/usr/bin/bash',['bash',*args])
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:f.write(json.dumps(dict(endpoint=Path(sys.argv[0]).name,argv=args,pid=os.getpid(),start=start))+'\\n')
if Path(sys.argv[0]).name=='cliphist':
 if args==['list']:print(''.join(str(i)+'\\tentry-'+str(i)+'\\n' for i in range(1,61)),end='')
 else:raise SystemExit('unexpected clipboard action')
elif len(args)>1 and args[0]=='-c' and args[1].startswith('cliphist list'):
 import subprocess
 payload=''.join(str(i)+'\\tentry-'+str(i)+'\\n' for i in range(1,61))
 if 'head -n ' in args[1]:
  result=subprocess.run(['/usr/bin/head','-n',args[1].split('head -n ',1)[1]],input=payload,text=True,capture_output=True)
  print(result.stdout,end='');raise SystemExit(result.returncode)
 print(payload,end='')
elif len(args)>1 and args[0]=='-c' and args[1]=='printf %s "$1" > "$2"':Path(args[4]).write_text(args[3])
else:raise SystemExit('unexpected shell endpoint '+repr(args))
'''


def hashes(case):
    return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def seed(case, plugins):
    for name in ('config/settings/plugins','cache','state','home','bin'): (case/name).mkdir(parents=True)
    product = case/'config/plugins/clipboard'; shutil.copytree(plugins/'clipboard',product)
    runner.write_json(case/'config/settings.json',dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
    (case/'requests.jsonl').write_text('')
    for name in ('bash','cliphist'):
        path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)
    return product


@receipt_run
def run(args, profile, scope):
    case,out=args.work_root/scope,args.output/scope;case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=seed(case,args.original_plugins or args.plugins)
    if args.shared_reader:
        path=product/'Panel.qml';text=path.read_text()
        old='settingsConsumerFor(pluginApi.settingsContext)';assert text.count(old)==1
        path.write_text(text.replace(old,'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'))
    shared=dict(maxHistorySize=40,showImagePreviews=False,density='compact',opaque='shared')
    initial=dict(shared=shared,bar=dict(widgets=dict(left=[dict(id='plugin:clipboard',instanceSettings=row) for row in ({'opaque':'selected'},{'maxHistorySize':30,'opaque':'sibling'},{'opaque':'inherited'})])))
    edited=deepcopy(initial);(edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['maxHistorySize']=20
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('maxHistorySize')
    following=deepcopy(reset);following['shared']['maxHistorySize']=50
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    runner.write_json(case/'expectations.json',expected);runner.write_json(case/'input.json',dict(plugin='clipboard',field='maxHistorySize',editValue=20,followValue=50))
    runner.write_json(case/'config/settings/plugins/clipboard.json',shared);runner.write_json(case/'config/settings/bar.json',initial['bar'])
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in product.rglob('*') if p.is_file()})
    env=dict(PHA_CLIPBOARD_CASE=str(case),PHA_CLIPBOARD_SCOPE=scope,PHA_CLIPBOARD_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_CLIPBOARD_OUTPUT=str(out),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    controlled=bool(args.original_plugins or args.shared_reader)
    modes=[('edit','')] if controlled else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode,boundary in modes:
        part=out/(mode+('-'+boundary if boundary else ''));part.mkdir();before=hashes(case)
        text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-clipboard-native.qml',extra_env=dict(env,PHA_CLIPBOARD_MODE=mode,PHA_CLIPBOARD_BOUNDARY=boundary),extra_lint=tuple(sorted(product.glob('*.qml'))),timeout=90)
        assert 'CLIPBOARD_NATIVE: PASS '+scope+' '+mode+' '+boundary in text
        assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected'))
        after=hashes(case);runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after))
        if mode=='cold':assert before==after,'cold consumer published'
        observed=json.loads(text.split('CLIPBOARD_NATIVE_CONSUMER ')[1].splitlines()[0])
        good=observed['counts']==observed['wanted'] and observed['rendered']
        assert good != controlled,('selected Panel counts',observed)
        runner.write_json(part/'consumer.json',dict(status='REJECTED' if controlled else 'PASS',observed=observed))
    boundaries=['initial','discarded','edited'] if controlled else list(expected)
    for boundary in boundaries:assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=expected[boundary])
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl');rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        stat=Path('/proc')/str(row['pid'])/'stat';assert not stat.exists() or stat.read_text().split(') ',1)[1].split()[19]!=row['start'],row
    stage_receipt(out/'result.json',dict(status='PASS',scope=scope,kind='original-native-red' if args.original_plugins else 'shared-reader-control' if args.shared_reader else 'native',completeNativeBoundaries=boundaries,nonpublishingColdReaders=[] if controlled else ['edited','reset','following'],endpointRows=len(rows),allEndpointIdentitiesAbsent=True,physicalProof=False))
    runner.remove_completed_installs(case,out)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--original-plugins',type=Path);parser.add_argument('--scope',choices=('instance','shared'))
    parser.add_argument('--shared-reader',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-clipboard-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        inputs=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-clipboard-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))

if __name__=='__main__':main()
