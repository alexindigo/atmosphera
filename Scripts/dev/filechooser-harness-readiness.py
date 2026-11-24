#!/usr/bin/env python3
"""Prove the real chooser harness obeys the production settings frontier.

This startup/consumer regression does not replace the complete interaction and
timing suite. The latter retains every assertion and its independent result.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from filechooser_isolation import enter, guest
from filechooser_profile import current_profile, exact_source, profile_argument


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    guest()
    source = args.source.resolve()
    assert exact_source(source)
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*', args.label)
    runtime, output = current_profile().runtime / args.label, current_profile().evidence / args.label
    assert not runtime.exists() and not output.exists()
    harness = subprocess.Popen(['timeout', '--kill-after=5', '90', 'python3', '-B', str(source / 'Scripts/dev/filechooser-harness.py'),
        '--source', str(source), '--label', args.label], env=dict(os.environ))
    probe = runtime / 'shell/filechooser-harness.qml'
    result = dict(passed=False, snapshot=None, errors=[], failure='', shutdownErrors=[])

    def ipc(member):
        return subprocess.check_output(['timeout', '5', 'qs', '-p', str(probe), 'ipc', 'call',
            'filechooserHarness', member], text=True, stderr=subprocess.PIPE, timeout=10)

    try:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if harness.poll() is not None:
                raise AssertionError('Harness exited before a ready consumer')
            try:
                state = json.loads(ipc('state'))
                if state['ready'] and state['nativeActive'] and state['count'] > 0 and state['focus'] == 'listing':
                    result['snapshot'] = state
                    break
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.1)
        if result['snapshot'] is None:
            raise AssertionError('Actual chooser did not become ready')
        ipc('quit')
        code = harness.wait(timeout=15)
        text = (output / 'harness.log').read_text()
        result['errors'] = [line for line in text.splitlines() if re.search(
            r'TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign', line)]
        assert code == 0 and not result['errors'], 'Harness startup/runtime diagnostics'
        result['passed'] = True
    except BaseException as error:
        result['failure'] = repr(error)
        raise
    finally:
        if harness.poll() is None:
            try:
                ipc('quit')
            except (OSError, subprocess.SubprocessError) as error:
                result['shutdownErrors'].append(repr(error))
            # The launch deadline remains authoritative even when IPC fails.
            try:
                harness.wait(timeout=100)
            except subprocess.TimeoutExpired as error:
                result['shutdownErrors'].append(repr(error))
        if output.is_dir():
            (output / 'readiness-result.json').write_text(json.dumps(result, indent=2) + '\n')
        print('CHOOSER_HARNESS_READINESS: ' + ('PASS' if result['passed'] else 'FAIL'), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
