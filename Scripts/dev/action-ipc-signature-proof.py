#!/usr/bin/env python3
"""Compare action admission with actual Quickshell IPC method registration."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

import action_catalog
from workspace_guard import check_execution_paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    work = args.workspace.resolve()
    check_execution_paths(parser, work, source=source)
    assert subprocess.check_output(['id', '-un'], text=True).strip() == 'tester'
    assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip().lower() == os.environ['ACTION_TEST_VM_UUID'].lower()
    assert subprocess.check_output(['systemd-detect-virt', '--vm'], text=True).strip() in ('qemu', 'kvm')
    work.mkdir()
    cases = [('untyped', 'value', '', ['hello'], False),
             ('variant', 'value: var', '', ['hello'], False),
             ('text', 'value: string', ': string', ['hello'], True),
             ('number', 'value: int', ': int', ['900'], True),
             ('badReturn', '', ': date', [], False),
             ('ten', ', '.join(f'arg{i}: string' for i in range(10)), '', ['hello'] * 10, True),
             ('eleven', ', '.join(f'arg{i}: string' for i in range(11)), '', ['hello'] * 11, False)]
    shell = work / 'shell.qml'
    functions = '\n'.join(f'function {name}({params}){returns} {{ '
        + ('return value;' if name in ('text', 'number') else '') + ' }'
        for name, params, returns, values, accepted in cases)
    shell.write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\n'
        'ShellRoot { Timer { interval: 20000; running: true; onTriggered: Qt.quit() }\n'
        'IpcHandler { target: "signatureProof"\nfunction ready(): bool { return true; }\n'
        'function finish(): void { Qt.quit(); }\n' + functions + '\n} }\n')
    handlers = action_catalog.ipc_handlers(shell, action_catalog.load_lexer(source))
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen')
    def call(method, values=()):
        return subprocess.run(['qs', 'ipc', '-p', str(shell), 'call', 'signatureProof', method, *values],
            env=env, text=True, capture_output=True, timeout=5)
    results = []
    with (work / 'shell.log').open('w') as log:
        child = subprocess.Popen(['qs', '-p', str(shell), '--no-color'], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 10
            while call('ready').stdout.strip() != 'true':
                assert time.monotonic() < deadline and child.poll() is None, 'IPC did not register'
                time.sleep(.05)
            listing = subprocess.run(['qs', 'ipc', '-p', str(shell), 'show'], env=env,
                text=True, capture_output=True, check=True, timeout=5).stdout
            (work / 'registered.txt').write_text(listing)
            for name, params, returns, values, accepted in cases:
                action = dict(id='signature', label='Signature', description='Signature proof.', icon='terminal',
                    command='atmosphera ipc signatureProof ' + name,
                    arguments=[dict(name=f'arg{i}', label='Argument', type='number' if name == 'number' else 'text',
                                    default=900 if name == 'number' else value) for i, value in enumerate(values)])
                errors = action_catalog.action_checks([action], 'plugin', {'terminal'}, handlers)
                actual = call(name, values)
                # This Quickshell CLI prints "Function not found" with rc 0.
                # Registration, not process status, is the native witness.
                registered = bool(re.search(r'\bfunction\s+' + name + r'\(', listing))
                passed = (not errors) == accepted and registered == accepted
                if accepted and name in ('text', 'number'):
                    passed = passed and actual.stdout.strip() == values[0]
                if not accepted:
                    passed = passed and actual.stdout.strip() == 'Function not found.'
                row = dict(name=name, passed=passed, accepted=accepted, lintErrors=errors,
                           registered=registered, exitCode=actual.returncode, stdout=actual.stdout, stderr=actual.stderr)
                results.append(row)
                print(json.dumps(row), flush=True)
        finally:
            if child.poll() is None:
                call('finish')
            child.wait(timeout=25)
    (work / 'result.json').write_text(json.dumps(dict(cases=results, childExitCode=child.returncode), indent=2))
    return 0 if results and all(row['passed'] for row in results) and child.returncode == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
