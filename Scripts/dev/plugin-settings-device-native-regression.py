#!/usr/bin/env python3
"""Actual device policy pages/native documents and inert final consumers."""
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

from fixture_resources import FixtureResources, start_private_bus
from guest_profile import activate_profile, profile_argument

spec=importlib.util.spec_from_file_location('device_runner',Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)

ENDPOINT='''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_DEVICE_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='sh':
 code=args[1]
 if str(b) in code and code.startswith(("test -f '","find '","for d in '")):os.execv('/usr/bin/sh',['sh',*args])
 else:raise SystemExit('Unreviewed device shell '+repr(args))
elif name=='lsblk':print(json.dumps(dict(blockdevices=[dict(name='fixture',path='/dev/fixture-usb',size='1G',fstype='ext4',label='Fixture USB',mountpoint=str(b/'mounted'),tran='usb',rm=True)])))
elif name=='df':print('Mounted on Use% Used Avail\\n'+str(b/'mounted')+' 10% 100M 900M')
elif name=='udevadm':
 while True:time.sleep(.1)
elif name=='supergfxctl':print('5.2.8\\nHybrid\\n[Integrated, Hybrid, AsusMuxDgpu]\\nNo action required\\nIntegrated')
'''


def hashes(case):return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def run(args,profile,member,scope):
    case,out=args.work_root/(member+'-'+scope),args.output/(member+'-'+scope);case.mkdir();out.mkdir();(out/'persisted').mkdir()
    install=case/'install';shutil.copytree(args.source,install,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=(args.original_plugins or args.plugins)/member;dest=case/('config/plugins/'+member);shutil.copytree(product,dest)
    gpu=member=='noctalia-supergfxctl';field='supergfxctl' if gpu else 'fileBrowser'
    shared=dict(opaque='shared')
    shared[field]=dict(patchPending=True,polling=False,pollingInterval=3000) if gpu else 'yazi'
    if not gpu:shared.update(terminalCommand='kitty',autoMount=False)
    sibling={field:dict(patchPending=False,polling=False,pollingInterval=3000) if gpu else 'thunar', 'opaque':'sibling'}
    bar=dict(widgets=dict(left=[dict(id='plugin:'+member,instanceSettings=row) for row in ({'opaque':'selected'},sibling,{'opaque':'inherited'})]))
    initial=dict(shared=shared,bar=bar);edited=deepcopy(initial)
    owner=edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    owner[field]=dict(patchPending=False,polling=False,pollingInterval=3000) if gpu else 'dolphin'
    reset=deepcopy(edited);(reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following=deepcopy(reset);following['shared'][field]=dict(patchPending=False,polling=False,pollingInterval=3000) if gpu else 'thunar'
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    (case/'config/settings/plugins').mkdir(parents=True)
    for name,value in [('input.json',dict(plugin=member)),('expectations.json',expected),('config/settings.json',dict(settingsVersion=62)),('config/plugins.json',dict(version=6,states={},sources=[])),('config/settings/plugins/'+member+'.json',shared),('config/settings/bar.json',bar)]:runner.write_json(case/name,value)
    for name in ('bin','home','cache','state','mounted'):(case/name).mkdir()
    (case/'requests.jsonl').write_text('')
    for name in ('sh','lsblk','df','udevadm','udisksctl','kitty','dolphin','thunar','yazi','supergfxctl'):
        path=case/'bin'/name;path.write_text(ENDPOINT);path.chmod(0o755)
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    env=dict(PHA_DEVICE_CASE=str(case),PHA_DEVICE_SCOPE=scope,PHA_DEVICE_PLUGIN=member,PHA_DEVICE_OUTPUT=str(out),PHA_DEVICE_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    with FixtureResources() as resources:
        if gpu:
            env['DBUS_SESSION_BUS_ADDRESS'] = start_private_bus(resources, profile.work_base, out/'bus.log',
                publish=lambda value: runner.write_json(out/'private-bus.json', value), diskBacked=True)
        rejected=False
        modes=[('edit','')] if args.original_plugins else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
        for mode,boundary in modes:
            part=out/(mode+('-'+boundary if boundary else ''));part.mkdir();before=hashes(case)
            try:
                text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-device-native.qml',extra_env=dict(env,PHA_DEVICE_MODE=mode,PHA_DEVICE_BOUNDARY=boundary),extra_lint=tuple(sorted(dest.rglob('*.qml'))),timeout=120)
            except RuntimeError:
                text=(part/'runtime.log').read_text();wanted='selected pending policy reaches actual GPU consumer' if gpu else 'selected browser reaches actual Panel action endpoint'
                if not args.original_plugins or wanted not in text or (part/'runtime.exit').read_text().strip()!='2':raise
                rejected=True
            if not rejected and 'DEVICE_NATIVE: PASS '+scope+' '+mode+' '+boundary not in text:raise RuntimeError('incomplete device native case')
            if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')):raise RuntimeError('unrelated device native diagnostic')
            after=hashes(case);runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after,nonpublishing=before==after))
            if mode=='cold' and before!=after:raise RuntimeError('device cold reader published')
    if args.original_plugins and not rejected:raise RuntimeError('original device policy escaped')
    wanted=['initial','discarded','edited'] if rejected else list(expected)
    for boundary in wanted:
        if json.loads((out/'persisted'/(boundary+'.json')).read_text())!=dict(status='PASS',values=expected[boundary]):raise RuntimeError('device complete native documents differ')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    runner.write_json(out/'result.json',dict(status='PASS',plugin=member,scope=scope,kind='original-native-red' if rejected else 'native',completeNativeBoundaries=wanted,nonpublishingColdReaders=[] if rejected else ['edited','reset','following'],privateBus=gpu,physicalProof=False,completeGroupAcceptance=False))
    runner.remove_completed_installs(case,out)


def main():
    parser=argparse.ArgumentParser(description=__doc__);profile_argument(parser)
    for name in ('source','plugins','work-root','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--plugin',choices=('usb-drive-manager','noctalia-supergfxctl'));parser.add_argument('--scope',choices=('instance','shared'));parser.add_argument('--original-plugins',type=Path)
    args=parser.parse_args();profile=activate_profile(args.guest_profile);profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-device-native-regression.py':parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-device-native.qml',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py')})
        for member in ((args.plugin,) if args.plugin else ('usb-drive-manager','noctalia-supergfxctl')):
            for scope in ((args.scope,) if args.scope else ('instance','shared')):run(args,profile,member,scope)
        runner.write_json(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__':main()
