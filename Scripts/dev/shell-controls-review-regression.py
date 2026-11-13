#!/usr/bin/env python3
"""Guest-only release-review regressions for installed CLI and shell handoff."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', required=True, type=Path)
    args = ap.parse_args()
    assert Path('/sys/class/dmi/id/sys_vendor').read_text().strip() == 'QEMU', 'VM only'
    args.work.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parents[2]
    prefix = args.work.resolve() / 'package'
    scripts = prefix / 'share/atmosphera/Scripts/bash'
    shutil.copytree(source / 'Scripts/bash', scripts)
    (prefix / 'bin').mkdir()
    shutil.copy2(scripts / 'atmosphera', prefix / 'bin/atmosphera')
    stub = args.work.resolve() / 'stub'
    stub.mkdir()
    (stub / 'busctl').write_text('''#!/bin/bash
if [ "$REVIEW_MODE" = absent ]; then exit 1; fi
if [[ "$*" == *GetNameOwner* ]]; then
  if [ -f "$REVIEW_WORK/stopped" ]; then
    if [ "$REVIEW_MODE" = successor ]; then echo 's ":1.99"'; else exit 1; fi
  else echo 's ":1.42"'; fi
elif [[ "$*" == *GetConnectionUnixProcessID* ]]; then
  if [ -f "$REVIEW_WORK/stopped" ]; then echo "u $REVIEW_SUCCESSOR"; else echo "u $REVIEW_PID"; fi
else echo 'b true'; fi
''')
    (stub / 'qs').write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$REVIEW_WORK/calls"
if [ "$1" = kill ]; then touch "$REVIEW_WORK/stopped"; exit 0; fi
if [ "$1" = -n ]; then echo started; exit 0; fi
if [[ "$*" == *'dialog cancel'* ]]; then exit 0; fi
case "$REVIEW_MODE" in
  delivery-failure) exit 42 ;;
  no-reply) exit 0 ;;
esac
method=$6
if [ "$method" = survey ]; then fifo=$9; else fifo=$8; fi
case "$method" in
  alert) reply=ok ;; confirm) reply=true ;; prompt) reply=typed ;; survey) reply='["typed"]' ;;
esac
printf '%s' "$reply" > "$fifo"
''')
    for path in stub.iterdir():
        path.chmod(0o755)
    impossible = int(Path('/proc/sys/kernel/pid_max').read_text()) + 1
    env = dict(os.environ, PATH=f'{stub}:{os.environ["PATH"]}',
               REVIEW_WORK=str(args.work.resolve()), REVIEW_PID=str(impossible),
               REVIEW_SUCCESSOR=str(impossible + 1), REVIEW_MODE='absent',
               XDG_RUNTIME_DIR=str(args.work.resolve()), ATMOSPHERA_DIALOG_TIMEOUT='1')
    results = []

    def check(name, cli, command, predicate, seconds=4):
        start = time.monotonic()
        p = subprocess.Popen(['bash', str(cli), *command], env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, start_new_session=True)
        try:
            stdout, stderr = p.communicate(timeout=seconds)
            reply = subprocess.CompletedProcess(p.args, p.returncode, stdout, stderr)
            passed = predicate(reply)
            detail = dict(rc=p.returncode, stdout=stdout, stderr=stderr)
        except subprocess.TimeoutExpired:
            passed, detail = False, {'timeout': seconds}
            os.killpg(p.pid, signal.SIGTERM)
            try:
                p.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                p.communicate(timeout=3)
        clean = not list(args.work.glob('atmosphera-dialog-*'))
        passed = passed and clean
        results.append(dict(case=name, passed=passed, elapsed=time.monotonic() - start,
                            cleanup_complete=clean, **detail))
        print(name, 'PASS' if passed else 'FAIL', detail if not passed else '', flush=True)

    installed = prefix / 'bin/atmosphera'
    check('nix-installed-help', installed, ['help'], lambda p: p.returncode == 0 and 'Subcommands:' in p.stdout)
    check('nix-installed-run', installed, ['run'], lambda p: p.returncode == 0 and p.stdout == 'started\n')
    check('nix-installed-handler', installed, ['session', 'list'], lambda p: p.returncode == 0 and 'Available shells:' in p.stdout)
    cli = scripts / 'atmosphera'
    env['REVIEW_MODE'] = 'successor'
    target = args.work.resolve() / 'target'
    target.mkdir()
    (target / 'shell.qml').write_text('//@ pragma ShellId app.atmosphera.Shell\n')
    (args.work / 'calls').unlink(missing_ok=True)
    check('successor-prevents-false-handoff', cli, ['session', 'launch', str(target)],
          lambda p: p.returncode != 0 and 'another shell' in p.stderr
          and '-n -p' not in (args.work / 'calls').read_text())
    (args.work / 'stopped').unlink(missing_ok=True)
    commands = [('alert', ['message'], ''), ('confirm', ['question'], ''),
                ('prompt', ['question', 'default'], 'typed\n'),
                ('survey', ['Field', 'default'], '["typed"]\n')]
    for mode in ('reply', 'delivery-failure', 'no-reply'):
        env['REVIEW_MODE'] = mode
        for name, params, output in commands:
            if mode == 'reply':
                predicate = lambda p, output=output: p.returncode == 0 and p.stdout == output
            elif mode == 'delivery-failure':
                predicate = lambda p: p.returncode != 0
            else:
                predicate = lambda p: p.returncode in (0, 1)
            check(name + '-' + mode, cli, [name, *params], predicate)
    (args.work / 'result.json').write_text(json.dumps(results, indent=2))
    failures = sum(not r['passed'] for r in results)
    print(f'{len(results)-failures}/{len(results)} passed; {failures} failed')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
