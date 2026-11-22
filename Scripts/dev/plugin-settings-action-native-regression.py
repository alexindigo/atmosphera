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

HARDWARE_ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
case=Path(os.environ['PHA_G2_CASE']);name=sys.argv[1];args=sys.argv[2:]
if name=='scan_controllers.sh':
 for index in (0,1):print(str(case/('led'+str(index)))+':red|controlled-sony')
 raise SystemExit(0)
if name=='scan_battery.sh':print('73');raise SystemExit(0)
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (case/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX);stream.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');stream.flush()
if name=='write_color.sh':
 deadline=time.monotonic()+12
 while (case/'hold-hardware').exists():
  if time.monotonic()>deadline:raise SystemExit('held hardware deadline')
  time.sleep(.02)
 if (case/'fallback-hardware').exists():print('direct:denied');raise SystemExit(1)
 for path,value in zip(args[:3],args[3:]):Path(path).write_text(value)
 print('direct:ok')
if name=='pkexec':
 _,base,separator,*rgb=args
 for color,value in zip(('red','green','blue'),rgb):Path(base+separator+color).write_text(value)
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
    if args.old_red:
        original=args.baseline_plugins/plugin/'Main.qml'
        shutil.copy2(original,dest/'Main.qml')
        runner.write_json(out/'original-main.json',dict(path=str(original),sha256=hashlib.sha256(original.read_bytes()).hexdigest(),candidateBarAdapter=True))
    gif = plugin == 'screencast-gif'; ds4 = plugin == 'ds4-colors'; nv = plugin == 'nvibrant'
    field = 'fps' if gif else 'color' if ds4 else 'vibranceValue' if nv else 'disableToastNotifications'
    shared = dict(fps=10, maxRecordingSeconds=13, outputDir=str(case / 'shared-output'), opaque='shared') if gif else dict(disableToastNotifications=False, displayMode='alwaysShow', connectedColor='primary', disconnectedColor='error', opaque='shared')
    selected = dict(outputDir=str(case / 'selected-output'), maxRecordingSeconds=7, opaque='selected') if gif else dict(opaque='selected')
    sibling = dict(fps=30, outputDir=str(case / 'sibling-output'), maxRecordingSeconds=9, opaque='sibling') if gif else dict(disableToastNotifications=True, opaque='sibling')
    if ds4:
        shared=dict(color='#0064ff',colorIcon=True,hideOnEmpty=False,recentColors=[],opaque='shared')
        selected=dict(opaque='selected');sibling=dict(color='#112233',opaque='sibling')
    elif nv:
        shared=dict(vibranceValue=128,displayIndex=1,enabled=False,opaque='shared')
        selected=dict(displayIndex=3,opaque='selected');sibling=dict(vibranceValue=768,displayIndex=2,opaque='sibling')
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin,instanceSettings=selected),dict(id='plugin:' + plugin,instanceSettings=sibling),dict(id='plugin:' + plugin,instanceSettings=dict(opaque='inherited'))]))
    initial = dict(shared=shared,bar=bar); edited=deepcopy(initial)
    target=edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    target[field]=24 if gif else '#334455' if ds4 else 640 if nv else True
    if ds4:target['recentColors']=['#334455']
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset);following['shared'][field]=18 if gif else '#556677' if ds4 else 256 if nv else True
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    if ds4:
        runtime=deepcopy(edited if args.hardware_control else following);runtime['bar']['widgets']['left'][0]['instanceSettings']['color']='#123456'
        expected.update(runtime=runtime,retired=runtime)
    elif nv:
        runtime=deepcopy(edited if args.hardware_control else following);runtime['bar']['widgets']['left'][0]['instanceSettings'].update(displayIndex=3.6,vibranceValue=640.6)
        expected.update(runtime=runtime,retired=runtime)
    for path,value in [('input.json',dict(plugin=plugin)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+plugin+'.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/path,value)
    (case/'requests.jsonl').write_text('')
    endpoint=case/'bin/nmcli' if not gif else dest/'screencast-gif.sh'
    endpoint.write_text(ENDPOINT);endpoint.chmod(0o755)
    if ds4 or nv:
        (case/'bin/hardware.py').write_text(HARDWARE_ENDPOINT)
    wrapper='#!/bin/sh\nexec python3 "$PHA_G2_CASE/bin/hardware.py" "$(basename "$0")" "$@"\n'
    if ds4:
        for name in ('scan_controllers.sh','scan_battery.sh','write_color.sh','set_ds4_color.sh'):
            endpoint=dest/'scripts'/name;endpoint.write_text(wrapper);endpoint.chmod(0o755)
        endpoint=case/'bin/pkexec';endpoint.write_text(wrapper);endpoint.chmod(0o755)
    elif nv:
        endpoint=case/'bin/nvibrant';endpoint.write_text(wrapper);endpoint.chmod(0o755)
        if args.old_red:
            # Keep the original numeric shell command while isolating login
            # profile/PATH side effects from the inert executable endpoint.
            endpoint=case/'bin/bash'
            endpoint.write_text('#!/bin/sh\nif [ "$1" = -lc ]; then shift; exec /bin/bash -c "$@"; fi\nexec /bin/bash "$@"\n');endpoint.chmod(0o755)
    wanted='actual capture endpoint receives selected policy' if gif else 'actual hardware endpoint receives selected policy' if ds4 or nv else 'actual toast endpoint receives captured selected policy'
    if args.negative_control:
        path=dest/('Settings.qml' if ds4 else 'BarWidget.qml' if gif or nv else 'Panel.qml');text=path.read_text()
        old,new=('trigger(pluginApi.settingsContext)','trigger()') if gif else ('applyColors(root.pluginApi.runtimeContext, root.valueColor)','applyColors()') if ds4 else ('toggle(pluginApi)','toggle()') if nv else ('connectTo(modelData.uuid, pluginApi.settingsContext)','connectTo(modelData.uuid)')
        if text.count(old)!=1:raise RuntimeError('review G2 omitted-caller anchor')
        path.write_text(text.replace(old,new))
    if args.hardware_control:
        changes={
            'ds4-elevation':('ds4-colors','String(admitted.rgb[0])','String(root.currentR)','direct and elevation retain admitted RGB'),
            'ds4-targets':('ds4-colors','controllers: targets','controllers: controllerPaths.map(path => Object.assign(controllers[path], {path: path}))','hardware gate/physical-byte readback failed'),
            'ds4-writer':('ds4-colors','operation.writer.pluginSettings.color','pluginApi.pluginSettings.color','complete native documents: runtime'),
            'ds4-retirement':('ds4-colors','success && operation.context.current() && operation.writer','success && operation.writer','retired direct completion cannot elevate or start next controller'),
            'nvibrant-type':('nvibrant','property int admittedVibranceValue','property real admittedVibranceValue','original QML int admission preserved for selected command'),
        }
        member,old,new,wanted=changes[args.hardware_control]
        if member!=plugin:raise RuntimeError('hardware control member mismatch')
        path=dest/'Main.qml';text=path.read_text()
        if text.count(old)!=1:raise RuntimeError('review hardware control anchor')
        text=text.replace(old,new)
        if args.hardware_control=='ds4-writer':text=text.replace('operation.writer.saveSettings()', 'pluginApi.saveSettings()')
        if args.hardware_control=='ds4-retirement':
            text=text.replace('operation.context.current()', 'true').replace('admitted.context.current()', 'true')
        path.write_text(text)
    control=args.old_red or args.negative_control or bool(args.hardware_control)
    env=dict(PHA_G2_PLUGIN=plugin,PHA_G2_SCOPE=scope,PHA_G2_CONTROL='1' if args.old_red or args.negative_control else '0',PHA_G2_CASE=str(case),PHA_G2_OUTPUT=str(out),PHA_G2_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    modes=[('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    if ds4 or nv:modes.append(('lifetime','following'))
    # A rejecting lifetime control needs the actual edited native boundary and
    # its unusual consumer, not another copy of every unchanged Reset/cold gate.
    if args.hardware_control:modes=[('edit',''),('lifetime','edited')]
    for mode,boundary in modes:
        output=out/(mode+('-'+boundary if boundary else ''));output.mkdir();before=hashes(case)
        try:
            text=runner.run_fixture(profile,install,case,output,args.source/'Scripts/dev/fixtures/plugin-settings-action-native.qml',extra_env=dict(env,PHA_G2_MODE=mode,PHA_G2_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        except RuntimeError:
            if not control or not (output/'runtime.log').exists() or wanted not in (output/'runtime.log').read_text() or (output/'runtime.exit').read_text().strip()!='2':raise
            if not (out/'persisted/edited.json').exists():raise RuntimeError('G2 control did not reach independent native publication')
            result=dict(status='PASS',kind='original-red' if args.old_red else 'rejecting-control',rejectedAt=wanted,completeGroupAcceptance=False)
            runner.write_json(out/'result.json',result);runner.remove_completed_installs(case,out);return result
        if 'G2_NATIVE: PASS '+plugin+' '+scope+' '+mode+' '+boundary not in text or any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('G2 native/action diagnostic failure')
        if mode=='cold' and hashes(case)!=before:raise RuntimeError('G2 cold action reader published preferences')
        runner.write_json(output/'observed.json',dict(status='PASS',hashes=hashes(case),actions=[json.loads(line.split('G2_ACTION ',1)[1]) for line in text.splitlines() if 'G2_ACTION ' in line]))
    if control:raise RuntimeError('G2 control escaped')
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
    parser.add_argument('--plugin',choices=('screencast-gif','network-manager-vpn','ds4-colors','nvibrant'));parser.add_argument('--scope',choices=('shared','instance'))
    parser.add_argument('--old-red',action='store_true');parser.add_argument('--negative-control',action='store_true')
    parser.add_argument('--hardware-control',choices=('ds4-elevation','ds4-targets','ds4-writer','ds4-retirement','nvibrant-type'))
    parser.add_argument('--baseline-plugins',type=Path)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-action-native-regression.py':parser.error('execute supplied source')
    if (args.old_red or args.negative_control or args.hardware_control) and (not args.plugin or args.scope!='instance'):parser.error('control needs explicit instance member')
    if args.old_red and not args.baseline_plugins:parser.error('original Main control needs baseline source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned profile roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-action-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']})
        results=[run(args,profile,plugin,scope) for plugin in ((args.plugin,) if args.plugin else ('screencast-gif','network-manager-vpn')) for scope in ((args.scope,) if args.scope else ('instance','shared'))]
        runner.write_json(args.output/'result.json',dict(status='PASS',cases=results,completeGroupAcceptance=False))


if __name__=='__main__':main()
