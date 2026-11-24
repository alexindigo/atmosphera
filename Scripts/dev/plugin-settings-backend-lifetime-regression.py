#!/usr/bin/env python3
"""Actual G4 backend/renderer lifetimes, confined to an explicit guest profile."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('backend_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
MEMBERS = ('auto-cpufreq', 'battery-and-power-management', 'thinkpad-fan')
ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_BACKEND_CASE']);name=Path(sys.argv[0]).name;argv=sys.argv[1:]
hardware=b.resolve()/'hardware'
def hardware_file(path):
 target=Path(path).resolve(strict=True)
 if not target.is_relative_to(hardware) or not target.is_file():
  raise SystemExit('endpoint write outside fixture hardware: '+str(target))
 return target
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(name=name,argv=argv,pid=os.getpid(),start=start))+'\\n');f.flush()
if name=='systemctl':
 assert argv==['is-active','--quiet','auto-cpufreq']
elif name=='powerprofilesctl':
 assert argv==['get'] or len(argv)==2 and argv[0]=='set'
 print('balanced')
elif name=='upower':
  assert len(argv)==2 and argv[0]=='-i'
  if argv[1].endswith('BAT1') and os.environ.get('PHA_BACKEND_VARIANT')=='source':
   while True:time.sleep(.02)
  print('time to empty: 2 hours')
elif name=='sh':
 assert len(argv)==2 and argv[0]=='-c'
 command=argv[1]
 if command.startswith('for d in '):print('BAT0')
 elif command.startswith('for f in '):print('auto' if 'turbo-override' in command else (b/'force').read_text() if (b/'force').exists() else 'default')
 elif command.startswith('echo '):
  left,right=command.split(' > ');target=hardware_file(right)
  value=left.removeprefix('echo ')
  if os.environ.get('PHA_BACKEND_VARIANT')=='actions' and value in ('level 7','95'):
   while True:time.sleep(.02)
  if value.startswith('level '):target.write_text('speed: 2100\\nlevel: '+value[6:]+'\\n')
  else:target.write_text(value+'\\n')
 else:raise SystemExit('unreviewed shell command')
elif name=='pkexec':
  assert len(argv)==2 and argv[0]=='auto-cpufreq' and argv[1].startswith(('--force=','--turbo='))
  if os.environ.get('PHA_BACKEND_VARIANT')=='actions' and argv[1]=='--turbo=always':
   while True:time.sleep(.02)
  if argv[1].startswith('--force='):
   mode=argv[1].split('=',1)[1];(b/'force').write_text(mode)
   hardware_file(hardware/'sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').write_text(mode+'\\n')
else:raise SystemExit('unreviewed endpoint')
'''


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def seed(case, source, plugins, plugin):
    compile(ENDPOINT, '<backend-endpoint>', 'exec')
    for name in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case/name).mkdir(parents=True)
    product = case/'config/plugins'/plugin
    shutil.copytree(plugins/plugin, product)
    hw = case/'hardware'
    for path, text in {
        'sys/devices/system/cpu/cpu0/cpufreq/scaling_governor': 'powersave\n',
        'sys/devices/system/cpu/intel_pstate/no_turbo': '0\n',
        'sys/devices/system/cpu/cpufreq/boost': '1\n',
        'sys/class/thermal/thermal_zone0/temp': '47000\n',
        'proc/acpi/ibm/fan': 'speed: 2100\nlevel: auto\n',
        **{'sys/class/power_supply/'+dev+'/'+name: value for dev in ('BAT0', 'BAT1') for name, value in {
            'uevent': 'POWER_SUPPLY_CAPACITY=64\nPOWER_SUPPLY_STATUS=Discharging\nPOWER_SUPPLY_POWER_NOW=12000000\n',
            'charge_control_end_threshold': '80\n'}.items()}
    }.items():
        p=hw/path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    # Adapt only physical paths in the disposable plugin. Shell interpretation
    # is separately intercepted by the literal-argv endpoint, never executed.
    for path in product.glob('*.qml'):
        text=path.read_text().replace('/sys/', str(hw/'sys')+'/').replace('/proc/acpi/', str(hw/'proc/acpi')+'/')
        path.write_text(text)
    for name in ('sh', 'systemctl', 'powerprofilesctl', 'upower', 'pkexec'):
        p=case/'bin'/name; p.write_text(ENDPOINT); p.chmod(0o755)
    (case/'requests.jsonl').write_text('')
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    shutil.copy2(source/'Assets/ColorScheme/MacOS/MacOS.json', case/'config/colors.json')
    return product


@receipt_run
def run(args, profile, plugin):
    case, out = args.work_root/plugin, args.output/plugin
    case.mkdir(); out.mkdir()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=link_or_copy, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = seed(case, args.source, args.plugins, plugin)
    hw = case/'hardware'
    shared = dict(refreshInterval=9000, compactMode=False, colorAuto='#112233', colorizeByStatus=True,
                  batteryDevice=str(hw/'sys/class/power_supply/BAT0'), opaque='shared')
    overrides = dict(refreshInterval=1700, compactMode=True, colorAuto='#445566',
                     batteryDevice=str(hw/'sys/class/power_supply/BAT1'), opaque='selected')
    runner.write_json(case/('config/settings/plugins/'+plugin+'.json'), shared)
    runner.write_json(case/'config/settings/bar.json', dict(widgets=dict(left=[dict(id='plugin:'+plugin, instanceSettings=overrides)])))
    runner.write_json(out/'sources.json', {str(p.relative_to(args.plugins/plugin)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((args.plugins/plugin).rglob('*')) if p.is_file()})
    before=hashes(case)
    wanted='popup backend survives last renderer retirement'
    try:
        text=runner.run_fixture(profile, install, case, out, args.source/'Scripts/dev/fixtures/plugin-settings-backend-lifetime.qml',
            extra_env=dict(PHA_BACKEND_CASE=str(case), PHA_BACKEND_PLUGIN=plugin, PHA_BACKEND_ORIGINAL='1' if args.original else '0',
                           PHA_BACKEND_VARIANT=args.variant,
                           HOME=str(case/'home'), PATH=str(case/'bin')+':'+os.environ['PATH']),
            extra_lint=tuple(sorted(product.glob('*.qml'))), timeout=90)
    except RuntimeError:
        if not args.original or (out/'runtime.exit').read_text().strip()!='2' or wanted not in (out/'runtime.log').read_text():
            raise
        kind='original-last-renderer-red'
    else:
        if args.original or 'BACKEND_LIFETIME: PASS '+plugin not in text:
            raise RuntimeError('incomplete backend lifetime result')
        if any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')):
            raise RuntimeError('backend lifetime diagnostic')
        kind='backend-lifetime-'+args.variant
    assert before==hashes(case), 'nonpublishing runtime characterization'
    if args.variant == 'actions':
        if plugin == 'thinkpad-fan':
            assert (hw/'proc/acpi/ibm/fan').read_text() == 'speed: 2100\nlevel: 3\n'
        elif plugin == 'battery-and-power-management':
            assert (hw/'sys/class/power_supply/BAT1/charge_control_end_threshold').read_text() == '75\n'
            assert (hw/'sys/class/power_supply/BAT0/charge_control_end_threshold').read_text() == '80\n'
        else:
            assert (hw/'sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text() == 'performance\n'
        runner.write_json(out/'physical-endpoint-bytes.json', {str(p.relative_to(hw)): p.read_text() for p in sorted(hw.rglob('*')) if p.is_file()})
    runner.write_json(out/'configuration-hashes.json', dict(before=before, after=hashes(case)))
    shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
    rows=[json.loads(line) for line in (out/'requests.jsonl').read_text().splitlines()]
    assert rows, 'actual endpoints must execute'
    for row in rows:
        p=Path('/proc')/str(row['pid'])/'stat'
        assert not p.exists() or p.read_text().split(') ',1)[1].split()[19]!=row['start'], 'live synthetic endpoint'
    stage_receipt(out/'result.json', dict(status='PASS', kind=kind, plugin=plugin, endpointRows=len(rows), configurationUnchanged=True, physicalProof=False))
    runner.remove_completed_installs(case, out)
    print('BACKEND_LIFETIME '+plugin+': '+kind, flush=True)


@receipt_run
def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--plugin', choices=MEMBERS)
    parser.add_argument('--original', action='store_true')
    parser.add_argument('--variant', choices=('renderer','actions','source'), default='renderer')
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-backend-lifetime-regression.py':
        parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir();args.output.mkdir()
        for plugin in ((args.plugin,) if args.plugin else MEMBERS):
            run(args,profile,plugin)
        stage_receipt(args.output/'result.json',dict(status='PASS',original=args.original,completeGroupAcceptance=False))


if __name__=='__main__':
    main()
