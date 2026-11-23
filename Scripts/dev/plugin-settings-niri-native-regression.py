#!/usr/bin/env python3
"""Actual scoped Niri policy pages/native files and inert resource consumers."""
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
import time
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('niri_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

ENDPOINT = r'''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_NIRI_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(run=os.environ['PHA_NIRI_RUN'],endpoint=name,argv=args,pid=os.getpid(),start=start))+'\n');f.flush()
if name=='python3':os.execv('/usr/bin/python3',['python3',*args])
if name=='sh':
 if any('setsid' in arg or 'qs kill' in arg for arg in args):sys.exit(0)
 os.execv('/usr/bin/sh',['sh',*args])
if name=='niri':
 if 'event-stream' in args:
  while True:time.sleep(.1)
 if 'focused-window' in args:print(json.dumps(dict(id=1,workspace_id=1)))
 elif 'windows' in args:print(json.dumps([dict(id=i+1,workspace_id=1,is_floating=False,layout=dict(pos_in_scrolling_layout=[i,0])) for i in range(7)]))
 elif 'workspaces' in args:print(json.dumps([dict(id=1,is_active=True,is_focused=True)]))
elif name=='niri-screensaver-launch' and args==['is-running']:sys.exit(1)
elif name=='niri-screensaver-ctl' and args==['effects']:print('header\nheader\nrain')
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root/scope, args.output/scope
    case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for name in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):(case/name).mkdir(parents=True)
    product = (args.original_plugins or args.plugins)/args.plugin
    shutil.copytree(product, case/'config/plugins'/args.plugin)
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    (case/'requests.jsonl').write_text('')
    for name in ('niri', 'python3', 'sh', 'niri-screensaver-launch', 'niri-screensaver-ctl'):
        endpoint=case/'bin'/name; endpoint.write_text(ENDPOINT); endpoint.chmod(0o755)
    field = 'maxVisible' if args.plugin == 'niri-auto-tile' else 'idleSeconds'
    base, edited_value, sibling_value, following_value = (4, 3, 5, 6) if field == 'maxVisible' else (300, 450, 600, 750)
    shared = dict(enabled=True, maxVisible=base, onlyAtMax=False, perWorkspace=False, workspaceMaxVisible={}, debounceMs=300, maxEventsPerSecond=20, language='auto', opaque='shared') if field == 'maxVisible' else dict(enabled=True, idleSeconds=base, frameRate=60, showClock=False, showNowPlaying=False, cursorHide=True, cursorWarp=False, dismissOnKey=True, randomLogo=False, launcherCommand='niri-screensaver-launch launch', killCommand='niri-screensaver-launch kill', opaque='shared')
    bar=dict(widgets=dict(left=[dict(id='plugin:'+args.plugin,instanceSettings=row) for row in ({'opaque':'selected'},{field:sibling_value,'opaque':'sibling'},{'opaque':'inherited'})]))
    initial=dict(shared=shared,bar=bar);edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field]=edited_value
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset);following['shared'][field]=following_value
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    if not(args.original_plugins or args.omit_origin):
        action=deepcopy(edited);action_values=action['shared'] if scope=='shared' else action['bar']['widgets']['left'][0]['instanceSettings']
        action_values['maxVisible' if field=='maxVisible' else 'enabled']=2 if field=='maxVisible' else False
        expected.update({'runtime-action':action,'runtime-restored':edited})
    runner.write_json(case/'expectations.json',expected)
    runner.write_json(case/'input.json',dict(plugin=args.plugin,field=field,editValue=edited_value,followValue=following_value))
    runner.write_json(case/('config/settings/plugins/'+args.plugin+'.json'),shared);runner.write_json(case/'config/settings/bar.json',bar)
    if args.omit_origin:
        path=case/'config/plugins'/args.plugin/'Settings.qml';text=path.read_text()
        old='applySettings(root.pluginApi.runtimeContext)';assert text.count(old)==1
        path.write_text(text.replace(old,'applySettings()'))
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env=dict(PHA_NIRI_CASE=str(case),PHA_NIRI_SCOPE=scope,PHA_NIRI_OUTPUT=str(out),PHA_NIRI_CONTROL='1' if args.original_plugins or args.omit_origin else '0',PHA_NIRI_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),XDG_CONFIG_HOME=str(case/'external-config'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    rejected=False
    modes=[('edit','')] if args.original_plugins or args.omit_origin else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode,boundary in modes:
        part=out/(mode+('-'+boundary if boundary else ''));part.mkdir();before=hashes(case)
        try:
            text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-niri-native.qml',extra_env=dict(env,PHA_NIRI_RUN=part.name,PHA_NIRI_MODE=mode,PHA_NIRI_BOUNDARY=boundary),extra_lint=tuple(sorted((case/'config/plugins'/args.plugin).glob('*.qml'))),timeout=120)
        except RuntimeError:
            # Original Auto-Tile has an independently retained invalid enum.
            # Admit only its completed consumer red, never a clean lint claim.
            if not args.original_plugins or args.plugin!='niri-auto-tile':raise
            assert (part/'runtime.exit').read_text().strip()=='0'
            lint=(part/'lint.log').read_text()
            assert 'Member "CrashExit" not found on type "Process"' in lint and 'qmllint: FAILED' in lint
            text=(part/'runtime.log').read_text()
            runner.write_json(part/'original-lint.json',dict(status='FAILED',knownInheritedMissingProperty='Process.CrashExit',consumerRedOnly=True))
        assert 'NIRI_NATIVE: PASS '+scope+' '+mode+' '+boundary in text
        assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')),text
        after=hashes(case);runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after));assert mode!='cold' or before==after
        effect=boundary or {'edit':'edited','reset':'reset','follow':'following'}[mode]
        values=dict(expected[effect]['shared'])
        if scope=='instance':values.update(expected[effect]['bar']['widgets']['left'][0]['instanceSettings'])
        wanted=values.get(field,base);observed=json.loads(text.split('NIRI_NATIVE_CONSUMER ')[1].splitlines()[0])
        good=observed==dict(maxVisible=wanted,running=True,barMaxVisible=wanted,panelMaxVisible=wanted) if field=='maxVisible' else len(observed['idle'])==1 and observed['idle'][0]['timeout']==wanted
        if not good:
            assert args.original_plugins or args.omit_origin,(wanted,observed)
            rejected=True
        else:assert not(args.original_plugins or args.omit_origin),'wrong origin escaped'
        if field=='maxVisible':
            # Endpoints inherit the launching run's identity. A late append from
            # a prior process cannot become evidence for a fresh engine.
            rows=[row for row in map(json.loads, (case/'requests.jsonl').read_text().splitlines()) if row['run']==part.name]
            starts=[row for row in rows if row['endpoint']=='python3' and row['argv'] and row['argv'][0].endswith('/auto-tile.py')]
            assert starts,('actual Python daemon admission',part.name)
            actual_argv=starts[-1]['argv'];actual_max=int(actual_argv[actual_argv.index('--max-visible')+1])
            actions=[row['argv'][3:] for row in rows if row['endpoint']=='niri' and row['argv'][:3]==['msg','action','set-column-width']]
            if not rejected:
                assert actual_max==wanted and '--no-only-at-max' in actual_argv,(wanted,actual_argv)
                assert [str(100//min(7,wanted))+'%'] in actions,('real Python redistribution output',wanted,actions)
        else:
            config=case/'external-config/niri-screensaver/config';content=config.read_text()
            assert 'FRAME_RATE="60"' in content and 'SHOW_CLOCK="false"' in content and 'CURSOR_HIDE="true"' in content
            shutil.copy2(config,part/'external-config.txt')
        runner.write_json(part/'consumer.json',dict(status='REJECTED' if rejected else 'PASS',expected=wanted,observed=observed,actualDaemonArgv=actual_argv if field=='maxVisible' else None,actualColumnWidths=actions if field=='maxVisible' else None))
    boundaries=['initial','discarded','edited'] if rejected else list(expected)
    for boundary in boundaries:assert json.loads((out/'persisted'/(boundary+'.json')).read_text())==dict(status='PASS',values=expected[boundary])
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl');rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    for _ in range(100):
        live=[]
        for row in rows:
            path=Path('/proc')/str(row['pid'])/'stat'
            if path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:live.append(row)
        if not live:break
        time.sleep(.02)
    assert not live,live
    stage_receipt(out/'result.json',dict(status='PASS',kind='original-native-red' if args.original_plugins else 'omitted-origin-control' if args.omit_origin else 'native',completeNativeBoundaries=boundaries,nonpublishingColdReaders=[] if rejected else ['edited','reset','following'],endpointRows=len(rows),allEndpointIdentitiesAbsent=True,physicalProof=False))
    runner.remove_completed_installs(case,out)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--plugin',choices=('niri-auto-tile','niri-screensaver'),required=True)
    parser.add_argument('--scope',choices=('instance','shared'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--original-plugins',type=Path)
    oracle.add_argument('--omit-origin',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-niri-native-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-niri-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,scope)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
