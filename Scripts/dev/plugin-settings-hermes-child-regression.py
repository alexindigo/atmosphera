#!/usr/bin/env python3
"""VM-only finite Hermes CLI lifetime proof using the actual HTTP dispatcher."""
from __future__ import annotations

from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

from fixture_resources import FixtureResources
from fixtures.fixture_paths import require_owned_path
from guest_profile import activate_profile


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def identity(pid):
    try:
        fields = (Path('/proc') / str(pid) / 'stat').read_text().split(') ', 1)[1].split()
        return {'pid': pid, 'start': fields[19], 'state': fields[0]}
    except FileNotFoundError:
        return None


def alive(record):
    current = identity(record['pid'])
    return current and current['start'] == record['start'] and current['state'] != 'Z'


def wait_for(check, message, timeout=10):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        value = check()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError(message)


def load_record(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def stop_exact_child(child, cli):
    if child and alive(child):
        try:
            command = (Path('/proc') / str(child['pid']) / 'cmdline').read_bytes().split(b'\0')
        except FileNotFoundError:
            return
        if not alive(child):
            return
        if os.fsencode(str(cli)) not in command:
            raise AssertionError('refusing to stop a process other than the exact synthetic CLI')
        try:
            os.kill(child['pid'], signal.SIGTERM)
        except ProcessLookupError:
            return
        wait_for(lambda: not alive(child), 'exact synthetic cleanup')


def run_main_witness(launch, case, cli, records):
    child = None

    def discover():
        nonlocal child
        if child is None:
            child = load_record(case / 'child.json')
            if child is not None:
                records.extend([child, child['parent']])
        return child

    def cleanup():
        stop_exact_child(discover(), cli)

    with FixtureResources() as resources:
        resources.defer(cleanup)
        text = launch()
        assert 'HERMES_MAIN_DESTROYED: PASS' in text
        child = discover()
        assert child and child['argv'] == ['-z', 'inert-held-oneshot']
        wait_for(lambda: not alive(child['parent']), 'actual Main helper quiescence')
        wait_for(lambda: not alive(child), 'actual Main CLI quiescence')
        return text, child


def request(port, token, path):
    body = json.dumps({'text': 'literal prompt ; $(not-a-shell) "quoted"'}).encode()
    req = urllib.request.Request(f'http://127.0.0.1:{port}{path}', body,
                                 {'X-Bridge-Token': token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=12) as reply:
        return json.load(reply)


CLI = '''#!/usr/bin/python3
import json,os,sys,time
from pathlib import Path
root=Path(os.environ['HERMES_CLI_CASE'])
pid=os.getpid();parent=os.getppid()
def identity(value):
    fields=(Path('/proc')/str(value)/'stat').read_text().split(') ',1)[1].split()
    return dict(pid=value,start=fields[19],state=fields[0])
record=identity(pid);record.update(parent=identity(parent),argv=sys.argv[1:])
(root/'child.json').write_text(json.dumps(record))
while not (root/'release').exists():time.sleep(.02)
print('synthetic-answer')
print('synthetic-stderr',file=sys.stderr)
'''


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'guest-profile', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--main-destruction', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    try:
        require_owned_path(args.work_root, profile.work_base, 'Hermes work root')
        require_owned_path(args.output, profile.journal_base, 'Hermes journal root')
    except ValueError as exc:
        parser.error(str(exc))
    args.work_root.mkdir()
    args.output.mkdir()
    helper = args.plugins / 'hermes-agent/scripts/hermes_bridge.py'
    baseline = args.work_root / 'original-hermes-bridge.py'
    # The caller supplies immutable plugin exports; the exact known baseline is
    # reconstructed from the one intended boundary, never canonical mutation.
    source = helper.read_text()
    assert source.count('httpd.command_runner = run_owned_command') == 1
    baseline.write_text(source.replace('httpd.command_runner = run_owned_command',
                                       'httpd.command_runner = subprocess.run'))
    write(args.output / 'inputs.json', {
        'source': str(args.source), 'plugins': str(args.plugins),
        'helperSha256': hashlib.sha256(helper.read_bytes()).hexdigest(),
        'driverSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'allEndpointsSynthetic': True, 'realHermesAccountsUsed': False,
    })
    records, results = [], []

    def endpoint_case(label, script, path, ending, bypass=False):
        case = args.work_root / label
        case.mkdir()
        home = case / 'hermes-home'
        home.mkdir()
        (home / 'config.yaml').write_text('model:\n  default: inert-model\n  provider: inert-provider\n')
        cli = case / 'literal hermes cli'
        cli.write_text(CLI)
        cli.chmod(0o755)
        with socket.socket() as peer:
            peer.bind(('127.0.0.1', 0))
            port = peer.getsockname()[1]
        env = {**os.environ, 'HERMES_CLI_CASE': str(case), 'HOME': str(case)}
        child = None
        replies = []
        failures = []

        with FixtureResources() as resources:
            stdout = resources.open(case / 'server.stdout', 'w')
            stderr = resources.open(case / 'server.stderr', 'w')
            workers = FixtureResources()
            resources.defer(workers.close)
            resources.defer(lambda: stop_exact_child(child or load_record(case / 'child.json'), cli))
            # The failing control must see its unbound descendant survive
            # owner death. Never terminate that descendant before the oracle.
            server = resources.spawn_direct([sys.executable, '-B', str(script), '--port', str(port),
                                      '--state-file', str(case / 'state/state.json'),
                                      '--hermes-home', str(home), '--hermes-command', str(cli)],
                                     env=env, stdout=stdout, stderr=stderr, timeout=10)
            parent = identity(server.pid)
            records.append(parent)
            token = wait_for(lambda: (case / 'state/bridge.token').read_text().strip()
                             if (case / 'state/bridge.token').exists() else '', 'server token')
            def invoke():
                try:
                    replies.append(request(port, token, path))
                except (OSError, urllib.error.URLError) as exc:
                    failures.append(type(exc).__name__)
            worker = workers.thread(invoke, timeout=12)
            child = wait_for(lambda: load_record(case / 'child.json'), 'actual CLI child')
            records.append(child)
            expected = ['-z', 'literal prompt ; $(not-a-shell) "quoted"'] if path == '/oneshot' else ['gateway', path.rsplit('/', 1)[1]]
            assert child['argv'] == expected, child
            assert child['parent']['pid'] == server.pid, child
            assert alive(child) and alive(parent)
            if ending == 'complete':
                (case / 'release').touch()
                worker.join(10)
                assert not worker.is_alive() and not failures and len(replies) == 1
                assert replies[0]['result']['status'] == ('completed' if path == '/oneshot' else 'started' if path.endswith('start') else 'stopped')
                if path == '/oneshot':
                    assert replies[0]['state']['messages'][-1]['text'] == 'synthetic-answer'
                assert alive(parent), 'request completion must not stop server'
                wait_for(lambda: not alive(child), 'normal child quiescence')
            else:
                server.send_signal(signal.SIGTERM if ending == 'term' else signal.SIGKILL)
                server.wait(10)
                wait_for(lambda: not alive(parent), 'server retirement')
                if bypass:
                    # The red proves an unbound CLI really survives owner death.
                    time.sleep(.2)
                    assert alive(child), 'bypass did not reproduce survivor'
                else:
                    wait_for(lambda: not alive(child), 'parent-death CLI quiescence')
            result = dict(case=label, path=path, ending=ending,
                          status='REPRODUCED' if bypass else 'PASS', child=child,
                          parent=parent, reply=replies, requestErrors=failures)
            results.append(result)
            write(args.output / (label + '.json'), result)

    try:
        for path in ('/oneshot', '/gateway/start', '/gateway/stop'):
            name = path.strip('/').replace('/', '-')
            for ending in ('complete', 'term', 'kill'):
                endpoint_case(name + '-' + ending, helper, path, ending)
            endpoint_case(name + '-unbound-kill', baseline, path, 'kill', True)

        # Exercise literal argv/output/timeout and failure at the same runner,
        # outside the HTTP layer whose product timeouts deliberately stay 30/600s.
        case = args.work_root / 'runner-controls'
        case.mkdir()
        cli = case / 'literal hermes cli'
        cli.write_text(CLI)
        cli.chmod(0o755)
        env = {**os.environ, 'HERMES_CLI_CASE': str(case)}
        loader = f'''import importlib.util,subprocess,sys
s=importlib.util.spec_from_file_location('hermes_bridge',{str(helper)!r})
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
'''
        control = case / 'timeout.py'
        control.write_text(loader + f'''
try:m.run_owned_command([{str(cli)!r},'literal arg','; no shell'],capture_output=True,text=True,timeout=.4)
except subprocess.TimeoutExpired:print('EXPECTED_TIMEOUT')
else:raise AssertionError('timeout not enforced')
''')
        reply = subprocess.run([sys.executable, '-B', str(control)], env=env, capture_output=True, text=True, timeout=10)
        assert reply.returncode == 0 and 'EXPECTED_TIMEOUT' in reply.stdout, reply
        child = load_record(case / 'child.json')
        records.append(child)
        wait_for(lambda: not alive(child), 'timeout child quiescence')
        assert child['argv'] == ['literal arg', '; no shell']
        (case / 'child.json').unlink()
        race = subprocess.run([sys.executable, '-B', str(helper), '--owned-cli-child',
                               str(os.getpid() + 10000000), str(cli), 'must-not-run'],
                              env=env, capture_output=True, text=True, timeout=10)
        assert race.returncode != 0 and 'owner already retired' in race.stderr
        assert not (case / 'child.json').exists(), 'retired owner executed CLI'
        control.write_text(loader + '''
class Prctl:
    def __call__(self,*args):return -1
class Libc:prctl=Prctl()
m.ctypes.CDLL=lambda *a,**kw:Libc()
''' + f'm.exec_owned_command({os.getpid()},[{str(cli)!r}])\n')
        binding = subprocess.run([sys.executable, '-B', str(control)], env=env, capture_output=True, text=True, timeout=10)
        assert binding.returncode != 0 and 'cannot bind Hermes CLI lifetime' in binding.stderr
        assert not (case / 'child.json').exists(), 'failed binding executed CLI'
        no_race = case / 'no-parent-check.py'
        assert source.count('if parent_pid <= 1 or os.getppid() != parent_pid:') == 1
        no_race.write_text(source.replace('if parent_pid <= 1 or os.getppid() != parent_pid:', 'if False:'))
        (case / 'release').touch()
        escaped = subprocess.run([sys.executable, '-B', str(no_race), '--owned-cli-child',
                                  str(os.getpid() + 10000000), str(cli), 'must-not-run'],
                                 env=env, capture_output=True, text=True, timeout=10)
        assert escaped.returncode == 0, escaped
        escaped_child = load_record(case / 'child.json')
        assert escaped_child and escaped_child['argv'] == ['must-not-run']
        records.append(escaped_child)
        (case / 'child.json').unlink()
        control.write_text(loader + f'''
r=m.run_owned_command([{str(cli)!r},'literal arg','; no shell'],capture_output=True,text=True,timeout=2)
assert r.returncode==0 and r.stdout=='synthetic-answer\\n' and r.stderr=='synthetic-stderr\\n'
print('EXPECTED_LITERAL_OUTPUT')
''')
        output = subprocess.run([sys.executable, '-B', str(control)], env=env, capture_output=True, text=True, timeout=10)
        assert output.returncode == 0 and 'EXPECTED_LITERAL_OUTPUT' in output.stdout, output
        output_child = load_record(case / 'child.json')
        assert output_child and output_child['argv'] == ['literal arg', '; no shell']
        records.append(output_child)
        control.write_text(loader + f'''
r=m.run_owned_command([{str(case / 'missing-executable')!r}],capture_output=True,text=True,timeout=2)
assert r.returncode!=0 and 'FileNotFoundError' in r.stderr
print('EXPECTED_MISSING_EXECUTABLE')
''')
        missing = subprocess.run([sys.executable, '-B', str(control)], env=env, capture_output=True, text=True, timeout=10)
        assert missing.returncode == 0 and 'EXPECTED_MISSING_EXECUTABLE' in missing.stdout
        write(args.output / 'runner-controls.json', dict(status='PASS',
              timeout=reply.stdout, race=race.stderr, binding=binding.stderr,
              missing=missing.stdout, timeoutChild=child,
              bypassRace=dict(status='REPRODUCED', child=escaped_child),
              literalOutput=output.stdout, literalChild=output_child))
        if args.main_destruction:
            case = args.work_root / 'actual-main'
            out = args.output / 'actual-main'
            case.mkdir()
            out.mkdir()
            for name in ('config/settings', 'cache', 'state', 'hermes-home', 'home'):
                (case / name).mkdir(parents=True, exist_ok=True)
            write(case / 'config/settings.json', dict(settingsVersion=62))
            write(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
            (case / 'hermes-home/config.yaml').write_text('model:\n  default: inert-model\n  provider: inert-provider\n')
            cli = case / 'hermes-cli'
            cli.write_text(CLI)
            cli.chmod(0o755)
            install = case / 'install'
            shutil.copytree(args.source, install, copy_function=link_or_copy,
                            ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
            spec = importlib.util.spec_from_file_location('hermes_fixture_runner', args.source / 'Scripts/dev/plugin-settings-host-assets-regression.py')
            runner = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(runner)
            with socket.socket() as peer:
                peer.bind(('127.0.0.1', 0))
                port = peer.getsockname()[1]
            old_lint_failed = False

            def launch():
                nonlocal old_lint_failed
                try:
                    return runner.run_fixture(profile, install, case, out,
                        args.source / 'Scripts/dev/fixtures/plugin-settings-hermes-child.qml',
                        extra_env=dict(PHA_HERMES_CHILD_CASE=str(case), HERMES_CLI_CASE=str(case),
                                       PHA_HERMES_CHILD_PORT=str(port),
                                       PHA_HERMES_CHILD_PLUGIN=str(helper.parent.parent), HOME=str(case / 'home')),
                        extra_lint=tuple(sorted(helper.parent.parent.rglob('*.qml'))), timeout=60)
                except RuntimeError as error:
                    if str(error) != 'fixture lint failed in the actual qs/native universe; see lint.log':
                        raise
                    assert (out / 'runtime.exit').read_text().strip() == '0'
                    lint = (out / 'lint.log').read_text()
                    assert 'Property "state" already exists in base type "QQuickItem"' in lint
                    assert 'Member "contentHeight" not found' in lint and 'qmllint: FAILED' in lint
                    old_lint_failed = True
                    return (out / 'runtime.log').read_text()

            text, child = run_main_witness(launch, case, cli, records)
            write(out / 'outcome.json', dict(status='PASS', child=child,
                originalQmlLintStillFailed=old_lint_failed,
                originalDiagnostics=[line for line in text.splitlines()
                                     if any(term in line for term in ('TypeError:', 'ReferenceError:', 'SyntaxError:'))],
                fullHermesMemberAccepted=False))
        for record in records:
            assert record and not alive(record), record
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results,
              controls=['timeout', 'retired-owner', 'binding-failure', 'missing-binary',
                        'post-bind-race-bypass', 'literal-output'],
              allIdentitiesQuiescent=records, realAccountsUsed=False))
        print('HERMES_CHILD_LIFETIME: PASS')
    finally:
        # A failing proof must not leak its own exact inert CLI. This cleanup is
        # separate from every product-quiescence assertion above, never success.
        for record in records:
            if record and 'argv' in record and alive(record):
                proc = Path('/proc') / str(record['pid'])
                command = proc.joinpath('cmdline').read_bytes().split(b'\0')
                owned = any(os.fsencode(str(args.work_root)) in entry for entry in command)
                assert owned, command
                os.kill(record['pid'], signal.SIGTERM)
                wait_for(lambda: not alive(record), 'failed-proof inert CLI cleanup')
        write(args.output / 'identities.json', records)


if __name__ == '__main__':
    main()
