#!/usr/bin/env python3
"""Battery Monitor selected-source/fallback/retirement proof with actual UPower."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--expect-fallback-red', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-battery-monitor-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    runner = module('battery_monitor_runner', args.source / 'Scripts/dev/plugin-settings-host-assets-regression.py')
    peer_module = module('battery_upower_peer', args.source / 'Scripts/dev/fixtures/plugin-settings-upower-peer.py')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output
        case.mkdir(); out.mkdir()
        install = case / 'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'): (case / part).mkdir(parents=True)
        runner.write_json(case / 'config/settings.json', {'settingsVersion': 62})
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        plugin = 'battery-monitor-plus'; dest = case / 'config/plugins' / plugin
        shutil.copytree(args.plugins / plugin, dest)
        runner.write_json(out / 'source-inputs.json', {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins / plugin).rglob('*')) if p.is_file()})
        runner.write_json(case / 'input.json', dict(directory=str(dest), manifest=json.loads((dest / 'manifest.json').read_text())))
        endpoint = case / 'bin/battery-endpoint'
        endpoint.write_text('''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
case=Path(os.environ['PHA_BATTERY_CASE'])
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (case/'requests.jsonl').open('a') as stream:
 fcntl.flock(stream,fcntl.LOCK_EX); stream.write(json.dumps(dict(argv=sys.argv[1:],pid=os.getpid(),start=start))+'\\n')
path=sys.argv[1]
if path=='held-battery':
 (case/'held').write_text(json.dumps(dict(pid=os.getpid(),start=start)))
 deadline=time.monotonic()+15
 while not (case/'release').exists() and time.monotonic()<deadline: time.sleep(.02)
 print(json.dumps(dict(ok=True,powerWatts=99,source='obsolete')))
elif path=='BAT0':
 if (case/'hold-base').exists():
  (case/'base-held').write_text(json.dumps(dict(pid=os.getpid(),start=start)))
  deadline=time.monotonic()+15
  while not (case/'base-release').exists() and time.monotonic()<deadline: time.sleep(.02)
 print(json.dumps(dict(ok=True,status='Discharging',powerWatts=11.1,source='BAT0')))
else: print('malformed-controlled-sysfs')
'''); endpoint.chmod(0o755)
        (case / 'bin/retirement-probe').write_text('''import json,os,sys
from pathlib import Path
case=Path(os.environ['PHA_BATTERY_CASE'])
base=len(sys.argv)>1 and sys.argv[1]=='base'
row=json.loads((case/('base-held' if base else 'held')).read_text())
stat=Path('/proc')/str(row['pid'])/'stat'
if stat.exists() and stat.read_text().split(') ',1)[1].split()[19]==row['start']: raise SystemExit(1)
assert not (case/('base-release' if base else 'release')).exists(), 'helper completed only after release'
(case/('last-retirement.json' if base else 'retirement.json')).write_text(json.dumps(dict(status='PASS',pid=row['pid'],start=row['start'],beforeRelease=True)))
''')
        (dest / 'scripts/read_battery_sysfs.sh').write_text('#!/bin/sh\nexec python3 "' + str(endpoint) + '" "$@"\n')
        (case / 'requests.jsonl').write_text(''); (case / 'upower.jsonl').write_text('')
        with FixtureResources() as resources:
            peer = peer_module.Fixture(case, Path(profile.child_environment('')['XDG_RUNTIME_DIR']), resources)
            try:
                text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-battery-monitor-lifecycle.qml',
                    extra_env=dict(DBUS_SYSTEM_BUS_ADDRESS=peer.address, PHA_BATTERY_CASE=str(case), HOME=str(case / 'home')), extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=50)
            except RuntimeError:
                wanted = 'explicit BAT1 never borrows BAT0 power'
                if not args.expect_fallback_red or wanted not in (out / 'runtime.log').read_text() or (out / 'runtime.exit').read_text().strip() != '2': raise
                result = dict(status='PASS', kind='selected-fallback-red', rejectedAt=wanted, completePlanAcceptance=False)
            else:
                expected_parse = 'Failed to parse sysfs battery data: SyntaxError: JSON.parse: Parse error'
                expected_errors = [line for line in text.splitlines() if 'WARN qml:' in line and 'BatteryMonitor' in line and line.endswith(expected_parse)]
                unexpected = [line for line in text.splitlines() if any(key in line for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'BATTERY_MONITOR_ASSERT:')) and line not in expected_errors]
                if args.expect_fallback_red or 'BATTERY_MONITOR_LIFECYCLE: PASS' not in text or unexpected or len(expected_errors) != 3: raise RuntimeError('battery outcome/diagnostic failure: ' + repr(unexpected))
                result = dict(status='PASS', realUPowerProtocol=True, expectedMalformedHelperErrors=len(expected_errors), nativeOrUIAcceptance=False, completePlanAcceptance=False)
        shutil.copy2(case / 'requests.jsonl', out / 'requests.jsonl'); shutil.copy2(case / 'upower.jsonl', out / 'upower.jsonl')
        shutil.copy2(case / 'bus.log', out / 'bus.log')
        if not args.expect_fallback_red:
            for name in ('retirement.json', 'last-retirement.json'): shutil.copy2(case / name, out / name)
        for row in map(json.loads, (case / 'requests.jsonl').read_text().splitlines()):
            stat = Path('/proc') / str(row['pid']) / 'stat'
            if stat.exists() and stat.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('battery endpoint survived')
        runner.write_json(out / 'result.json', result); runner.remove_completed_installs(case, out)
        print(json.dumps(result))


if __name__ == '__main__': main()
