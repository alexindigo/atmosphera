#!/usr/bin/env python3
"""Serial/parallel equivalence, ordered diagnostics and pool lifetime controls."""
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT/'Scripts/dev/check-settings-writes.py'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(root, report, extra=(), cpu_count=None):
    argv = [str(SCRIPT), '--root', str(root), '--report', str(report), '--check', *extra]
    if cpu_count is None:
        command = [sys.executable, '-B', *argv]
    else:
        code = ('import os,runpy,sys; os.cpu_count=lambda: ' + cpu_count
                + '; sys.argv=' + repr(argv) + '; runpy.run_path(sys.argv[0],run_name="__main__")')
        command = [sys.executable, '-B', '-c', code]
    return subprocess.run(command, capture_output=True, timeout=60)


def main():
    with tempfile.TemporaryDirectory(prefix='settings-parallel-') as temporary:
        root = Path(temporary)
        (root/'Configs').mkdir()
        (root/'Configs/settings-schema.json').write_bytes((ROOT/'Configs/settings-schema.json').read_bytes())
        cases = json.loads((ROOT/'Scripts/dev/fixtures/settings-writes/cases.json').read_text())
        for index, case in enumerate(cases):
            suffix = '.js' if 'js' in case else '.qml'
            (root/(f'{index:03d}-case'+suffix)).write_text(case.get('qml', case.get('js')))
        for directory in ('.git', 'node_modules', 'Scripts/dev/fixtures/settings-writes'):
            hidden = root/directory/'excluded.qml'
            hidden.parent.mkdir(parents=True)
            hidden.write_text('not valid QML')
        serial_report = root/'serial.json'
        serial = run(root, serial_report, ['--workers', '1'])
        require(serial.returncode == 1 and b'SETTINGS_WRITES: FAIL' in serial.stdout,
                'fixture errors must remain rejected in serial mode')
        expected = serial_report.read_bytes()
        require(json.loads(expected)['files'] == len(cases), 'input exclusions or file count changed')
        for label, workers, cpu in (('two', ['--workers', '2'], None),
                                    ('four', ['--workers', '4'], None),
                                    ('automatic', [], '2'), ('unknown-cpus', [], 'None')):
            report = root/(label+'.json')
            result = run(root, report, workers, cpu)
            require((result.returncode, result.stdout, result.stderr)
                    == (serial.returncode, serial.stdout, serial.stderr), label+' CLI bytes/status differ')
            require(report.read_bytes() == expected, label+' report bytes differ')
        timed_report = root/'timed.json'
        timed = run(root, timed_report, ['--workers', '2', '--timings'])
        require(timed.returncode == serial.returncode and timed.stdout == serial.stdout
                and timed_report.read_bytes() == expected, 'timing mode changes analysis')
        records = [json.loads(line.removeprefix('SETTINGS_WRITES_TIME: '))
                   for line in timed.stderr.decode().splitlines()]
        paths = sorted(p.name for p in root.iterdir() if p.suffix in ('.qml', '.js'))
        require(len(records) == 2*len(paths), 'timing records lost a file')
        for index, path in enumerate(paths):
            start, end = records[index*2:index*2+2]
            require((start['file'], end['file'], start['status'], end['status'])
                    == (path, path, 'started', 'finished'), 'diagnostics not in deterministic input order')
            require(start['filesCompleted'] == index and end['filesCompleted'] == index+1
                    and start['filesTotal'] == len(paths) and end['filesTotal'] == len(paths)
                    and end['seconds'] >= 0 and end['totalSeconds'] >= start['totalSeconds'],
                    'invalid worker timing/progress')
        for workers in ('0', '-1', 'invalid'):
            result = run(root, root/'invalid.json', ['--workers', workers])
            require(result.returncode == 2 and b'--workers' in result.stderr, 'invalid override accepted')
        # One-file and empty roots bypass the pool without changing the report.
        for label, paths in (('one', ['000-case.qml']), ('empty', ['Configs'])):
            a = root/(label+'-serial.json'); b = root/(label+'-parallel.json')
            first = run(root, a, ['--workers', '1', *paths])
            second = run(root, b, ['--workers', '2', *paths])
            require((first.returncode, first.stdout, first.stderr, a.read_bytes())
                    == (second.returncode, second.stdout, second.stderr, b.read_bytes()), label+' differs')
        broken = root/'unreadable.qml'
        broken.write_bytes(b'\xff')
        failure_report = root/'failed.json'
        failed = run(root, failure_report, ['--workers', '2'])
        require(failed.returncode != 0 and b'UnicodeDecodeError' in failed.stderr
                and b'SETTINGS_WRITES: PASS' not in failed.stdout and not failure_report.exists(),
                'worker failure was hidden or published a successful report')

        spec = importlib.util.spec_from_file_location('settings_contract_runner', ROOT/'Scripts/dev/settings-contract-check.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        sleeper = root/'pool-lifetime.py'
        receipt = root/'pool-pids.json'
        sleeper.write_text('import json,os,signal,sys\nfrom pathlib import Path\n'
                           'child=os.fork()\n'
                           'if child: Path(sys.argv[1]).write_text(json.dumps([os.getpid(),child,os.getpgrp()]))\n'
                           'while True: signal.pause()\n')
        try:
            runner.run_command([sys.executable, '-B', str(sleeper), str(receipt)], root, 1)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise RuntimeError('whole-command deadline was not enforced')
        parent, child, group = json.loads(receipt.read_text())
        require(group == parent and group != os.getpgrp(), 'command did not own a private process group')
        for pid in (parent, child):
            # SIGKILL is asynchronous for the grandchild. Wait for its actual
            # exit notification, not a racy /proc sample immediately after wait.
            try:
                descriptor = os.pidfd_open(pid)
            except ProcessLookupError:
                continue
            try:
                require(bool(select.select([descriptor], [], [], 1)[0]),
                        'timeout left a parent or worker running')
            finally:
                os.close(descriptor)
    print(f'SETTINGS_WRITES_PARALLEL_SELFTEST: PASS ({len(cases)} cases, workers 1/2/4/auto, ordered bytes, failures, group timeout)')


if __name__ == '__main__':
    main()
