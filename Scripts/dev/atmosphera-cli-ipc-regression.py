#!/usr/bin/env python3
"""Guest-only CLI reply regression (no running shell needed).

Run in the project VM: python3 Scripts/dev/atmosphera-cli-ipc-regression.py
--work NEW_DISK_BACKED_DIR [--cli OTHER_TREE/Scripts/bash/atmosphera].
The stub mirrors quickshell 0.3.2: IPC diagnostics on stdout with exit 0.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['S10_STUB'])
spec = json.loads((root / 'spec.json').read_text())
log = root / 'calls.jsonl'
calls = log.read_text().splitlines() if log.exists() else []
args = sys.argv[1:]
with log.open('a') as f:
    f.write(json.dumps(args) + '\\n')
if len(calls) >= len(spec) or args != spec[len(calls)]['args']:
    print('unexpected invocation: ' + repr(args), file=sys.stderr)
    sys.exit(97)
reply = spec[len(calls)]
sys.stdout.write(reply['output'])
sys.exit(reply['rc'])
'''
PREFIX = ['-c', 'atmosphera', 'ipc', 'call']
SHORT = ('Too few arguments provided (2 required but 1 were provided.)\n'
         'Function definition: function toggleIM(name: string, group: string): string\n')
ERRORS = [
    'Too many arguments provided (0 required but 1 were provided.)\nFunction definition: function next(): string\n',
    'Unable to parse argument 1 as int. Provided argument: nope\nFunction definition: function test(value: int): void\n',
    'Target not found.\n',
    'Function not found.\n',
    'Not ready to accept queries yet.\n',
    'Target required to send message.\n',
    'Function required to send message.\n',
    'ERROR quickshell.ipc: Received invalid IPC response from IpcClient(0x1234)\n',
    'ERROR quickshell.ipc: Socket Error QLocalSocket::PeerClosedError\n',
    'ERROR quickshell.ipc: Error occurred while waiting for response.\n',
]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', required=True, type=Path)
    ap.add_argument('--cli', type=Path, default=Path(__file__).resolve().parents[1] / 'bash/atmosphera')
    args = ap.parse_args()
    args.work.mkdir(parents=True, exist_ok=False)
    stub = args.work / 'qs'
    stub.write_text(STUB)
    stub.chmod(0o755)
    env = dict(os.environ, PATH=f'{args.work.resolve()}:{os.environ["PATH"]}', S10_STUB=str(args.work.resolve()))
    failures = []
    count = 0

    def check(name, command, calls, output, success=True):
        nonlocal count
        count += 1
        spec = [{'args': PREFIX + params, 'output': text, 'rc': rc} for params, text, rc in calls]
        (args.work / 'spec.json').write_text(json.dumps(spec))
        log = args.work / 'calls.jsonl'
        log.unlink(missing_ok=True)
        p = subprocess.run(['bash', str(args.cli), *command], capture_output=True, text=True, env=env, timeout=15)
        seen = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        passed = ((p.returncode == 0) == success and p.stdout == output and not p.stderr
                  and seen == [row['args'] for row in spec])
        print(f'{name}: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            failures.append(name)
            print(f'  rc={p.returncode} stdout={p.stdout!r} stderr={p.stderr!r} calls={seen!r}', flush=True)

    short_args = ['inputmethod', 'toggleIM', 'mozc']
    for rc in (0, 255):
        check(f'padding-status-{rc}', ['ipc', *short_args],
              [(short_args, SHORT, rc), (short_args + [''], 'ok\n', 0)], 'ok\n')
    many = 'Too few arguments provided (5 required but 0 were provided.)\nFunction definition: function test(a: string, b: string, c: string, d: string, e: string): string\n'
    check('pad-reported-arity', ['ipc', 'test', 'call'],
          [(['test', 'call'], many, 0), (['test', 'call', '', '', '', '', ''], 'ok\n', 0)], 'ok\n')
    for i, error in enumerate(ERRORS):
        check(f'error-{i}', ['ipc', 'test', 'call'], [(['test', 'call'], error, 0)], error, False)
    for rc in (0, 255):
        error = 'No running instances for "/home/tester/.config/quickshell/atmosphera/shell.qml"\n'
        check(f'no-instance-{rc}', ['ipc', 'test', 'call'], [(['test', 'call'], error, rc)], error, False)
    check('other-nonzero', ['ipc', 'test', 'call'], [(['test', 'call'], 'transport failed\n', 42)], 'transport failed\n', False)
    for i, output in enumerate(('ok\n', '\n', 'line one\nline two\n', 'error: unknown input method keyboard-fr\n',
                                'The message said Too few arguments, but this is handler output.\n')):
        check(f'success-{i}', ['ipc', 'test', 'call'], [(['test', 'call'], output, 0)], output)
    check('padded-parse-failure', ['ipc', *short_args],
          [(short_args, SHORT, 0), (short_args + [''], ERRORS[1], 0)], ERRORS[1], False)
    check('repeated-short-does-not-loop', ['ipc', *short_args],
          [(short_args, SHORT, 0), (short_args + [''], SHORT, 0)], SHORT, False)
    for name, command, params in (
        ('fire', ['fire', 'event-name'], ['event', 'fire', 'event-name']),
        ('custom', ['custom', 'widget', 'method'], ['custom', 'widget', 'method']),
        ('plugin', ['plugin', 'widget', 'method'], ['plugin', 'widget', 'method']),
    ):
        check(f'{name}-padding', command, [(params, SHORT, 0), (params + [''], 'ok\n', 0)], 'ok\n')
        check(f'{name}-failure', command, [(params, ERRORS[2], 0)], ERRORS[2], False)
    print(f'{count - len(failures)}/{count} passed; {len(failures)} failed')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
