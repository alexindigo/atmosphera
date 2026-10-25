#!/usr/bin/env python3
"""Prove timeout artifacts and detached-descendant cleanup in the assigned VM."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from presentation_harness import run_harness

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--workspace', type=Path, required=True)
args = parser.parse_args()
work = args.workspace.resolve()
assert not str(work).startswith('/tmp/')
work.mkdir()


def console_qs():
    # ps exits 1 when no qs runs; an empty listing is a valid observation.
    return subprocess.run(['ps', '-C', 'qs', '-o', 'pid=,args='], capture_output=True, text=True, timeout=10).stdout


console_before = console_qs()
body = '''import os,signal,subprocess,sys,time
child = subprocess.Popen([sys.executable, '-u', '-c', 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("DETACHED_READY",flush=True); time.sleep(3600)'], start_new_session=True)
print('STALL_READY', child.pid, os.readlink('/proc/self/ns/pid'), flush=True)
time.sleep(3600)
'''
result = []
failures = []

def execute():
    try:
        result.append(run_harness([sys.executable, '-u', '-c', body], work, dict(os.environ), 2.0))
    except BaseException as error:
        failures.append(repr(error))

thread = threading.Thread(target=execute)
thread.start()
deadline = time.monotonic() + 2
incremental = False
while thread.is_alive() and time.monotonic() < deadline:
    path = work / 'shell.log'
    if path.exists() and 'DETACHED_READY' in path.read_text(errors='replace'):
        incremental = not (work / 'execution.json').exists()
        break
    time.sleep(0.02)
thread.join(timeout=12)
assert not thread.is_alive() and not failures, failures
execution = result[0]
receipt = json.loads((work / 'result.json').read_text())
log = (work / 'shell.log').read_text()
console_after = console_qs()
assert incremental and 'STALL_READY' in log and 'HARNESS_TIMEOUT' in log
assert receipt['passed'] is False and execution['timed_out'] and execution['exit_code'] != 0
assert execution['cleanup_complete'] and execution['remaining_pids'] == []
assert execution['elapsed_seconds'] < 10 and console_before == console_after
proof = dict(passed=True, incremental_log_observed=incremental, stalled_execution=execution,
             console_before=console_before, console_after=console_after)
(work / 'selftest.json').write_text(json.dumps(proof, indent=2) + '\n')
print(json.dumps(proof, indent=2))
