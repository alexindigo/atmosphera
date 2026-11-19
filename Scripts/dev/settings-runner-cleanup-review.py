#!/usr/bin/env python3
"""Fault the real runner cleanup paths without leaving the rejecting children."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from unittest.mock import patch

from guest_profile import activate_profile, profile_argument, ProcessIdentity
from native_settings_controls import prepare
from presentation_harness import run_harness


STALL = '''import json,os,signal,subprocess,sys,time
signal.signal(signal.SIGTERM,signal.SIG_IGN)
schedule=os.environ.get('ATCQ_NATIVE_SCHEDULE')
if schedule:
 rule=json.load(open(schedule))['rules'][0]
 fd=os.open(rule['gate'],os.O_RDONLY|os.O_NONBLOCK)
 open(rule['marker'],'w').write('{}')
 print('PLUGIN_UNLOAD: HELD_PASS',flush=True)
child=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)'],start_new_session=True)
open(os.environ['CLEANUP_DESCENDANT'],'w').write(str(child.pid))
print('CLEANUP_STALL_READY',flush=True)
time.sleep(60)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'output'):
        parser.add_argument('--'+name, required=True, type=Path)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    source, plugins, output = (p.resolve() for p in (args.source, args.plugins, args.output))
    if not output.is_relative_to(profile.workspace) or output == profile.workspace:
        raise SystemExit('output must stay in the assigned workspace')
    output.mkdir(parents=True, exist_ok=False)
    native = prepare(source)
    popen, open_fd = subprocess.Popen, os.open
    rows = []
    for case in ('unload-termination', 'unload-release', 'scoped-timeout', 'scoped-guard'):
        root = output/case
        root.mkdir()
        descendant = root/'descendant'
        kind = 'unload' if case.startswith('unload') else 'scoped'
        filename = 'settings-plugin-unload-review.py' if kind == 'unload' else 'settings-scoped-receipts.py'
        spec = importlib.util.spec_from_file_location('cleanup_'+case.replace('-', '_'), source/'Scripts/dev'/filename)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        children = []

        def launch(command, **kwargs):
            if command[0] == 'dbus-run-session':
                kwargs['env'] = dict(kwargs['env'], CLEANUP_DESCENDANT=str(descendant))
                child = popen([sys.executable, '-B', '-c', STALL], **kwargs)
                children.append(child)
                wait, communicate = child.wait, child.communicate
                child.wait = lambda timeout=None: wait(timeout=min(timeout or .2, .2))

                def bounded_communicate(*values, **keywords):
                    if keywords.get('timeout') is None:
                        raise AssertionError('unbounded cleanup communicate')
                    keywords['timeout'] = .2
                    return communicate(*values, **keywords)

                child.communicate = bounded_communicate
                return child
            return popen(command, **kwargs)

        def supervised(command, work, env, budget):
            return run_harness([sys.executable, '-B', '-c', STALL], work,
                               dict(env, CLEANUP_DESCENDANT=str(descendant)), .4)

        def refuse_release(path, flags, *values, **keywords):
            if case == 'unload-release' and Path(path).name == 'release' and flags & os.O_WRONLY:
                raise OSError('injected FIFO release refusal')
            return open_fd(path, flags, *values, **keywords)

        def refused_guard(*unused):
            raise RuntimeError('injected guard acquisition refusal')

        command = ['cleanup-review', '--source', str(source), '--plugins', str(plugins), '--output', str(root/'run')]
        command += ['--case', 'reload-held' if case == 'unload-release' else 'closed-api'] if kind == 'unload' else [
            '--guest-profile', str(args.guest_profile), '--modes', 'ordinary']
        failure = None
        started = time.monotonic()
        try:
            with patch.object(sys, 'argv', command), patch.object(subprocess, 'Popen', launch), \
                 patch.object(module, 'run_harness', supervised, create=True), \
                 patch.object(module, 'prepare', return_value=native, create=True), \
                 patch.object(module.os, 'open', refuse_release), \
                 patch.object(module, 'protect_owned_process', refused_guard, create=True) if case == 'scoped-guard' else \
                 patch.object(module, '_cleanup_review_unused', None, create=True):
                code = module.main()
            result = json.loads((root/'run/result.json').read_text())
            entries = result['cases'] if isinstance(result, dict) else result
            if code == 0 or not entries or any(row['status'] != 'FAIL' for row in entries):
                raise AssertionError('fault must produce a durable failed receipt')
            if any(child.poll() is None for child in children):
                raise AssertionError('runner left a live child')
            executions = [json.loads(path.read_text()) for path in (root/'run').rglob('execution.json')]
            if not executions or any(not item['cleanup_complete'] or item['remaining_pids'] or
                                     item['namespace'] == item['parent_namespace'] for item in executions):
                raise AssertionError('bounded descendant cleanup not independently recorded')
        except Exception as error:
            failure = repr(error)
        finally:
            # Only the OLD rejecting runner launches outside the existing
            # namespace supervisor. Retire its exact synthetic children here.
            if children:
                if descendant.exists():
                    pid = int(descendant.read_text())
                    try:
                        identity = ProcessIdentity.read(pid)
                        if identity.uid == os.getuid() and identity.argv and 'signal.SIG_IGN' in ' '.join(identity.argv):
                            os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                for child in children:
                    if child.poll() is None:
                        os.killpg(child.pid, signal.SIGKILL)
                    popen.wait(child, timeout=5)
        row = dict(case=case, status='FAIL' if failure else 'PASS', error=failure,
                   elapsed=time.monotonic()-started)
        rows.append(row)
        print(json.dumps(row), flush=True)
    (output/'result.json').write_text(json.dumps(dict(cases=rows), indent=2)+'\n')
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
