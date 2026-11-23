#!/usr/bin/env python3
"""Explicit-context observation diagnostics; not native page/placement acceptance."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

DATA = {
    'port-monitor': ({'hideSystemPorts': False, 'refreshInterval': 8}, {'hideSystemPorts': True, 'refreshInterval': 1.5}),
    'mullvad': ({'showCityName': False, 'refreshInterval': 8000}, {'showCityName': True, 'refreshInterval': 1500, 'favoriteCountries': ['se'], 'expiryWarningDays': 30}),
    'netbird': ({'compactMode': False, 'showPing': False, 'terminalCommand': 'terminal-base'}, {'compactMode': True, 'showPing': True, 'refreshInterval': 1500, 'terminalCommand': '', 'managementUrl': 'selected.invalid'}),
    'tailscale': ({'compactMode': False, 'refreshInterval': 8000, 'taildropEnabled': False, 'loginServer': 'https://base.invalid'}, {'compactMode': True, 'refreshInterval': 1500, 'taildropEnabled': True, 'taildropReceiveMode': 'operator', 'loginServer': 'https://selected.invalid'}),
    'openvpn3': ({'pollInterval': 8, 'showNotifications': False}, {'pollInterval': 1.5, 'showNotifications': True}),
    'amd-gpu-monitor': ({'deviceIndex': 0}, {'deviceIndex': 1.9}),
    'battery-monitor-plus': ({'deviceNativePath': 'base-battery', 'refreshIntervalSeconds': 5}, {'deviceNativePath': 'selected-battery', 'refreshIntervalSeconds': 1.5}),
}

ENDPOINT = '''#!/usr/bin/python3
import fcntl, json, os, sys, time
from pathlib import Path
name=Path(sys.argv[0]).name
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with Path(os.environ['PHA_OBSERVATION_REQUESTS']).open('a') as stream:
 fcntl.flock(stream, fcntl.LOCK_EX)
 stream.write(json.dumps(dict(command=name,argv=sys.argv[1:],pid=os.getpid(),start=start))+'\\n'); stream.flush()
args=sys.argv[1:]
case=Path(os.environ['PHA_OBSERVATION_CASE'])
stage=os.environ.get('PHA_OBSERVATION_HOLD_STAGE','')
handoff=os.environ.get('PHA_OBSERVATION_HANDOFF')=='1'
extra=os.environ.get('PHA_OBSERVATION_EXTRA_LIFETIME')=='1'
def expire(row):
 (case/f"stage-expired-{row['pid']}-{row['start']}.json").write_text(json.dumps(row))
def hold(label):
 if stage!=label and not (extra and (case/(label+'-hold')).exists()): return
 row=dict(stage=label,pid=os.getpid(),start=start)
 (case/'stage-held').write_text(json.dumps(row))
 deadline=time.monotonic()+15
 while not (case/'stage-release').exists() and time.monotonic()<deadline: time.sleep(.02)
 if not (case/'stage-release').exists():
  expire(row)
  raise SystemExit('controlled stage not released')
if name=='which': print('/controlled/'+args[-1])
elif name=='ss':
 print('State Recv-Q Send-Q Local Address:Port Peer Address:Port Process')
 if args==['-tlnp']:
  print('LISTEN 0 128 127.0.0.1:80 0.0.0.0:* users:(("system",pid=90001,fd=3))')
  print('LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("selected-http",pid=90002,fd=3))')
 elif args==['-ulnp']: print('UNCONN 0 0 127.0.0.1:9090 0.0.0.0:* users:(("selected-udp",pid=90003,fd=3))')
 else: raise SystemExit('unreviewed ss argv')
elif name=='mullvad':
 if args==['status','--json']: print(json.dumps(dict(state='connected',details=dict(endpoint=dict(address='192.0.2.10'),location=dict(country='se',city='Controlled City',ipv4='192.0.2.10',hostname='controlled-host')))))
 elif args==['relay','list']: print('Sweden (se)\\n\\tStockholm (sto)\\n\\t\\tse-sto-wg-001 (192.0.2.20)')
 elif args==['relay','get']: print('Location: country se')
 elif args==['account','get']: print('Expires at: 2099-01-01')
 elif len(args)==2 and args[-1]=='get': print('State: off')
 else: raise SystemExit('unreviewed Mullvad action '+repr(args))
elif name=='netbird' and args==['status','--json']:
 print(json.dumps(dict(management=dict(connected=True,url='https://detected.invalid'),signal=dict(connected=True),netbirdIp='100.64.0.1/16',fqdn='controlled',peers=dict(total=1,connected=1,details=[dict(status='Connected',netbirdIp='100.64.0.2',fqdn='controlled-peer')]))))
elif name=='ping' and args==['-c','1','-W','2','100.64.0.2']:
 hold('ping')
 print('rtt min/avg/max/mdev = 1.0/12.3/14.0/0.1 ms')
elif name in ('ghostty','selected-terminal','gnome-terminal-controlled','terminal-base'):
 expected={'ghostty':['-e','ssh','100.64.0.2'],'selected-terminal':['-e','ssh','100.64.0.2'],'gnome-terminal-controlled':['--','ping','-c','7','100.64.0.2'],'terminal-base':['-e','ssh','100.64.0.2']}
 if args!=expected[name]: raise SystemExit('unreviewed inert terminal arguments '+repr(args))
elif name=='tailscale':
 if args==['status','--json']: print(json.dumps(dict(BackendState='Running',Self=dict(TailscaleIPs=['100.64.0.1']),Peer={})))
 elif args==['switch','--list','--json']: print('[]')
 elif args[:2]==['file','get']:
  target=Path(args[2])
  if target not in ([case/'receive-original',case/'receive-replacement'] if handoff else [case/'receive-original']): raise SystemExit('retargeted controlled receive')
  if target==case/'receive-original': hold('receive')
  (target/'received.txt').write_text('controlled received bytes')
 elif args[:3]==['up','--accept-routes','--force-reauth']: pass
 else: raise SystemExit('unreviewed Tailscale action '+repr(args))
elif name=='ls':
 if handoff and args==['-1',str(case/'receive-replacement')]:
  print('\\n'.join(path.name for path in sorted((case/'receive-replacement').iterdir())))
  raise SystemExit(0)
 if args!=['-1',str(case/'receive-original')]: raise SystemExit('unexpected scan target '+repr(args))
 held=case/'scan-held'
 if not held.exists():
  held.write_text(str(os.getpid()))
  if stage: hold('pre')
  else:
   deadline=time.monotonic()+15
   while not (case/'release').exists() and time.monotonic()<deadline: time.sleep(.05)
   if not (case/'release').exists(): raise SystemExit('controlled scan not released')
 else: hold('post')
 print('\\n'.join(path.name for path in sorted((case/'receive-original').iterdir())))
elif name=='openvpn3':
 if args==['configs-list','--json']: print(json.dumps({'/controlled/config':dict(name='Controlled VPN')}))
 elif args==['sessions-list']: print('Path: /controlled/session\\nConfig name: Controlled VPN\\nStatus: Connected')
 elif args[:1]==['config-manage'] and args[-1]=='--show': print('Persistent config: Yes')
 elif args[:1]==['session-stats']: print(json.dumps(dict(BYTES_IN=1234,BYTES_OUT=5678)))
 elif args[:1]==['log']:
  row=dict(stage='log',pid=os.getpid(),start=start)
  (case/'log-held').write_text(json.dumps(row))
  print('controlled log line',flush=True)
  deadline=time.monotonic()+20
  while time.monotonic()<deadline: time.sleep(.1)
  expire(row)
 elif args==['session-start','--config-path','/controlled/failure']:
  (case/'action-held').write_text(str(os.getpid()))
  deadline=time.monotonic()+15
  while not (case/'release').exists() and time.monotonic()<deadline: time.sleep(.05)
  raise SystemExit(1)
 else: raise SystemExit('unreviewed OpenVPN action '+repr(args))
elif name=='rocm-smi':
 index=int(args[args.index('-d')+1])
 if os.environ.get('PHA_OBSERVATION_GPU_CADENCE')=='1':
  def event(kind):
   with (case/'gpu-cadence.jsonl').open('a') as stream:
    fcntl.flock(stream,fcntl.LOCK_EX)
    stream.write(json.dumps(dict(kind=kind,index=index,pid=os.getpid(),at=time.monotonic()))+'\\n'); stream.flush()
  event('start')
  count=sum(json.loads(line)['kind']=='start' and json.loads(line)['index']==index for line in (case/'gpu-cadence.jsonl').read_text().splitlines())
  if index==1 and count==3: (case/'gpu-1-hold').touch()
 hold('gpu-'+str(index))
 print(json.dumps({'card'+str(index):{'Card Series':'Controlled GPU '+str(index),'GPU use (%)':10+index,'Temperature (Sensor junction) (C)':40+index}}))
 if os.environ.get('PHA_OBSERVATION_GPU_CADENCE')=='1': event('finish')
elif name=='battery-endpoint':
 selected=args==['selected-battery']
 if not selected and args!=['base-battery']: raise SystemExit('unreviewed battery target')
 print(json.dumps(dict(ok=True,status='Charging' if selected else 'Discharging',powerWatts=22.2 if selected else 11.1,timeToEmpty=3600,timeToFull=7200,capacity=75,source=args[0])))
else: raise SystemExit('unreviewed observation endpoint '+name+' '+repr(args))
'''


@receipt_run
def run(args, profile, plugin):
    compile(ENDPOINT, '<controlled-observation-endpoint>', 'exec')
    case, out = args.work_root / plugin, args.output / plugin
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'home', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    runner.write_json(case / 'config/settings.json', {'settingsVersion': 62})
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    manifest = json.loads((dest / 'manifest.json').read_text())
    shared, selected = DATA[plugin]
    if plugin == 'tailscale':
        for name in ('receive-original', 'receive-replacement'):
            (case / name).mkdir()
        (case / 'receive-original/existing.txt').write_text('unrelated bytes')
        selected = dict(selected, taildropDownloadDir=str(case / 'receive-original'))
    if plugin == 'battery-monitor-plus':
        (dest / 'scripts/read_battery_sysfs.sh').write_text('#!/bin/sh\nexec python3 "' + str(case / 'bin/battery-endpoint') + '" "$@"\n')
    runner.write_json(case / 'input.json', dict(directory=str(dest), manifest=manifest, shared=dict(manifest['metadata']['defaultSettings'], **shared), selected=dict(manifest['metadata']['defaultSettings'], **selected)))
    runner.write_json(out / 'source-inputs.json', {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((args.plugins / plugin).rglob('*')) if path.is_file()})
    (case / 'requests.jsonl').write_text('')
    for command in ('which', 'ss', 'mullvad', 'netbird', 'ping', 'tailscale', 'openvpn3', 'rocm-smi', 'battery-endpoint', 'ls', 'ghostty', 'selected-terminal', 'gnome-terminal-controlled', 'terminal-base'):
        path = case / 'bin' / command
        path.write_text(ENDPOINT); path.chmod(0o755)
    if args.taildrop_lifetime or args.extra_lifetime:
        (case / 'bin/stage-retirement-probe').write_text('''import json,os,sys
from pathlib import Path
case=Path(os.environ['PHA_OBSERVATION_CASE'])
row=json.loads((case/(sys.argv[1] if len(sys.argv)>1 else 'stage-held')).read_text())
stat=Path('/proc')/str(row['pid'])/'stat'
try:
 current_start=stat.read_text().split(') ',1)[1].split()[19]
except FileNotFoundError:
 current_start=None
if current_start==row['start']: raise SystemExit(1)
# Expiry is written by this exact process before it exits. Check it only
# after disappearance, so the probe cannot race ahead of that receipt.
if (case/('stage-expired-'+str(row['pid'])+'-'+row['start']+'.json')).exists(): raise SystemExit(2)
if (case/'stage-release').exists(): raise SystemExit('held stage was already released')
result=json.dumps(dict(status='PASS',stage=row['stage'],pid=row['pid'],start=row['start'],beforeRelease=True))
(case/'stage-retired.json').write_text(result)
if os.environ.get('PHA_OBSERVATION_EXTRA_LIFETIME')=='1': (case/(row['stage']+'-retired.json')).write_text(result)
''')
    wanted = 'original shared observation does not apply selected policy' if args.old_red else 'retired receive startup never revives state or dereferences a cleared request' if args.expect_starting_red else None
    if args.lifetime_control:
        path = dest / 'Main.qml'
        text = path.read_text()
        old, count = {'amd-gpu-monitor': ('entry.observer.destroy();', 1), 'netbird': ('pingProcess.running = false;', 1), 'openvpn3': ('_logProc.running = false\n                sessionLogs = []', 2)}[plugin]
        if text.count(old) != count: raise RuntimeError('review unusual observation retirement control anchor')
        path.write_text(text.replace(old, '/* retain controlled held process */' + ('\n                sessionLogs = []' if plugin == 'openvpn3' else '')))
        wanted = 'held observation process retires before source release'
        runner.write_json(out / 'mutation.json', dict(path=plugin + '/Main.qml', old=old, occurrences=count))
    if args.receive_completion_control:
        path = dest / 'Main.qml'; text = path.read_text()
        old = 'if (_taildropOperation !== operation || !taildropRequestCurrent()) return;'
        if text.count(old) != 1: raise RuntimeError('review receive-generation control anchor')
        path.write_text(text.replace(old, 'if (!taildropRequestCurrent()) return;'))
        wanted = 'late originating completion cannot settle replacement receive'
        runner.write_json(out / 'mutation.json', dict(path='tailscale/Main.qml', old=old, new='if (!taildropRequestCurrent()) return;'))
    try:
        text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-observation.qml',
            extra_env=dict(PHA_OBSERVATION_PLUGIN=plugin, PHA_OBSERVATION_CASE=str(case), PHA_OBSERVATION_REQUESTS=str(case / 'requests.jsonl'), PHA_OBSERVATION_OLD_RED='1' if args.old_red else '0', PHA_OBSERVATION_CANCEL_STARTING='1' if args.cancel_starting else '0', PHA_OBSERVATION_HOLD_STAGE='receive' if args.taildrop_lifetime == 'handoff' else args.taildrop_lifetime or '', PHA_OBSERVATION_HANDOFF='1' if args.taildrop_lifetime == 'handoff' else '0', PHA_OBSERVATION_EXTRA_LIFETIME='1' if args.extra_lifetime or args.gpu_cadence else '0', PHA_OBSERVATION_GPU_CADENCE='1' if args.gpu_cadence else '0', HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH']),
            extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=60)
    except RuntimeError:
        if not wanted or wanted not in (out / 'runtime.log').read_text() or (out / 'runtime.exit').read_text().strip() != '2':
            raise
        result = dict(status='PASS', kind='rejecting-observation-retirement-control' if args.lifetime_control else 'rejecting-receive-completion-control' if args.receive_completion_control else 'receive-starting-red' if args.expect_starting_red else 'original-shared-policy-red', rejectedAt=wanted, nativeOrUIAcceptance=False)
    else:
        if wanted or 'OBSERVATION_CONTEXT: PASS ' + plugin not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'OBSERVATION_ASSERT:')):
            raise RuntimeError('observation context outcome/diagnostic failure: ' + plugin)
        result = dict(status='PASS', plugin=plugin, nativeOrUIAcceptance=False, completePlanAcceptance=False)
    shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl')
    requests = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
    if args.gpu_cadence:
        events = [json.loads(line) for line in (case / 'gpu-cadence.jsonl').read_text().splitlines()]
        for index in (0, 1):
            rows = [row for row in events if row['index'] == index]
            starts = [row for row in rows if row['kind'] == 'start']
            finishes = [row for row in rows if row['kind'] == 'finish']
            if len(starts) < 4 or [row['pid'] for row in starts] != [row['pid'] for row in finishes]:
                raise RuntimeError('cadence queries must all start and finish for each device')
            if any(row['at'] - starts[0]['at'] < .75 * i for i, row in enumerate(starts[1:], 1)):
                raise RuntimeError('GPU cadence must not restart immediately after process exit')
            if any(b['at'] < a['at'] for a, b in zip(finishes, starts[1:])):
                raise RuntimeError('GPU cadence must not overlap queries')
        shutil.copy2(case / 'gpu-cadence.jsonl', out / 'gpu-cadence.jsonl')
        result.update(cadenceVerified=True, busyTicksSkipped=True, subscribersRetired=True)
    for row in requests:
        path = Path('/proc') / str(row['pid']) / 'stat'
        if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']:
            raise RuntimeError('owned observation endpoint survived engine')
    if args.extra_lifetime and not args.lifetime_control:
        stages = {'amd-gpu-monitor': ['gpu-1', 'gpu-2'], 'netbird': ['ping'], 'openvpn3': ['log']}[plugin]
        for stage in stages:
            receipt = json.loads((case / (stage + '-retired.json')).read_text())
            if receipt['status'] != 'PASS' or receipt['stage'] != stage or not receipt['beforeRelease']: raise RuntimeError('held observation retirement missing')
            shutil.copy2(case / (stage + '-retired.json'), out / (stage + '-retired.json'))
        if plugin == 'netbird':
            terminals = [row for row in requests if row['command'] in ('ghostty', 'selected-terminal', 'gnome-terminal-controlled', 'terminal-base')]
            if sorted((row['command'], row['argv']) for row in terminals) != [('ghostty', ['-e', 'ssh', '100.64.0.2']), ('gnome-terminal-controlled', ['--', 'ping', '-c', '7', '100.64.0.2']), ('selected-terminal', ['-e', 'ssh', '100.64.0.2'])]: raise RuntimeError('originating selected terminal endpoints differ')
        result.update(heldObservationStages=stages, processRetiredBeforeRelease=True, additionalLifecycleProof=True)
    if args.taildrop_lifetime and not wanted:
        stage = args.taildrop_lifetime
        scans = [row for row in requests if row['command'] == 'ls']
        receives = [row for row in requests if row['command'] == 'tailscale' and row['argv'][:2] == ['file', 'get']]
        if len(scans) != (3 if stage == 'handoff' else 2 if stage == 'post' else 1) or len(receives) != (2 if stage == 'handoff' else 0 if stage == 'pre' else 1): raise RuntimeError('cancelled receive advanced to another stage')
        replacement_files = sorted(p.name for p in (case / 'receive-replacement').iterdir())
        if (case / 'receive-original/received.txt').exists() != (stage == 'post') or replacement_files != (['received.txt'] if stage == 'handoff' else []): raise RuntimeError('cancelled producer files differ')
        if (case / 'receive-original/existing.txt').read_text() != 'unrelated bytes': raise RuntimeError('cancelled producer changed existing content')
        if stage == 'handoff' and (case / 'receive-replacement/received.txt').read_text() != 'controlled received bytes': raise RuntimeError('replacement producer bytes differ')
        retirement = json.loads((case / 'stage-retired.json').read_text())
        if not retirement['beforeRelease'] or retirement['stage'] != ('receive' if stage == 'handoff' else stage): raise RuntimeError('stage process retirement not observed')
        shutil.copy2(case / 'stage-retired.json', out / 'stage-retired.json')
        result.update(heldStage=stage, processRetiredBeforeRelease=True)
    if not args.old_red and not args.cancel_starting and not args.taildrop_lifetime and plugin == 'tailscale':
        receives = [row for row in requests if row['command'] == 'tailscale' and row['argv'][:2] == ['file', 'get']]
        logins = [row for row in requests if row['command'] == 'tailscale' and row['argv'][:1] == ['up']]
        scans = [row for row in requests if row['command'] == 'ls']
        if len(receives) != 1 or receives[0]['argv'] != ['file', 'get', str(case / 'receive-original')] or len(scans) != 2 or any(row['argv'] != ['-1', str(case / 'receive-original')] for row in scans):
            raise RuntimeError('captured receive endpoint chain differs')
        if len(logins) != 1 or logins[0]['argv'] != ['up', '--accept-routes', '--force-reauth', '--login-server=https://selected.invalid']:
            raise RuntimeError('originating selected login endpoint differs')
        if (case / 'receive-original/received.txt').read_text() != 'controlled received bytes' or (case / 'receive-original/existing.txt').read_text() != 'unrelated bytes' or list((case / 'receive-replacement').iterdir()):
            raise RuntimeError('captured receive files differ')
    stage_receipt(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('OBSERVATION_CONTEXT ' + plugin + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, required=True, type=Path)
    parser.add_argument('--plugin', choices=tuple(DATA))
    parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--cancel-starting', action='store_true')
    parser.add_argument('--expect-starting-red', action='store_true')
    parser.add_argument('--taildrop-lifetime', choices=('pre', 'receive', 'post', 'handoff'))
    parser.add_argument('--receive-completion-control', action='store_true')
    parser.add_argument('--extra-lifetime', action='store_true')
    parser.add_argument('--lifetime-control', action='store_true')
    parser.add_argument('--gpu-cadence', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-observation-regression.py':
        parser.error('execute supplied source')
    if args.old_red and not args.plugin:
        parser.error('explicit member required for original red')
    if (args.cancel_starting or args.expect_starting_red or args.taildrop_lifetime) and args.plugin != 'tailscale': parser.error('receive lifetime case requires Tailscale')
    if args.cancel_starting and args.taildrop_lifetime: parser.error('one lifetime case at a time')
    if args.expect_starting_red and not args.cancel_starting: parser.error('starting red needs cancellation case')
    if args.receive_completion_control and args.taildrop_lifetime != 'handoff': parser.error('completion control requires handoff case')
    if args.extra_lifetime and args.plugin not in ('amd-gpu-monitor', 'netbird', 'openvpn3'): parser.error('explicit unusual observation member required')
    if args.lifetime_control and not args.extra_lifetime: parser.error('retirement control requires unusual observation lifetime case')
    if args.gpu_cadence and (args.plugin != 'amd-gpu-monitor' or args.old_red or args.extra_lifetime or args.lifetime_control):
        parser.error('GPU cadence requires its unmodified explicit GPU case')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-observation.qml')}, nativeOrUIAcceptance=False))
        results = [run(args, profile, plugin) for plugin in ((args.plugin,) if args.plugin else DATA)]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, nativeOrUIAcceptance=False, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
