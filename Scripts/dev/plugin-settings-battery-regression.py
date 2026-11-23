#!/usr/bin/env python3
"""Actual battery Settings/Main/Panel/Bar with native owners and disk batteries. Guest only."""
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

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed', 'BATTERY_ASSERT:')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, scope):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin', 'devices/BAT0', 'devices/BAT1'):
        (case / part).mkdir(parents=True, exist_ok=True)
    shutil.copytree(args.plugins / 'battery-threshold', case / 'config/plugins/battery-threshold')
    # The real schema/controls stay unchanged; its reference path is redirected
    # to disk so even native shared Reset cannot target a physical sysfs node.
    manifest_path = case / 'config/plugins/battery-threshold/manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['metadata']['defaultSettings']['batteryDevice'] = str(case / 'devices/BAT0')
    runner.write_json(manifest_path, manifest)
    runner.write_json(out / 'synthetic-manifest.json', manifest)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    shared = dict(batteryDevice=str(case / 'devices/BAT0'), chargeThreshold=80, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:battery-threshold', tag='selected', instanceSettings=dict(opaque=dict(keep='selected'))),
                                 dict(id='plugin:battery-threshold', tag='sibling', instanceSettings=dict(batteryDevice=str(case / 'devices/BAT0'), chargeThreshold=80)),
                                 dict(id='plugin:battery-threshold', tag='inherited')]))
    runner.write_json(case / 'config/settings/plugins/battery-threshold.json', shared)
    runner.write_json(case / 'config/settings/bar.json', bar)
    for name, value in (('BAT0', 80), ('BAT1', 60)):
        (case / 'devices' / name / 'model_name').write_text('Synthetic ' + name + '\n')
        (case / 'devices' / name / 'charge_control_end_threshold').write_text(str(value) + '\n')
    initial = dict(shared=deepcopy(shared), bar=deepcopy(bar), batteries=dict(BAT0=80, BAT1=60))
    ipc75 = deepcopy(initial)
    ipc75['shared']['chargeThreshold'] = 75
    ipc75['batteries']['BAT0'] = 75
    edited = deepcopy(initial)
    target = edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings']
    target['batteryDevice'] = str(case / 'devices/BAT1')
    edited['batteries']['BAT1'] = 80
    acted = deepcopy(edited)
    (acted['shared'] if scope == 'shared' else acted['bar']['widgets']['left'][0]['instanceSettings'])['chargeThreshold'] = 65
    acted['batteries']['BAT1'] = 65
    reset_staged = deepcopy(acted)
    reset = deepcopy(acted)
    if scope == 'shared':
        reset['shared'].pop('batteryDevice')
    else:
        reset['bar']['widgets']['left'][0]['instanceSettings'].pop('batteryDevice')
    reset['batteries']['BAT0'] = 65
    retired = deepcopy(reset)
    retired['batteries']['BAT0'] = 70
    cold_expected = deepcopy(reset)
    cold_expected['batteries']['BAT0'] = 65 if scope == 'shared' else 80
    runner.write_json(case / 'expectations.json', dict(initial=initial, ipc75=ipc75, ipc80=initial, discarded=initial, failed=initial, edited=edited, device_failed=edited, acted=acted, reset_staged=reset_staged, reset=reset, retired=retired, cold=cold_expected))
    if args.negative_control:
        name = 'Main.qml' if args.negative_control == 'shared-client' else 'BatteryThresholdService.qml'
        target_path = case / 'config/plugins/battery-threshold' / name
        original = target_path.read_text()
        if args.negative_control == 'shared-client':
            needle = 'function settingsConsumerFor(context) {'
            replacement = needle + '\n        context = pluginApi.settingsContext;'
        else:
            needle = 'runtimeApi.pluginSettings.chargeThreshold = v;'
            replacement = 'runtimeApi = inventory.pluginApi;\n            ' + needle
        if original.count(needle) != 1:
            raise RuntimeError('review battery rejecting-control anchor')
        target_path.write_text(original.replace(needle, replacement, 1))
        runner.write_json(out / 'mutation.json', dict(control=args.negative_control, target=name,
            sha256=hashlib.sha256(target_path.read_bytes()).hexdigest()))
    adapter = case / 'bin/find'
    adapter.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
case=Path(os.environ['PHA_BATTERY_CASE'])
assert sys.argv[1:] == ['/sys/class/power_supply','-exec','find','{}/',';'], repr(sys.argv)
with (case/'enumeration.jsonl').open('a') as stream: stream.write(json.dumps(sys.argv[1:])+'\\n')
for name in ('BAT0','BAT1'): print(case/'devices'/name/'charge_control_end_threshold')
''')
    adapter.chmod(0o700)
    shell_adapter = case / 'bin/sh'
    shell_adapter.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
case=Path(os.environ['PHA_BATTERY_CASE']); out=Path(os.environ['PHA_BATTERY_OUTPUT'])
if len(sys.argv) == 6 and sys.argv[1] == '-c' and sys.argv[3] == 'battery-threshold':
    assert sys.argv[2] == 'printf "%s\\\\n" "$1" > "$2"', repr(sys.argv)
    assert sys.argv[5] in [str(case/'devices'/name/'charge_control_end_threshold') for name in ('BAT0','BAT1')]
    with (out/'writes.jsonl').open('a') as stream: stream.write(json.dumps(sys.argv[1:])+'\\n')
    if (case/('hold-write-'+sys.argv[4])).exists():
        (case/('write-entered-'+sys.argv[4])).touch()
        deadline=time.monotonic()+20
        while not (case/('release-write-'+sys.argv[4])).exists():
            if time.monotonic()>deadline: sys.exit(90)
            time.sleep(.03)
os.execv('/usr/bin/sh',['sh',*sys.argv[1:]])
''')
    shell_adapter.chmod(0o700)
    env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_BATTERY_CASE=str(case), PHA_BATTERY_OUTPUT=str(out),
               PHA_BATTERY_SCOPE=scope, PHA_BATTERY_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-battery-disk.py'))
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-battery.qml'
    try:
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env,
                extra_lint=tuple(sorted((case / 'config/plugins/battery-threshold').glob('*.qml'))), timeout=100)
        except RuntimeError:
            log, code = out / 'runtime.log', out / 'runtime.exit'
            marker = 'Main must retain selected runtime context' if args.negative_control == 'shared-client' else 'BATTERY_DISK acted'
            if not args.negative_control or not log.exists() or not code.exists() or code.read_text().strip() != '2' or marker not in log.read_text():
                raise
            result = dict(status='PASS', kind='rejecting-control', control=args.negative_control,
                          rejectedAt=marker, productionCoverage=False)
            stage_receipt(out / 'result.json', result)
            runner.remove_completed_installs(case, out)
            return result
    finally:
        (case / 'config/settings').chmod(0o700)
        (case / 'config/settings/plugins').chmod(0o700)
        for device_file in (case / 'devices').glob('*/charge_control_end_threshold'):
            device_file.chmod(0o600)
    if 'BATTERY: PASS ' + scope not in text or any(marker in text for marker in BAD):
        raise RuntimeError('actual battery warm consumer failed')
    if args.negative_control:
        raise RuntimeError('battery rejecting control escaped')
    boundaries = ('initial', 'ipc75', 'ipc80', 'discarded', 'failed', 'edited', 'device_failed', 'acted', 'reset_staged', 'reset', 'retired')
    if {p.stem for p in (out / 'persisted').glob('*.json')} != set(boundaries):
        raise RuntimeError('missing independent battery boundaries')
    before = hashes(case)
    cold = out / 'cold'; cold.mkdir()
    text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_BATTERY_COLD='1'), timeout=65)
    if 'BATTERY: COLD_PASS ' + scope not in text or any(marker in text for marker in BAD) or hashes(case) != before:
        raise RuntimeError('nonpublishing independent battery cold consumer failed')
    if not (out / 'persisted/cold.json').is_file() or text.count('BATTERY_COLD_RESTORE ') != 4:
        raise RuntimeError('missing independent cold device/policy outcomes')
    writes = [json.loads(line) for line in (out / 'writes.jsonl').read_text().splitlines()]
    if not writes or not (case / 'enumeration.jsonl').is_file():
        raise RuntimeError('actual battery action/enumeration endpoints were not observed')
    result = dict(status='PASS', scope=scope, bothActualPresentations=True, intermediateBoundaries=list(boundaries),
                   syntheticOnly=True, nativeRuntimeWriter=True, failedEditorRetry=True, fieldReset=True,
                   explicitSharedIpc=True, physicalFailureRetry=True, retiredActionFenced=True,
                   sharedPhysicalState=True, coldSequentialRestores=4, literalWriteArgv=writes,
                   sourceQualified=True, independentColdConsumer=True, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print('BATTERY ' + scope + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance'))
    parser.add_argument('--negative-control', choices=('shared-client', 'shared-writer'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-battery-regression.py':
        parser.error('execute the driver from the supplied source tree')
    if args.negative_control and args.scope != 'instance':
        parser.error('rejecting controls require --scope instance')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        args.baseline_source = args.baseline_plugins = None
        runner.write_json(args.output / 'inputs.json', dict(nativeInputs=runner.input_fingerprints(args),
            shell={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [Path(__file__), *sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-battery*'))]},
            battery={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sorted((args.plugins / 'battery-threshold').rglob('*')) if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))
        print('PLUGIN_SETTINGS_BATTERY: PASS', flush=True)


if __name__ == '__main__':
    main()
