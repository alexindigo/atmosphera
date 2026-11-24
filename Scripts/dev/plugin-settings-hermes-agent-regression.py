#!/usr/bin/env python3
"""Actual Hermes connection/session generations against isolated HTTP peers."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy
from fixture_evidence import require
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('hermes_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


class Peer(ThreadingHTTPServer):
    daemon_threads = True


def peer(resources, case, name):
    class Handler(BaseHTTPRequestHandler):
        def call(self):
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
            row = dict(peer=name, method=self.command, path=self.path, body=body, token=self.headers.get('X-Bridge-Token', ''))
            with (case/'requests.jsonl').open('a') as output:
                fcntl.flock(output, fcntl.LOCK_EX); output.write(json.dumps(row)+'\n'); output.flush()
            if self.path == '/sessions' or (self.path == '/session/create' and (case/'hold-create').exists()) or (self.path == '/detect' and (case/'hold-detect').exists()) or (name=='selected' and self.path=='/health' and (case/'hold-health').exists()) or (self.path=='/model' and body.get('model')=='older-model' and (case/'hold-model').exists()):
                while (case/'hold').exists() and not (case/'release').exists() and not done.wait(.02):
                    pass
            model = getattr(self.server, 'model', 'initial-'+name)
            if self.path == '/model':
                model = self.server.model = body['model']
            state = dict(bridge=dict(status='online', error=''), hermes=dict(status='idle', model=model, provider='fixture'), session=dict(id='chat-'+name, stored_id='stored-'+name, running=False), messages=[dict(role='assistant', text='retained-'+name)], events=[], approval=dict(pending=False), summary=dict(model=dict(name=model, provider='fixture'), models=[], gateway=dict(status='running')))
            data = (dict(hermesHome=str(case/'detected-home'), hermesHomeExists=True, hermesCommand='detected-literal-command', model=dict(name='detected-model',provider='detected-provider')) if self.path == '/detect' else
                    dict(bridge=dict(status='online')) if self.path == '/health' else
                    dict(sessions=[dict(id='stored-'+name)]) if self.path == '/sessions' else
                    dict(state=state) if self.command == 'POST' and self.path != '/session/create' else state)
            self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
            try:
                self.wfile.write(json.dumps(data).encode())
            except (BrokenPipeError, ConnectionResetError):
                pass
        do_GET = do_POST = call
        def log_message(self, *args):
            pass
    done = threading.Event()
    server = Peer(('127.0.0.1', 0), Handler)
    return resources.serve(server, daemon=True, release=done.set)


@receipt_run
def run(args, profile, scenario):
    with FixtureResources() as resources:
        case, out = run_with_peers(args, profile, scenario, resources)
    runner.remove_completed_installs(case, out)


def run_with_peers(args, profile, scenario, resources):
    case, out = args.work_root/scenario, args.output/scenario
    case.mkdir(); out.mkdir()
    for name in ('config/settings', 'cache', 'state', 'home'):
        (case/name).mkdir(parents=True)
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    (case/'requests.jsonl').write_text('')
    if scenario in ('held-retire', 'held-destroy', 'held-source'):
        (case/'hold').write_text('hold')
    if scenario=='model-retire':(case/'hold').write_text('hold');(case/'hold-model').write_text('hold')
    if scenario == 'boundary-retire':
        (case/'hold').touch(); (case/'hold-create').touch()
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=link_or_copy, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    resources.defer(assert_no_survivors, case)
    shared = FixtureResources()
    resources.defer(shared.close)
    peers = [peer(shared, case, 'shared'), peer(resources, case, 'selected')]
    ports = [server.server_address[1] for server in peers]
    if scenario in ('local','failed-start'):
        shared.close()
        (case/'hermes-home').mkdir()
        (case/'hermes-home/config.yaml').write_text('model:\n  default: local-model\n  provider: fixture\n')
    if scenario=='failed-start':
        (case/'bin').mkdir();(case/'fail-start').write_text('fail')
        executable=case/'bin/python3'
        executable.write_text('''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
case=Path(os.environ['PHA_HERMES_CASE'])
if sys.argv[1].endswith('/hermes_bridge.py'):
 with (case/'starts.jsonl').open('a') as output:output.write(json.dumps(sys.argv[1:])+'\\n')
 if (case/'fail-start').read_text()=='fail':sys.exit(23)
os.execv('/usr/bin/python3',['python3',*sys.argv[1:]])
''');executable.chmod(0o755)
    product = args.plugins/'hermes-agent'
    inputs = dict(shell={str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-hermes.qml')}, plugin={str(path.relative_to(product)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(product.rglob('*')) if path.is_file()})
    runner.write_json(out/'inputs.json', inputs)
    prove_peers(args, profile, scenario, case, out, install, product, ports)
    return case, out


def prove_peers(args, profile, scenario, case, out, install, product, ports):
        text = runner.run_fixture(profile, install, case, out, args.source/'Scripts/dev/fixtures/plugin-settings-hermes.qml', extra_env=dict(PHA_HERMES_CASE=str(case), PHA_HERMES_SCENARIO=scenario, PHA_HERMES_PLUGIN=str(product), PHA_HERMES_PORTS=json.dumps(ports), HOME=str(case/'home'),PATH=str(case/'bin')+':'+os.environ['PATH']), extra_lint=tuple(sorted(product.rglob('*.qml'))), timeout=90)
        require('HERMES_CONTRACT: PASS '+scenario in text, 'Hermes runtime verdict missing: '+scenario)
        require(not any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')), text)
        rows = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
        shutil.copy2(case/'requests.jsonl', out/'requests.jsonl')
        if scenario == 'model':
            model = [row for row in rows if row['path'] == '/model']
            require(model and model[-1]['body'] == dict(provider='selected-provider', model='selected-model', persist=False), 'Hermes selected model request body')
            require(model[-1]['peer'] == 'shared' and model[-1]['token'] == 'shared-token', 'Hermes shared model peer and token')
        if scenario=='model-retire':
            model=[row for row in rows if row['path']=='/model']
            require([row['body']['model'] for row in model]==['older-model','latest-model'], 'Hermes retirement request order')
        if scenario in ('pending', 'held-source', 'local'):
            creates = [row for row in rows if row['path'] == '/session/create']
            require(len(creates) == 1 and creates[0]['peer'] == 'selected' and creates[0]['token'] == 'selected-token', 'Hermes selected session request')
        if scenario == 'held-retire':
            require(len([row for row in rows if row['path'] == '/sessions']) == 1, 'Hermes retired sessions request count')
        if scenario == 'boundary-retire':
            require([(row['peer'], row['path']) for row in rows if row['path'] in ('/session/create', '/prompt')] == [('shared', '/session/create'), ('shared', '/prompt')], 'Hermes boundary retirement request destinations')
        if scenario=='failed-start':
            starts=[json.loads(line) for line in (case/'starts.jsonl').read_text().splitlines()]
            require(len(starts)==2 and starts[0]==starts[1], 'Hermes identical restart attempts')
            require(starts[0][-6:]==['--state-file',str(case/'local-state/state.json'),'--hermes-home',str(case/'hermes-home'),'--hermes-command','inert-not-invoked'], 'Hermes restart command')
            shutil.copy2(case/'starts.jsonl',out/'starts.jsonl')
        stage_receipt(out/'result.json', dict(status='PASS', scenario=scenario, requestRows=len(rows), physicalProof=False))


def assert_no_survivors(case):
    survivors=[]
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():continue
        try:command=(path/'cmdline').read_bytes()
        except (FileNotFoundError,ProcessLookupError,PermissionError):continue
        if b'hermes_bridge.py' in command and os.fsencode(str(case)) in command:survivors.append(path.name)
    require(not survivors, ('owned actual helper survived',survivors))


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    scenarios = ('model', 'pending', 'held-retire', 'held-destroy', 'held-source', 'timers', 'callers', 'local', 'failed-start', 'model-retire', 'owner-retire', 'boundary-retire')
    parser.add_argument('--scenario', choices=scenarios)
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-hermes-agent-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        for scenario in ((args.scenario,) if args.scenario else scenarios):
            run(args, profile, scenario)
        stage_receipt(args.output/'result.json', dict(status='PASS', fullMemberAcceptance=False))


if __name__ == '__main__':
    main()
