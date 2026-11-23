#!/usr/bin/env python3
"""Clipboard typed projections, shared content and originating decode lifetime."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time

from guest_profile import activate_profile, profile_argument

spec=importlib.util.spec_from_file_location('clipboard',Path(__file__).with_name('plugin-settings-clipboard-regression.py'))
clip=importlib.util.module_from_spec(spec);spec.loader.exec_module(clip);runner=clip.runner
ENDPOINT='''#!/usr/bin/python3
import json,os,re,sys,time
from pathlib import Path
b=Path(os.environ['PHA_CLIPBOARD_CASE']);args=sys.argv[1:];endpoint=Path(sys.argv[0]).name
if endpoint=='bash' and args and args[0].endswith('/Scripts/dev/qmllint.sh'):os.execv('/usr/bin/bash',['bash',*args])
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
row=dict(endpoint=endpoint,argv=args,pid=os.getpid(),start=start)
if endpoint=='bash' and len(args)>1 and args[1].startswith('cliphist decode '):
 row['endpoint']='decode';row['id']=re.match(r'cliphist decode ([0-9]+)',args[1])[1]
with (b/'requests.jsonl').open('a') as f:f.write(json.dumps(row)+'\\n')
if endpoint=='head':
 while args==['-n','3'] and not (b/'release-projection').exists():time.sleep(.02)
 payload=sys.stdin.read()
 import subprocess
 result=subprocess.run(['/usr/bin/head',*args],input=payload,text=True,capture_output=True)
 print(result.stdout,end='');raise SystemExit(result.returncode)
elif endpoint=='cliphist' and args==['list']:print(''.join(str(i)+'\\tentry-'+str(i)+'\\n' for i in range(1,7)),end='')
elif row['endpoint']=='decode':
 while not (b/('release-'+row['id'])).exists():time.sleep(.02)
elif endpoint=='bash' and len(args)>1 and args[1]=='printf %s "$1" > "$2"':Path(args[4]).write_text(args[3])
else:raise SystemExit('unexpected endpoint '+repr(args))
'''


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--omit-origin',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    assert Path(__file__).resolve()==args.source.resolve()/'Scripts/dev/plugin-settings-clipboard-lifetime-regression.py'
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):assert path==path.resolve() and path!=parent and path.is_relative_to(parent)
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);case=args.work_root;out=args.output;case.mkdir();out.mkdir()
        install=case/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        product=clip.seed(case,args.plugins)
        shutil.copy2(args.source/'Assets/ColorScheme/MacOS/MacOS.json',case/'config/colors.json')
        for name in ('head','cliphist','bash'):
            path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)
        if args.omit_origin:
            path=product/'ClipboardItem.qml';text=path.read_text();old='getImage(card.entryId, card.pluginApi.settingsContext)';assert text.count(old)==1;path.write_text(text.replace(old,'getImage(card.entryId)'))
        before=clip.hashes(case)
        fixture=args.source/'Scripts/dev/fixtures/plugin-settings-clipboard-lifetime.qml'
        env=dict(PHA_CLIPBOARD_CASE=str(case),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
        rejected=False
        try:text=runner.run_fixture(profile,install,case,out,fixture,extra_env=env,extra_lint=tuple(sorted(product.glob('*.qml'))),timeout=100)
        except RuntimeError:
            text=(out/'runtime.log').read_text()
            assert args.omit_origin and 'CLIPBOARD_LIFETIME_ASSERT decode: finite lifetime phase' in text,text
            rejected=True
        assert rejected==args.omit_origin
        if not rejected:assert 'CLIPBOARD_LIFETIME: PASS' in text
        assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected'))
        after=clip.hashes(case);assert before==after;runner.write_json(out/'configuration-hashes.json',dict(before=before,after=after))
        shutil.copy2(case/'requests.jsonl',out/'requests.jsonl');rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
        for _ in range(100):
            live=[]
            for row in rows:
                f=Path('/proc')/str(row['pid'])/'stat'
                if f.exists() and f.read_text().split(') ',1)[1].split()[19]==row['start']:live.append(row)
            if not live:break
            time.sleep(.02)
        assert not live,live
        runner.write_json(out/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),fixture,args.source/'Scripts/dev/plugin-settings-clipboard-regression.py')})
        runner.write_json(out/'sources.json',{str(p.relative_to(args.plugins/'clipboard')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/'clipboard').rglob('*') if p.is_file()})
        stage_receipt(out/'result.json',dict(status='PASS',kind='omitted-origin-control' if rejected else 'clipboard-lifetimes',typedZeroNegativeFractional=True,sharedPinsAndTimestamps=True,coalescedDecode=True,retiredQueuedAndHeldDecode=True,allEndpointIdentitiesAbsent=True,endpointRows=len(rows),physicalProof=False))
        runner.remove_completed_installs(case,out)

if __name__=='__main__':main()
