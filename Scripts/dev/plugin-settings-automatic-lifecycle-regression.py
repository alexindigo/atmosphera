#!/usr/bin/env python3
"""Automatic-owner held stages and private-bus monitor retirement (guest only)."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import time

from fixture_resources import FixtureResources, start_private_bus
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('automatic_native', Path(__file__).with_name('plugin-settings-automatic-native-regression.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
runner = native.runner

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,signal,sys,time
from pathlib import Path
b=Path(os.environ['PHA_AUTO_CASE']); name=Path(sys.argv[0]).name; args=sys.argv[1:]; scenario=os.environ['PHA_AUTO_SCENARIO']
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
def record(**kw):
 with (b/'requests.jsonl').open('a') as f:
  fcntl.flock(f,fcntl.LOCK_EX); f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start,at=time.monotonic(),**kw))+'\\n'); f.flush()
def wait(tag):
 end=time.monotonic()+18
 while not (b/('release-'+tag)).exists():
  if time.monotonic()>end: raise SystemExit('barrier timeout '+tag)
  time.sleep(.01)
record()
if name=='sh':
 code=args[1]
 if 'HYPRLAND_INSTANCE_SIGNATURE' in code and 'printf niri' in code: print('niri')
 elif 'inotifywait -m' in code:
  while True: time.sleep(.1)
 elif 'if [ -f "$1" ]' in code:
  if scenario=='state-file' and args[-1].endswith('state-old'): wait('old-state')
  print('on' if scenario=='sensor' else 'off')
 elif '/tmp/2-in-1-tools.log' in code: pass
 elif 'socket="$XDG_RUNTIME_DIR' in code:
  while True: time.sleep(.1)
 elif code.startswith('monitor-sensor --accel'): print('Accelerometer orientation: normal')
 elif str(b) in code and code.startswith(("test -f '", "find '", "for d in '")): os.execv('/usr/bin/sh',['sh',*args])
 else: raise SystemExit('Unreviewed shell endpoint '+repr(args))
elif name=='monitor-sensor':
 wait('sensor'); print('Accelerometer orientation changed: left-up',flush=True)
 while True: time.sleep(.1)
elif name=='niri' and '--json' in args: print(json.dumps({'eDP-test':{'logical':{'transform':(b/'transform').read_text() if (b/'transform').exists() else '180'}}}))
elif name=='niri' and 'transform' in args:
 (b/'transform').write_text(args[-1])
elif name=='hyprctl':
 if args==['-j','devices']:
  if scenario in ('touch','retire-touch'): wait('touch')
  print(json.dumps({'touch':[{'name':'touch-one','output':'eDP-test'},{'name':'touch-two','output':'eDP-test'}]}))
 elif args[:2]==['keyword','monitor']:
  if scenario in ('apply','retire-apply'): wait('apply')
 elif args==['-j','monitors']: print(json.dumps([dict(name='eDP-test',width=1280,height=720,refreshRate=60,scale=1,transform=2)]))
elif name=='which':
 if scenario=='detect' and args[0]=='wvkbd-old': wait('detect')
 print(str(b/'bin'/args[0]))
elif name=='pgrep': sys.exit(1)
elif name.startswith('wvkbd-'):
 signal.signal(signal.SIGUSR1,lambda sig,frame:record(event='signal',value=sig))
 signal.signal(signal.SIGUSR2,lambda sig,frame:record(event='signal',value=sig))
 while True:time.sleep(.01)
elif name=='gsettings':
 if args[0]=='get': print('false')
elif name=='dconf':
 while True:time.sleep(.1)
elif name=='busctl':
 if scenario=='backend-detect': wait('backend-detect'); sys.exit(0)
 os.execv('/usr/bin/busctl',['busctl',*args])
elif name=='dbus-monitor': os.execv('/usr/bin/dbus-monitor',['dbus-monitor',*args])
'''

PEER = '''import gi,sys
from gi.repository import Gio,GLib
c=Gio.bus_get_sync(Gio.BusType.SESSION,None)
c.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','RequestName',GLib.Variant('(su)',('sm.puri.OSK0',0)),None,0,-1,None)
print('READY',flush=True)
GLib.MainLoop().run()
'''


def live(row):
    path = Path('/proc')/str(row['pid'])/'stat'
    try:
        return path.read_text().split(') ', 1)[1].split()[19] == row['start']
    except FileNotFoundError:
        return False


@receipt_run
def run(args, profile, scenario):
    member = 'osk-toggle' if scenario in ('keyboard', 'detect', 'backend-detect', 'delayed-retire', 'private-monitor', 'private-retire') else '2-in-1-tools'
    case, out = args.work_root/scenario, args.output/scenario
    case.mkdir(); out.mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    shutil.copytree(args.plugins/member, case/'plugin')
    if args.control:
        name, old, new = {
            'apply-policy': ('Main.qml', 'root._requestHyprTouchTransformSync(outputName, root._applyTarget, policy)', 'root._requestHyprTouchTransformSync(outputName, root._applyTarget, root.capturePolicy(root.policyContext))'),
            'exit-policy': ('Main.qml', 'root._autoRotateSessionPolicy?.autoRotateOutsideTabletMode', 'root.autoRotateOutsideTabletMode'),
        }[args.control]
        path = case/'plugin'/name
        text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('stale lifetime control')
        path.write_text(text.replace(old, new))
    for name in ('config','home','cache','state','bin'): (case/name).mkdir()
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6,states={},sources=[]))
    (case/'requests.jsonl').write_text('')
    for name in ('sh','niri','hyprctl','monitor-sensor','which','pgrep','pkill','gsettings','dconf','busctl','dbus-monitor','wvkbd-mobintl','wvkbd-old','wvkbd-new'):
        path=case/'bin'/name; path.write_text(ENDPOINT); path.chmod(0o755)
    product=case/'plugin'
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in product.rglob('*') if p.is_file()})
    env=dict(PHA_AUTO_CASE=str(case),PHA_AUTO_SCENARIO=scenario,HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    with FixtureResources() as resources:
        if scenario in ('private-monitor','private-retire'):
            env['DBUS_SESSION_BUS_ADDRESS'] = start_private_bus(resources, profile.work_base, out/'bus.log')
            (case/'peer.py').write_text(PEER)
        rejected=False
        try:
            text=runner.run_fixture(profile,install,case,out,args.source/'Scripts/dev/fixtures/plugin-settings-automatic-lifecycle.qml',extra_env=env,extra_lint=tuple(sorted(product.rglob('*.qml'))),timeout=100)
        except RuntimeError:
            text=(out/'runtime.log').read_text()
            wanted={'apply-policy':'captured apply keeps touch and notification policy','exit-policy':'session exit retains admitted restore transform'}[args.control] if args.control else ''
            if not wanted or wanted not in text or (out/'runtime.exit').read_text().strip()!='2': raise
            rejected=True
        if args.control and not rejected: raise RuntimeError('automatic lifetime control escaped')
        if not rejected and 'AUTOMATIC_LIFETIME: PASS '+scenario not in text: raise RuntimeError('incomplete automatic lifetime')
        if any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected')): raise RuntimeError('unrelated lifetime diagnostic')
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    deadline=time.monotonic()+6
    while any(live(row) for row in rows) and time.monotonic()<deadline: time.sleep(.02)
    if any(live(row) for row in rows): raise RuntimeError('endpoint survived actual engine teardown')
    shutil.copy2(case/'requests.jsonl',out/'requests.jsonl')
    stage_receipt(out/'result.json',dict(status='PASS',scenario=scenario,kind='runtime-control' if rejected else 'individual-lifetime',control=args.control,endpointIdentities=len(rows),quiescent=True,privateBus=scenario in ('private-monitor','private-retire'),nativeAcceptance=False,physicalProof=False,completeGroupAcceptance=False))
    runner.remove_completed_installs(case,out)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    scenarios=('sensor','apply','touch','retire-apply','retire-touch','exit-restore','restore-retry','state-file','keyboard','detect','backend-detect','delayed-retire','private-monitor','private-retire')
    parser.add_argument('--scenario',choices=scenarios)
    parser.add_argument('--control',choices=('apply-policy','exit-policy'))
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-automatic-lifecycle-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir();args.output.mkdir()
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-automatic-lifecycle.qml')})
        for scenario in ((args.scenario,) if args.scenario else scenarios): run(args,profile,scenario)
        stage_receipt(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))


if __name__=='__main__': main()
