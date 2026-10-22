#!/usr/bin/env python3
"""Actual native-heap and consumer-pattern regression for OwnedProcess (VM)."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote

from filechooser_isolation import ROOT, enter, profile_env
from filechooser_leaks import build_probe, native_query


def main():
    enter(runtime_seconds=600)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    runtime, output = ROOT / 'runtime' / args.label, ROOT / 'evidence' / args.label
    runtime.mkdir(); output.mkdir()
    cases, samples = [], []
    complete, failure = False, ''

    def check(name, condition, detail=None):
        cases.append({'case': name, 'pass': bool(condition), 'detail': detail})
        print(name, 'PASS' if condition else 'FAIL', flush=True)
        assert condition, name

    shell = runtime / 'shell'
    shutil.copytree(source, shell, symlinks=True)
    probe = shell / 'owned-process-test.qml'
    template = (source / 'Scripts/dev/fixtures/OwnedProcessRegression.qml').read_text()
    probe.write_text(template.replace('../../../Helpers/OwnedProcess.js', 'Helpers/OwnedProcess.js'))
    shutil.copy2(probe, output / probe.name)
    shutil.copy2(shell / 'Helpers/OwnedProcess.js', output / 'OwnedProcess.js')
    library = build_probe(source, runtime, output)
    address = Path(os.environ['FILECHOOSER_ISOLATION']) / 'run/native-heap.sock'
    env = dict(profile_env(runtime / 'profile'), MALLOC_CONF='dirty_decay_ms:0,muzzy_decay_ms:0', OWNED_TEST_INHERITED='inherited-value')
    (runtime / 'profile/config/settings.json').write_text((source / 'Configs/defaults.json').read_text())

    def ipc(member, *values, check=True):
        result = subprocess.run(['timeout', '10', 'qs', '-p', str(probe), 'ipc', 'call', 'ownedProcessTest', member, *map(str, values)],
                                env=env, capture_output=True, text=True, timeout=15, check=check)
        if member != 'state':
            (output / ('ipc-' + member + '.json')).write_text(json.dumps({'member': member, 'arguments': list(values),
                'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}, indent=2))
            assert not result.stdout.strip(), result.stdout
        return result.stdout.strip()

    def encoded(value):
        # qs's typed IPC argument reader reparses quotes inside JSON even when
        # argv is passed without a shell; keep one opaque whitespace-free token.
        return quote(json.dumps(value, ensure_ascii=True), safe='')

    def state():
        value = json.loads(ipc('state'))
        (output / 'last-state.json').write_text(json.dumps(value, indent=2))
        return value

    def wait(fn, seconds=15):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            value = fn()
            if value:
                return value
            time.sleep(.03)
        raise AssertionError('consumer did not observe completion')

    def result(name):
        return wait(lambda: state()['results'].get(name))

    def run(name, argv, data=None):
        ipc('start', encoded({'name': name, 'argv': argv, 'input': data}))
        row = result(name)
        check(name + '-settles-once', row['calls'] == 1, row)
        return row['result']

    with (output / 'subject.log').open('w') as log:
        app = subprocess.Popen(['timeout', '520', sys.executable, '-B', str(source / 'Scripts/dev/filechooser-no-thp.py'),
                                'env', 'LD_PRELOAD=' + str(library), 'FILECHOOSER_NATIVE_SOCKET=' + str(address),
                                'qs', '-p', str(probe)], cwd=shell, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            end = time.monotonic() + 30
            while True:
                value = ipc('state', check=False)
                if address.exists() and value.startswith('{'):
                    break
                assert app.poll() is None and time.monotonic() < end, 'cold start'
                time.sleep(.1)
            pid = state()['pid']
            check('native-observer-is-actual-subject', native_query(address)['pid'] == pid)
            check('subject-thp-off', 'THP_enabled:\t0' in Path(f'/proc/{pid}/status').read_text())
            # Inventory is deliberately checked against production importers,
            # not a hand-maintained claim that only the chooser uses the helper.
            consumers = sorted(str(p.relative_to(source)) for p in source.rglob('*.qml')
                               if 'OwnedProcess.js' in p.read_text() and not p.is_relative_to(source / 'Scripts'))
            expected = sorted(['Commons/Settings.qml', 'Services/Keyboard/BindingsService.qml', 'Services/Keyboard/InputMethodBinds.qml',
                               'Services/Keyboard/KeydService.qml', 'Services/Compositor/NiriSessionInit.qml',
                               'Services/Files/FilePreview.qml', 'Services/Files/FileThumbnails.qml'])
            check('all-production-consumers-covered', consumers == expected, consumers)
            payload = json.dumps({'value': 'résumé 日本語 #?%', 'items': list(range(2000))}, ensure_ascii=False)
            script = 'import json,sys; data=json.load(sys.stdin); print(json.dumps({"ok":True,"state":data},ensure_ascii=False)); print("diagnostic",file=sys.stderr)'
            for name in ('Settings', 'NiriSessionInit'):
                row = run(name, ['python3', '-c', script], payload)
                check(name + '-json-stdin-eof-output', row['success'] and row['exitCode'] == row['exitStatus'] == 0
                      and json.loads(row['stdout']) == {'ok': True, 'state': json.loads(payload)} and row['stderr'] == 'diagnostic\n')
            for name in ('KeydService', 'InputMethodBinds', 'FilePreview'):
                row = run(name, ['python3', '-c', 'import json,sys; print(json.dumps({"ok":True,"argument":sys.argv[1]},ensure_ascii=False))', 'spaces 日本語 #?%'])
                check(name + '-argv-json-readback', row['success'] and json.loads(row['stdout']) == {'ok': True, 'argument': 'spaces 日本語 #?%'})
            row = run('BindingsService', ['env', 'OWNED_OVERRIDE=override', 'python3', '-c',
                                        'import json,os; print(json.dumps([os.environ["OWNED_TEST_INHERITED"],os.environ["OWNED_OVERRIDE"],os.getcwd()]))'])
            check('BindingsService-env-and-working-directory', row['success'] and json.loads(row['stdout']) == ['inherited-value', 'override', str(shell)])
            folder = runtime / 'directory with spaces'; folder.mkdir()
            row = run('working-directory', ['sh', '-c', 'cd "$1" && pwd', 'sh', str(folder)])
            check('explicit-child-working-directory', row['success'] and row['stdout'].strip() == str(folder))
            ipc('chain', encoded(['sh', '-c', 'printf stage']))
            check('sequential-reentrant-completion', result('chain-first')['calls'] == result('chain-second')['calls'] == 1)
            row = run('nonzero', ['sh', '-c', 'printf output; printf error >&2; exit 7'])
            check('stdout-stderr-exit-status', not row['success'] and row['stdout'] == 'output' and row['stderr'] == 'error'
                  and row['exitCode'] == 7 and row['exitStatus'] == 0)
            row = run('empty-command', [])
            check('empty-command-failure', not row['success'] and row['exitCode'] is None and row['error'] == 'Empty child command')
            row = run('missing-command', ['/nonexistent/owned-process-regression'])
            check('failed-start-settles', not row['success'] and row['error'])
            row = run('timeout', ['timeout', '.2', 'sleep', '10'])
            check('caller-timeout-exit-code', not row['success'] and row['exitCode'] == 124 and row['exitStatus'] == 0)
            stream = 'import sys\nfor line in sys.stdin:\n print("reply:"+line.strip(),flush=True)\nprint("EOF",file=sys.stderr)'
            ipc('streaming', encoded(['python3', '-u', '-c', stream]))
            wait(lambda: state()['childPid'])
            ipc('write', encoded('first\n'))
            wait(lambda: 'reply:first' in state()['streamText'])
            ipc('write', encoded('second\n'))
            wait(lambda: 'reply:second' in state()['streamText'])
            check('FileThumbnails-stream-visible-before-exit', state()['streamed'] >= 2 and 'stream' not in state()['results'])
            ipc('closeInput')
            row = result('stream')
            check('FileThumbnails-EOF-and-final-collectors', row['calls'] == 1 and row['result']['success']
                  and row['result']['stdout'] == 'reply:first\nreply:second\n' and row['result']['stderr'] == 'EOF\n')
            for name, action in (('cancel', 'stop'), ('kill', 'kill')):
                ipc('start', encoded({'name': name, 'argv': ['sleep', '30'], 'input': None}))
                child = wait(lambda: state()['childPid'])
                ipc(action)
                row = result(name)
                check(name + '-native-process-control', row['calls'] == 1 and not row['result']['success'])
                wait(lambda: not Path(f'/proc/{child}').exists())
            ipc('owned', encoded(['sleep', '30']))
            child = wait(lambda: state()['childPid'])
            ipc('destroyOwner')
            wait(lambda: not Path(f'/proc/{child}').exists())
            check('owner-teardown-reaps-child-without-completion', 'owner' not in state()['results'])
            # Warm200, then measure1000 fresh real children after explicit GC.
            # Old inline compilation retained ~7KiB/child in the causal probe;
            # the1MiB bound admits startup/cache jitter, not that linear growth.
            def batch(count):
                before = state()['completed']
                ipc('batch', count)
                wait(lambda: state()['completed'] == before + count and state()['pending'] == 0, 45)
                assert state()['failures'] == 0
                time.sleep(.3)
                ipc('collect')
                stats = native_query(address)
                assert stats['pid'] == pid
                samples.append({'children': before + count, 'native': stats})
                (output / 'native-samples.json').write_text(json.dumps(samples, indent=2))
            batch(200)
            for _ in range(5):
                batch(200)
            growth = samples[-1]['native']['allocated_bytes'] - samples[0]['native']['allocated_bytes']
            check('1000-children-native-retention-bounded', growth < 1024 * 1024,
                  {'measured_children': 1000, 'warmup_children': 200, 'growth_bytes': growth, 'limit_bytes': 1024 * 1024})
            ipc('quit'); app.wait(timeout=15)
            check('cold-subject-exit', app.returncode == 0)
            complete = True
        except Exception as error:
            failure = repr(error)
            (output / 'failure-state.json').write_text(json.dumps(state(), indent=2))
            raise
        finally:
            if app.poll() is None:
                ipc('quit'); app.wait(timeout=15)
            (output / 'result.json').write_text(json.dumps({'passed': complete and all(c['pass'] for c in cases),
                'complete': complete, 'failure': failure, 'cases': cases, 'native_samples': samples}, indent=2))


if __name__ == '__main__':
    main()
