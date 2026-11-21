#!/usr/bin/env python3
"""G2 representative native publication joined to inert originating actions."""
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

spec = importlib.util.spec_from_file_location('g2_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys
from pathlib import Path
args=sys.argv[1:];case=Path(os.environ['PHA_G2_CASE']);state=case/'vpn-active'
if args==['-t','-f','NAME,TYPE,STATE,UUID','connection','show']:
 print('Controlled VPN:vpn:'+('activated' if state.exists() else 'deactivated')+':controlled-vpn');raise SystemExit(0)
if Path(sys.argv[0]).name=='nmcli':
 if args not in [['connection','up','uuid','controlled-vpn'],['connection','down','uuid','controlled-vpn']]:raise SystemExit('unreviewed VPN endpoint '+repr(args))
 if args[1]=='up':state.touch()
 elif state.exists():state.unlink()
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
row=dict(argv=args,pid=os.getpid(),start=start)
if Path(sys.argv[0]).name!='nmcli':row.update(fps=os.environ['FPS'],maxSecs=os.environ['MAX_SECS'],outDir=os.environ['OUTDIR'])
with Path(os.environ['PHA_G2_CASE'],'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(row)+'\\n');stream.flush()
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


def run(args, profile, plugin, scope):
    case, out = args.work_root / (plugin + '-' + scope), args.output / (plugin + '-' + scope)
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin); shutil.copytree(args.plugins / plugin, dest)
    runner.write_json(out/'sources.json', {str(p.relative_to(args.plugins)):dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(),mode=p.stat().st_mode & 0o777) for p in sorted((args.plugins/plugin).rglob('*')) if p.is_file()})
    gif = plugin == 'screencast-gif'; field = 'fps' if gif else 'disableToastNotifications'
    shared = dict(fps=10, maxRecordingSeconds=13, outputDir=str(case / 'shared-output'), opaque='shared') if gif else dict(disableToastNotifications=False, displayMode='alwaysShow', connectedColor='primary', disconnectedColor='error', opaque='shared')
    selected = dict(outputDir=str(case / 'selected-output'), maxRecordingSeconds=7, opaque='selected') if gif else dict(opaque='selected')
    sibling = dict(fps=30, outputDir=str(case / 'sibling-output'), maxRecordingSeconds=9, opaque='sibling') if gif else dict(disableToastNotifications=True, opaque='sibling')
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin,instanceSettings=selected),dict(id='plugin:' + plugin,instanceSettings=sibling),dict(id='plugin:' + plugin,instanceSettings=dict(opaque='inherited'))]))
    initial = dict(shared=shared,bar=bar); edited=deepcopy(initial)
    (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field]=24 if gif else True
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset);following['shared'][field]=18 if gif else True
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    for path,value in [('input.json',dict(plugin=plugin)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+plugin+'.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text('')
    endpoint=case/'bin/nmcli' if not gif else dest/'screencast-gif.sh'
    endpoint.write_text(ENDPOINT);endpoint.chmod(0o755)
    wanted='actual capture endpoint receives selected policy' if gif else 'actual toast endpoint receives captured selected policy'
    if args.negative_control:
        path=dest/('BarWidget.qml' if gif else 'Panel.qml');text=path.read_text()
        old,new=('trigger(pluginApi.settingsContext)','trigger()') if gif else ('connectTo(modelData.uuid, pluginApi.settingsContext)','connectTo(modelData.uuid)')
        if text.count(old)!=1:raise RuntimeError('review G2 omitted-caller anchor')
        path.write_text(text.replace(old,new))
    env=dict(PHA_G2_PLUGIN=plugin,PHA_G2_SCOPE=scope,PHA_G2_CONTROL='1' if args.old_red or args.negative_control else '0',PHA_G2_CASE=str(case),PHA_G2_OUTPUT=str(out),PHA_G2_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    for mode,boundary in [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]:
        output=out/(mode+('-'+boundary if boundary else ''));output.mkdir();before=hashes(case)
        try:
            text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-action-native.qml',extra_env=dict(env,PHA_G2_MODE=mode,PHA_G2_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        except RuntimeError:
            if not (args.old_red or args.negative_control) or not (output/'runtime.log').exists() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2':raise
            if not (out/'persisted/edited.json').exists():raise RuntimeError('G2 control did not reach independent native publication')
            result=dict(status='PASS',kind='original-red' if args.old_red else 'rejecting-control',rejectedAt=wanted,completeGroupAcceptance=False)
            runner.write_json(out/'result.json',result);runner.remove_completed_installs(case,out);return result
        if 'G2_NATIVE: PASS '+plugin+' '+scope+' '+mode+' '+boundary not in text or any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('G2 native/action diagnostic failure')
        if mode=='cold' and hashes(case)!=before:raise RuntimeError('G2 cold action reader published preferences')
        runner.write_json(output/'observed.json',dict(status='PASS',hashes=hashes(case),actions=[json.loads(line.split('G2_ACTION ',1)[1]) for line in text.splitlines() if 'G2_ACTION ' in line]))
    if args.old_red or args.negative_control:raise RuntimeError('G2 control escaped')
    for boundary,value in expected.items():
        if json.loads((out/('persisted/'+boundary+'.json')).read_text())!=dict(status='PASS',values=value):raise RuntimeError('G2 complete native documents differ')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    rows=list(map(json.loads,(case/'requests.jsonl').read_text().splitlines()))
    for row in rows:
        path=Path('/proc')/str(row['pid'])/'stat'
        if path.exists() and path.read_text().split(') ',1)[1].split()[19]==row['start']:raise RuntimeError('G2 endpoint process survived')
    result=dict(status='PASS',plugin=plugin,scope=scope,actualPageMainAndOriginatingView=True,nativeBoundaries=sorted(expected),unchangedHashColdReaders=['edited','reset','following'],inertActions=len(rows),physicalProof=False,completeGroupAcceptance=False)
    runner.write_json(out/'result.json',result);runner.remove_completed_installs(case,out);print('G2_NATIVE '+plugin+' '+scope+': PASS',flush=True);return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for key in ('source','plugins','work-root','output'):parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--plugin',choices=('screencast-gif','network-manager-vpn'));parser.add_argument('--scope',choices=('shared','instance'))
    parser.add_argument('--old-red',action='store_true');parser.add_argument('--negative-control',action='store_true')
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-action-native-regression.py':parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and (not args.plugin or args.scope!='instance'):parser.error('control needs explicit instance member')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned profile roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-action-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']})
        results=[run(args,profile,plugin,scope) for plugin in ((args.plugin,) if args.plugin else ('screencast-gif','network-manager-vpn')) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        runner.write_json(args.output/'result.json',dict(status='PASS',cases=results,completeGroupAcceptance=False))


if __name__=='__main__':main()
