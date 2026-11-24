#!/usr/bin/env python3
"""Real-daemon activation isolation and failure/ownership controls."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

from guest_profile import activate_profile, profile_argument, ProcessIdentity, protect_owned_process
from image_decoding_bus import address_for, private_bus


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    out = args.output
    if out != out.resolve() or out.exists() or not out.is_relative_to(profile.journal_base):
        raise ValueError('Fresh canonical guest evidence directory required')
    out.mkdir()
    checks = []

    def check(name, condition, detail):
        checks.append(dict(id=name, passed=bool(condition), detail=detail))
        (out / 'result.json').write_text(json.dumps(dict(checks=checks), indent=2) + '\n')
        print('CASE ' + name + ': ' + ('PASS' if condition else 'FAIL'), flush=True)
        assert condition, name

    def call(address, method, *arguments):
        argv = ['busctl', '--address=' + address, 'call', 'org.freedesktop.DBus',
            '/org/freedesktop/DBus', 'org.freedesktop.DBus', method, *arguments]
        try:
            result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired as error:
            return dict(exit=124, timeout=True, error=repr(error))
        return dict(exit=result.returncode, stdout=result.stdout, stderr=result.stderr)

    data = out / 'data'
    services = data / 'dbus-1/services'
    services.mkdir(parents=True)
    marker = out / 'unexpected-activation'
    helper = out / 'activation.py'
    helper.write_text('from pathlib import Path\nPath(' + repr(str(marker)) + ').write_text("activated")\n')
    service = 'org.atmosphera.ImageFixture'
    (services / (service + '.service')).write_text('[D-BUS Service]\nName=' + service
        + '\nExec=' + sys.executable + ' ' + str(helper) + '\n')
    original_data = os.environ.get('XDG_DATA_HOME')
    os.environ['XDG_DATA_HOME'] = str(data)
    try:
        # Red: the previous --session bus imports arbitrary activation helpers.
        address = address_for(profile)
        with (out / 'original-bus.log').open('w') as log:
            bus = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1', '--address=' + address],
                stdout=subprocess.PIPE, stderr=log, text=True, start_new_session=True)
            guard = protect_owned_process(bus)
            try:
                observed = bus.stdout.readline().strip()
                red = call(observed, 'StartServiceByName', 'su', service, '0')
                check('original-session-activates-unowned-service', observed.startswith(address) and marker.is_file(), red)
            finally:
                guard.terminate()
                bus.wait(timeout=10)
                bus.stdout.close()
        marker.unlink()
        fixed = out / 'isolated'
        fixed.mkdir()
        with private_bus(profile, fixed) as observed:
            active = call(observed, 'ListActivatableNames')
            check('only-bus-is-activatable', active['exit'] == 0 and active['stdout'].strip() == 'as 1 "org.freedesktop.DBus"', active)
            refused = call(observed, 'StartServiceByName', 'su', service, '0')
            check('fixture-cannot-activate-login-service', refused['exit'] != 0 and not refused.get('timeout')
                  and not marker.exists(), refused)
            desktop = call(observed, 'StartServiceByName', 'su', 'org.freedesktop.portal.Desktop', '0')
            check('desktop-portal-not-an-implicit-dependency', desktop['exit'] != 0 and not desktop.get('timeout'), desktop)
        record = json.loads((fixed / 'bus-process.json').read_text())
        check('isolated-bus-joins-exact-launch', record['exit'] == 0 and not record['primaryError']
              and not record['cleanupError'] and not record['escalated'], record)
    finally:
        if original_data is None:
            os.environ.pop('XDG_DATA_HOME', None)
        else:
            os.environ['XDG_DATA_HOME'] = original_data

    primary_root = out / 'primary-failure'
    primary_root.mkdir()
    try:
        with private_bus(profile, primary_root):
            raise ValueError('fixture-primary-sentinel')
    except ValueError as error:
        check('primary-error-survives-normal-cleanup', str(error) == 'fixture-primary-sentinel', repr(error))
    else:
        raise AssertionError('Primary error was swallowed')

    stalled = out / 'stopped-cleanup'
    stalled.mkdir()
    sibling = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True)
    sibling_guard = protect_owned_process(sibling)
    try:
        try:
            with private_bus(profile, stalled) as observed:
                # GetConnectionUnixProcessID observes the real daemon owner.
                pid = int(call(observed, 'GetConnectionUnixProcessID', 's', 'org.freedesktop.DBus')['stdout'].split()[-1])
                captured = ProcessIdentity.read(pid)
                os.kill(pid, signal.SIGSTOP)
                raise ValueError('fixture-primary-with-cleanup-sentinel')
        except BaseExceptionGroup as errors:
            check('both-primary-and-cleanup-errors-retained', len(errors.exceptions) == 2
                  and isinstance(errors.exceptions[0], ValueError)
                  and isinstance(errors.exceptions[1], subprocess.TimeoutExpired), repr(errors))
        else:
            raise AssertionError('Cleanup deadline was hidden')
        record = json.loads((stalled / 'bus-process.json').read_text())
        check('cleanup-deadline-reaps-only-captured-bus', record['escalated'] and record['exit'] == -signal.SIGKILL
              and record['identity']['pid'] == captured.pid and record['identity']['start'] == captured.start
              and not Path('/proc', str(captured.pid)).exists() and sibling.poll() is None, record)
    finally:
        sibling_guard.terminate()
        sibling.wait(timeout=10)
    check('unrelated-owned-control-reaped-separately', sibling.returncode is not None, sibling.returncode)
    print('IMAGE_DECODING_BUS: PASS', flush=True)


if __name__ == '__main__':
    main()
