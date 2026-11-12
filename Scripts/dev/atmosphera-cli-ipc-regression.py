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
BUS_STUB = '''#!/usr/bin/env python3
import os, pathlib, sys
if os.environ.get('S10_OWNER_MODE') == 'absent':
    sys.exit(1)
log = pathlib.Path(os.environ['S10_STUB']) / 'calls.jsonl'
if log.exists() and '["kill", "--pid", "4242"]' in log.read_text():
    sys.exit(1)
if 'GetNameOwner' in sys.argv:
    print('s ":1.42"')
elif 'GetConnectionUnixProcessID' in sys.argv:
    print('u 4242')
elif 'get-property' in sys.argv:
    print('b false' if os.environ.get('S10_OWNER_MODE') == 'waiting' else 'b true')
else:
    sys.exit(98)
'''
PREFIX = ['ipc', '--pid', '4242', 'call']
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
    bus_stub = args.work / 'busctl'
    bus_stub.write_text(BUS_STUB)
    bus_stub.chmod(0o755)
    env = dict(os.environ, PATH=f'{args.work.resolve()}:{os.environ["PATH"]}', S10_STUB=str(args.work.resolve()))
    failures = []
    count = 0

    def check(name, command, calls, output, success=True, prefix=PREFIX):
        nonlocal count
        count += 1
        spec = [{'args': prefix + params, 'output': text, 'rc': rc} for params, text, rc in calls]
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
    for mode in ('absent', 'waiting'):
        env['S10_OWNER_MODE'] = mode
        p = subprocess.run(['bash', str(args.cli), 'ipc', 'launcher', 'toggle'], capture_output=True, text=True, env=env, timeout=10)
        count += 1
        passed = p.returncode == 1 and 'no ready registered shell' in p.stderr
        print(f'owner-{mode}: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            failures.append('owner-' + mode)
    env.pop('S10_OWNER_MODE')
    for name, command, target in (
        ('settings', ['settings', 'open'], ['settings', 'open']),
        ('lock', ['lock', 'lock'], ['lockScreen', 'lock']),
        ('lock-preview', ['lock', 'preview'], ['lockScreen', 'preview']),
    ):
        check(name + '-registered-owner', command, [(target, 'ok\n', 0)], 'ok\n')
    check('run-reuses-owner', ['run'], [], 'Atmosphera is already running (PID 4242).\n')
    target = args.work.resolve() / 'development-tree'
    target.mkdir()
    (target / 'shell.qml').write_text('//@ pragma ShellId app.atmosphera.Shell\n')
    config = args.work.resolve() / 'config/niri'
    config.mkdir(parents=True)
    base = config / 'config.kdl'
    base.write_text('// fixture base\n')
    (config / 'atmosphera-session.kdl').write_text('// Base config detected at niri boot: ' + str(base) + '\n')
    niri = args.work / 'niri'
    niri.write_text('#!/bin/sh\ntouch "$S10_STUB/niri-reset"\nexit 99\n')
    niri.chmod(0o755)
    env.update(NIRI_SOCKET='/fixture/niri', XDG_CONFIG_HOME=str(config.parent))
    check('switch-dev-tree-uses-owner', ['session', 'launch', str(target)],
          [(['kill', '--pid', '4242'], '', 0), (['-n', '-p', str(target), '-d'], 'started\n', 0)],
          f'Launching: {target}\nstarted\n', prefix=[])
    count += 1
    reset = (args.work / 'niri-reset').exists()
    print(f'dev-switch-keeps-niri-session: {"FAIL" if reset else "PASS"}', flush=True)
    if reset:
        failures.append('dev-switch-keeps-niri-session')
    env['S10_OWNER_MODE'] = 'absent'
    check('run-starts-when-unregistered', ['run'], [(['-n', '-c', 'atmosphera'], 'started\n', 0)], 'started\n', prefix=[])
    env.pop('S10_OWNER_MODE')
    stub.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
assert args[:5] == ['ipc', '--pid', '4242', 'call', 'dialog'], args
with (pathlib.Path(os.environ['S10_STUB']) / 'dialogs.jsonl').open('a') as f:
    f.write(json.dumps(args) + '\\n')
method = args[5]
if method != 'cancel':
    fifo = args[8] if method == 'survey' else args[7]
    reply = {'alert': 'ok', 'confirm': 'true', 'prompt': 'typed', 'survey': '["typed"]'}[method]
    with open(fifo, 'w') as f:
        f.write(reply + '\\n')
''')
    env['XDG_RUNTIME_DIR'] = str(args.work.resolve())
    for name, command, output in (
        ('alert', ['alert', 'message'], ''),
        ('confirm', ['confirm', 'question'], ''),
        ('prompt', ['prompt', 'question', 'default'], 'typed\n'),
        ('survey', ['survey', 'Field', 'default'], '["typed"]\n'),
    ):
        p = subprocess.run(['bash', str(args.cli), *command], capture_output=True, text=True, env=env, timeout=12)
        count += 1
        passed = p.returncode == 0 and p.stdout == output and not p.stderr
        print(f'{name}-registered-owner: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            failures.append(name)
            print(repr((p.returncode, p.stdout, p.stderr)))
    print(f'{count - len(failures)}/{count} passed; {len(failures)} failed')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
