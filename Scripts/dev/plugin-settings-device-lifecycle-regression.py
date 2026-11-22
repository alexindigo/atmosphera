#!/usr/bin/env python3
"""Guest-only device policy barriers, typed polling and private notifications."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('device_native', Path(__file__).with_name('plugin-settings-device-native-regression.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
runner = native.runner

ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_DEVICE_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:];scenario=os.environ['PHA_DEVICE_SCENARIO']
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start,at=time.monotonic()))+'\\n');f.flush()
def wait(tag):
 end=time.monotonic()+18
 while not (b/('release-'+tag)).exists():
  if time.monotonic()>end:raise SystemExit('barrier timeout '+tag)
  time.sleep(.01)
if name=='sh':
 code=args[1]
 if code.startswith('udisksctl unmount -b /dev/fixture-usb '):wait('action')
 elif str(b) in code and code.startswith(("test -f '","find '","for d in '")):os.execv('/usr/bin/sh',['sh',*args])
 else:raise SystemExit('Unreviewed shell '+repr(args))
elif name=='udevadm':
 wait('udev');print('ACTION=add',flush=True)
 while True:time.sleep(.1)
elif name=='lsblk':print(json.dumps(dict(blockdevices=[dict(name='fixture',path='/dev/fixture-usb',size='1G',fstype='ext4',label='Fixture USB',mountpoint='',tran='usb',rm=True)])))
elif name=='df':print('Mounted on Use% Used Avail')
elif name=='udisksctl':wait('action')
elif name=='supergfxctl':
 if args[0]=='--mode':wait('action')
 else:
  with (b/'query-count').open('a+') as f:
   fcntl.flock(f,fcntl.LOCK_EX);f.seek(0);count=int(f.read() or '0')+1;f.seek(0);f.truncate();f.write(str(count));f.flush()
  if scenario in ('gpu-query','gpu-query-retire') and count>1:wait('query')
  print('5.2.8\\nHybrid\\n[Integrated, Hybrid, AsusMuxDgpu]\\nNo action required\\n'+('Integrated' if count>1 else 'None'))
'''

PEER = '''import json,sys
from gi.repository import Gio,GLib
c=Gio.bus_get_sync(Gio.BusType.SESSION,None)
r=c.call_sync('org.freedesktop.Notifications','/org/freedesktop/Notifications','org.freedesktop.Notifications','Notify',GLib.Variant('(susssasa{sv}i)',('device-fixture',0,'','device-policy-probe','private only',[],{},-1)),None,0,5000,None)
print(json.dumps(dict(notificationId=r.unpack()[0],privateBus=True)),flush=True)
'''

SCENARIOS = ('usb-automatic','usb-auto-retire','usb-mount','usb-unmount','usb-eject','usb-action-retire','usb-browser',
             'gpu-polling','gpu-query','gpu-query-retire','gpu-mode','gpu-mode-retire','gpu-notification')
CONTROLS = {
    'usb-completion': ('Main.qml', 'if (admitted.showNotifications)', 'if (root.showNotifications)', 'usb-mount', 'captured USB completion notification policy'),
    'usb-automatic': ('Main.qml', 'autoMountNewDevices(policy.context, policy)', 'autoMountNewDevices()', 'usb-automatic', 'captured automatic policy reaches mount endpoint'),
    'gpu-parser': ('src/Main.qml', 'sgfx.parseOutput(text.trim(), root._refreshPolicy)', 'sgfx.parseOutput(text.trim(), root.capturePolicy())', 'gpu-query', 'captured parser policy reaches pending state'),
    'gpu-mode': ('src/Main.qml', 'root._refreshWithPolicy(policy);', 'root.refresh();', 'gpu-mode', 'mode follow-up retains captured policy'),
}


def live(row):
    try:
        return (Path('/proc')/str(row['pid'])/'stat').read_text().split(') ', 1)[1].split()[19] == row['start']
    except FileNotFoundError:
        return False


def run(args, profile, scenario):
    gpu = scenario.startswith('gpu-')
    member = 'noctalia-supergfxctl' if gpu else 'usb-drive-manager'
    case, out = args.work_root/scenario, args.output/scenario
    case.mkdir(); out.mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = case/'plugin'
    shutil.copytree(args.plugins/member, product)
    if args.control:
        name, old, new, _, _ = CONTROLS[args.control]
        path = product/name
        text = path.read_text()
        if old not in text: raise RuntimeError('stale device lifetime control')
        path.write_text(text.replace(old, new))
    for name in ('config', 'home', 'cache', 'state', 'bin', 'mounted'): (case/name).mkdir()
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    (case/'requests.jsonl').write_text('')
    for name in ('sh','udevadm','lsblk','df','udisksctl','supergfxctl','kitty','wezterm','dolphin'):
        path = case/'bin'/name; path.write_text(ENDPOINT); path.chmod(0o755)
    runner.write_json(out/'sources.json', {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in product.rglob('*') if p.is_file()})
    env = dict(PHA_DEVICE_CASE=str(case), PHA_DEVICE_SCENARIO=scenario, HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH'])
    bus = None
    if gpu:
        socket = profile.work_base/('g2m-bus-'+uuid.uuid4().hex[:12])
        address = 'unix:path='+str(socket)
        bus = subprocess.Popen(['/usr/bin/dbus-daemon','--session','--nofork','--address='+address], stdout=(out/'bus.log').open('w'), stderr=subprocess.STDOUT)
        for _ in range(200):
            if socket.exists(): break
            time.sleep(.01)
        else: raise RuntimeError('private bus unavailable')
        runner.write_json(out/'private-bus.json', dict(pid=bus.pid, start=(Path('/proc')/str(bus.pid)/'stat').read_text().split(') ',1)[1].split()[19], address=address, joined=False))
        env['DBUS_SESSION_BUS_ADDRESS'] = address
        (case/'peer.py').write_text(PEER)
    rejected = False
    try:
        try:
            text = runner.run_fixture(profile, install, case, out, args.source/'Scripts/dev/fixtures/plugin-settings-device-lifecycle.qml', extra_env=env, extra_lint=tuple(sorted(product.rglob('*.qml'))), timeout=100)
        except RuntimeError:
            text = (out/'runtime.log').read_text()
            wanted = CONTROLS[args.control][4] if args.control else ''
            if not wanted or wanted not in text or (out/'runtime.exit').read_text().strip() != '2': raise
            rejected = True
        if not rejected and 'DEVICE_LIFETIME: PASS '+scenario not in text: raise RuntimeError('incomplete device lifetime')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')): raise RuntimeError('unrelated lifetime diagnostic')
    finally:
        if bus:
            bus.terminate(); bus.wait(timeout=5)
            path = out/'private-bus.json'; receipt = json.loads(path.read_text()); receipt.update(joined=True, returncode=bus.returncode); runner.write_json(path, receipt)
    rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    deadline = time.monotonic()+6
    while any(live(row) for row in rows) and time.monotonic()<deadline: time.sleep(.02)
    if any(live(row) for row in rows): raise RuntimeError('device endpoint survived engine teardown')
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    runner.write_json(out/'result.json', dict(status='PASS', scenario=scenario, kind='runtime-control' if rejected else 'individual-lifetime', control=args.control, endpointIdentities=len(rows), quiescent=True, privateBus=gpu, nativeAcceptance=False, physicalProof=False, completeGroupAcceptance=False))
    runner.remove_completed_installs(case, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scenario', choices=SCENARIOS)
    parser.add_argument('--control', choices=CONTROLS)
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-device-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-device-lifecycle.qml',args.source/'Scripts/dev/plugin-settings-device-native-regression.py')})
        scenarios = (CONTROLS[args.control][3],) if args.control else ((args.scenario,) if args.scenario else SCENARIOS)
        for scenario in scenarios: run(args,profile,scenario)
        runner.write_json(args.output/'result.json', dict(status='PASS', completeGroupAcceptance=False))


if __name__ == '__main__': main()
