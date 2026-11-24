#!/usr/bin/env python3
"""Actual battery helper in a private guest mount namespace over disposable sysfs."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.json_evidence import json_matches
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from guest_profile import activate_profile, profile_argument


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--expect-selection-red', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    case, out = args.work_root, args.output
    case.mkdir(); out.mkdir()
    helper = args.plugins / 'battery-monitor-plus/scripts/read_battery_sysfs.sh'
    # Privilege owns only the private mount. Never interpret fixture or plugin
    # source until the namespace child is back to the invoking tester's IDs.
    launcher = ('/usr/bin/mount --bind -- "$1" /sys/class/power_supply\n'
                'export TMPDIR="$2"\n'
                'exec /usr/bin/setpriv --reuid="$3" --regid="$4" --clear-groups --no-new-privs '
                '-- /usr/bin/sh "$5" "$6"')
    rows = []

    def run(name, selection, fixtures, expected):
        source = case / name; source.mkdir()
        for relative, value in fixtures.items():
            path = source / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(str(value) + '\n')
        command = ['sudo', '-n', '/usr/bin/unshare', '--mount', '--propagation', 'private', '--',
                   '/usr/bin/sh', '-ec', launcher, 'namespace', str(source), os.environ['TMPDIR'],
                   str(os.getuid()), str(os.getgid()), str(helper), selection]
        # TMPDIR is set by the strict connector and inside the namespace launcher.
        result = subprocess.run(command, capture_output=True, text=True, timeout=15)
        (out / (name + '.stdout')).write_text(result.stdout); (out / (name + '.stderr')).write_text(result.stderr)
        if result.returncode: raise RuntimeError('namespace helper failure: ' + result.stderr)
        data = json.loads(result.stdout)
        mismatch = {key: dict(expected=value, observed=data.get(key)) for key, value in expected.items()
                    if key not in data or not json_matches(data[key], value)}
        rows.append(dict(name=name, selection=selection, expected=expected, observed=data, mismatch=mismatch))
        if args.expect_selection_red:
            # The characterized old helper aggregated BAT1 and BAT10 despite
            # the explicit BAT10 selector. A broken schema or other mismatch
            # is not a reproduction of that selection failure.
            if name != 'exact-name' or set(mismatch) != {'source', 'capacity'} or not json_matches(
                    {key: data[key] for key in mismatch}, {'source': 'BAT1,BAT10', 'capacity': 57}):
                raise RuntimeError('expected exact-name selection failure: ' + repr(rows[-1]))
            stage_receipt(out / 'result.json', dict(status='PASS', kind='helper-selection-red', rejectedAt=name, rows=rows, helperSha256=hashlib.sha256(helper.read_bytes()).hexdigest()))
            print('BATTERY_SYSFS: SELECTION_RED')
        elif mismatch:
            raise RuntimeError('selected helper mismatch: ' + repr(rows[-1]))

    common = {'BAT1/type': 'Battery', 'BAT1/status': 'Discharging', 'BAT1/capacity': 25, 'BAT1/energy_now': 20000000, 'BAT1/energy_full': 40000000,
              'BAT10/type': 'Battery', 'BAT10/status': 'Charging', 'BAT10/capacity': 90, 'BAT10/power_now': 99000000,
              'AC/type': 'Mains', 'AC/online': 1, 'AC/power_now': 50000000}
    run('exact-name', 'BAT10', common, dict(ok=True, source='BAT10', capacity=90, powerWatts=99))
    if args.expect_selection_red: return
    run('explicit-no-foreign-supply', 'BAT1', common, dict(ok=True, source='BAT1', capacity=25, powerWatts=-1, timeToEmpty=0))
    variants = [
        ('direct-power', {'BAT1/power_now': 7000000}, 7),
        ('current-voltage', {'BAT1/current_now': 1000000, 'BAT1/voltage_now': 12000000}, 12),
        ('hwmon-power', {'BAT1/hwmon0/power1_input': 8000000}, 8),
        ('device-hwmon-power', {'BAT1/device/hwmon/hwmon0/power1_input': 9000000}, 9),
        ('hwmon-current-voltage', {'BAT1/hwmon0/in1_input': 12000, 'BAT1/hwmon0/curr1_input': 1000}, 12),
        ('zero-power', {'BAT1/power_now': 0}, 0)]
    for name, values, watts in variants:
        run(name, '/sys/devices/controlled/BAT1', dict(common, **values), dict(ok=True, source='BAT1', powerWatts=watts, status='Discharging', timeToEmpty=int(20 / watts * 3600) if watts else 0))
    run('upower-native-suffix', '/org/freedesktop/UPower/devices/battery_BAT1', dict(common, **{'BAT1/power_now': 4000000, 'BAT1/status': 'Charging'}), dict(ok=True, source='BAT1', powerWatts=4, status='Charging', timeToFull=18000, timeToEmpty=0))
    charge = {key: value for key, value in common.items() if key not in ('BAT1/energy_now', 'BAT1/energy_full')}
    charge.update({'BAT1/charge_now': 1000000, 'BAT1/charge_full': 3000000, 'BAT1/voltage_now': 12000000, 'BAT1/current_now': 1000000})
    run('charge-energy-conversion', 'BAT1', charge, dict(ok=True, source='BAT1', powerWatts=12, timeToEmpty=3600))
    aggregate = dict(common, **{'BAT10/power_now': 0})
    for selection in ('__default__', 'DisplayDevice'):
        run('aggregate-' + selection, selection, aggregate, dict(ok=True, source='BAT1,BAT10', powerWatts=50))
    run('missing', 'BAT2', common, dict(ok=False, source='', powerWatts=-1))
    result = dict(status='PASS', cases=rows, helperSha256=hashlib.sha256(helper.read_bytes()).hexdigest(), physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); print('BATTERY_SYSFS: PASS ' + str(len(rows)))


if __name__ == '__main__': main()
