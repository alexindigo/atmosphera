#!/usr/bin/env python3
"""Unusual niri daemon/config/probe lifetimes with literal inert endpoints."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from guest_profile import activate_profile, profile_argument, protect_owned_process

spec=importlib.util.spec_from_file_location('niri_native',Path(__file__).with_name('plugin-settings-niri-native-regression.py'))
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native);runner=native.runner
SCENARIOS=('auto-typed','auto-hot','auto-restart','auto-retire','screensaver-policy','screensaver-probe','screensaver-retire','screensaver-config','python-children')


def absent(rows):
    for _ in range(150):
        live=[]
        for row in rows:
            path=Path('/proc')/str(row['pid'])/'stat'
            if path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:live.append(row)
        if not live:return True
        time.sleep(.02)
    raise AssertionError(('live owned endpoint',live))


def python_children(args,case,out):
    script=args.plugins/'niri-auto-tile/auto-tile.py';outcomes=[]
    entry="import importlib.util,sys; s=importlib.util.spec_from_file_location('tile',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); {'query':lambda:m.niri_cmd('-j','windows'),'action':lambda:m.niri_action('focus-column-first'),'stream':m.run_event_loop}[sys.argv[2]]()"
    endpoint=case/'bin/niri';endpoint.write_text(native.ENDPOINT.replace("if name=='niri':", "if name=='niri':\n (b/'child-started').touch()\n while not (b/'release-child').exists():time.sleep(.02)"));endpoint.chmod(0o755)
    for kind in ('query','action','stream'):
        (case/'requests.jsonl').write_text('');(case/'child-started').unlink(missing_ok=True)
        env=dict(os.environ,PHA_NIRI_CASE=str(case),PATH=str(case/'bin')+':'+os.environ['PATH'])
        with (out/(kind+'.log')).open('w') as log:
            process=subprocess.Popen([sys.executable,'-B','-c',entry,str(script),kind],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            guard=protect_owned_process(process)
            try:
                deadline=time.monotonic()+8
                while not (case/'child-started').exists() and time.monotonic()<deadline:
                    assert process.poll() is None,'Python parent exited before held child'
                    time.sleep(.02)
                assert (case/'child-started').exists(),'held actual script child'
                rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
                assert len(rows)==1 and rows[0]['endpoint']=='niri',rows
                # Model Process::~Process's direct SIGKILL, not group cleanup.
                process.kill();assert process.wait(timeout=5)==-signal.SIGKILL
                absent(rows);outcomes.append(dict(kind=kind,children=rows,allIdentitiesAbsent=True))
            finally:
                if process.poll() is None:guard.terminate();process.wait(timeout=5)
    with (out/'race.log').open('w') as log:
        result=subprocess.run([sys.executable,'-B',str(script),'--owned-niri-child','1','-j','windows'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=5)
    assert result.returncode!=0 and 'owner already retired' in (out/'race.log').read_text()
    runner.write_json(out/'python-children.json',dict(status='PASS',cases=outcomes,raceRefusedBeforeExec=True))
    return [row for item in outcomes for row in item['children']]


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--scenario',choices=SCENARIOS,required=True);args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-niri-lifetime-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir();case,out=args.work_root,args.output
        for name in ('config/settings','cache','state','home','bin'):(case/name).mkdir(parents=True)
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62));runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]));(case/'requests.jsonl').write_text('')
        plugin='niri-auto-tile' if args.scenario.startswith(('auto-','python-')) else 'niri-screensaver'
        shutil.copytree(args.plugins/plugin,case/'config/plugins'/plugin)
        fingerprints={str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/plugin-settings-niri-native-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-niri-lifetime.qml')}
        runner.write_json(out/'inputs.json',dict(shell=fingerprints,plugin={str(p.relative_to(args.plugins/plugin)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins/plugin).rglob('*') if p.is_file()}))
        if args.scenario=='python-children':rows=python_children(args,case,out)
        else:
            endpoint=native.ENDPOINT.replace("if name=='sh':", "if name=='sh':\n if any('__NIRI_SS_EOF_' in arg for arg in args):\n  while (b/'hold-config').exists() and not (b/'release-config').exists():time.sleep(.02)")
            endpoint=endpoint.replace("elif name=='niri-screensaver-launch' and args==['is-running']:sys.exit(1)","elif name=='niri-screensaver-launch' and args==['is-running']:\n (b/'probe-started').touch()\n while (b/'hold-probe').exists() and not (b/'release-probe').exists():time.sleep(.02)\n sys.exit(1)")
            for name in ('niri','python3','sh','niri-screensaver-launch','shared-launch','shared-kill','selected-launch','selected-kill','later-launch','other-launch','other-kill'):
                path=case/'bin'/name;path.write_text(endpoint);path.chmod(0o755)
            if args.scenario in ('screensaver-probe','screensaver-retire'):(case/'hold-probe').touch()
            if args.scenario=='screensaver-config':(case/'hold-config').touch()
            install=case/'install';shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-niri-lifetime.qml',extra_env=dict(PHA_NIRI_CASE=str(case),PHA_NIRI_SCENARIO=args.scenario,HOME=str(case/'home'),XDG_CONFIG_HOME=str(case/'external-config'),PATH=str(case/'bin')+':'+os.environ['PATH']),extra_lint=tuple(sorted((case/'config/plugins'/plugin).glob('*.qml'))),timeout=60)
            assert 'NIRI_LIFETIME: PASS '+args.scenario in text
            assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')),text
            observed=json.loads(text.split('NIRI_LIFETIME_RESULT ')[1].splitlines()[0]);runner.write_json(out/'observed.json',observed)
            rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
            starts=[row['argv'] for row in rows if row['endpoint']=='python3' and row['argv'] and row['argv'][0].endswith('/auto-tile.py')]
            if args.scenario=='auto-typed':
                argv=starts[-1];assert argv[argv.index('--max-visible')+1]==str(observed['expectedMax']) and argv[argv.index('--max-events')+1]==str(observed['expectedEvents']) and float(argv[argv.index('--debounce')+1])==observed['expectedDebounce']/1000 and '--no-only-at-max' in argv and '--workspace-config' in argv
            if args.scenario=='auto-hot':
                config=json.loads((case/'config/plugins/niri-auto-tile/runtime-config.json').read_text());assert config==dict(maxVisible=2,onlyAtMax=True,perWorkspace=True,workspaceMaxVisible={'1':2}),config
                assert any(row['endpoint']=='niri' and row['argv']==['msg','action','set-column-width','50%'] for row in rows),'actual reloaded Python redistribution consumer'
            if args.scenario=='auto-restart':assert starts[-1][starts[-1].index('--max-visible')+1]=='3' and not any('--max-visible' in argv and argv[argv.index('--max-visible')+1]=='6' for argv in starts),'superseded restart never starts'
            if args.scenario=='screensaver-probe':assert any(row['endpoint']=='selected-launch' and row['argv']==['literal argument'] for row in rows) and not any(row['endpoint'] in ('later-launch','other-launch') for row in rows),'captured smart-toggle continuation'
            if args.scenario=='screensaver-retire':assert not any(row['endpoint'] in ('selected-launch','later-launch','other-launch','selected-kill') for row in rows),'retired probe cannot dispatch'
            if args.scenario.startswith('screensaver-'):
                config=case/'external-config/niri-screensaver/config';content=config.read_text();shutil.copy2(config,out/'external-config.txt')
                if args.scenario=='screensaver-policy':
                    for line in ('FRAME_RATE="24"','CLOCK_DURATION="7"','NOW_PLAYING_DURATION="9"','CURSOR_HIDE="false"','MULTI_MONITOR_MODE="mirror"','INCLUDE_EFFECTS="rain,\\$literal"'):assert line in content,line
                    assert observed['idle'][0]['timeout']==450 and observed['unlock']=='other-kill' and observed['lock']=='user-hook'
                if args.scenario=='screensaver-config':assert 'FRAME_RATE="48"' in content and observed['idle'][0]['timeout']==900,'latest serialized config wins'
            absent(rows)
            shutil.copy2(case/'requests.jsonl',out/'requests.jsonl');runner.remove_completed_installs(case,out)
        runner.write_json(out/'result.json',dict(status='PASS',scenario=args.scenario,endpointRows=len(rows),allEndpointIdentitiesAbsent=True,physicalProof=False,completeGroupAcceptance=False))
        print('NIRI_LIFETIME: PASS '+args.scenario)


if __name__=='__main__':main()
