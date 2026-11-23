#!/usr/bin/env python3
"""Real Sticky Notes pages/native owners and controlled Gist operation lifetime."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('sticky_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def run(args, profile, scope, mode):
    with FixtureResources() as resources:
        return run_with_endpoint(args, profile, scope, mode, resources)


def run_with_endpoint(args, profile, scope, mode, resources):
    case = args.work_root/(scope+'-'+mode)
    out = args.output/case.name
    case.mkdir(); out.mkdir()
    for name in ('config/settings/plugins', 'home', 'cache', 'state'):
        (case/name).mkdir(parents=True)
    install = case/'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    product = (args.original_plugins or args.plugins)/'sticky-notes'
    runner.write_json(out/'sources.json', {str(p.relative_to(product)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(product.rglob('*')) if p.is_file()})
    plugin = case/'config/plugins/sticky-notes'
    shutil.copytree(product, plugin)
    shared = dict(syncEnabled=False, githubToken='shared-token', githubGistId='shared-gist', notes=json.dumps([dict(noteId='shared', content='shared-note', modified=1, color='#FFF9C4')]), opaque='shared')
    if mode in ('create', 'find'):
        shared['githubGistId'] = ''
    elif mode == 'missing':
        shared['githubToken'] = ''
    bar = dict(widgets=dict(left=[dict(id='plugin:sticky-notes', instanceSettings=dict(syncEnabled=True, githubToken='instance-token', githubGistId='legacy-gist', notes='legacy-content', opaque='selected')), dict(id='plugin:sticky-notes', instanceSettings=dict(opaque='sibling'))]))
    initial = dict(shared=shared, bar=bar)
    runner.write_json(case/'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case/'config/plugins.json', dict(version=6, states={}, sources=[]))
    runner.write_json(case/'config/settings/plugins/sticky-notes.json', shared)
    runner.write_json(case/'config/settings/bar.json', bar)
    (case/'marker').write_text('')
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def call(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            requests.append(dict(method=self.command, path=self.path, token=self.headers.get('Authorization'), body=json.loads(body) if body else None))
            if mode in ('replace', 'target-replace', 'destroy', 'original-replace', 'busy') and self.command == 'GET':
                (case/'marker').write_text('held')
                deadline = time.monotonic()+15
                while (case/'marker').read_text().strip() != 'release' and time.monotonic() < deadline:
                    time.sleep(.02)
            gist_id = 'created-gist' if mode == 'create' else 'found-gist' if mode == 'find' else 'shared-gist'
            payload = dict(id=gist_id, description='noctalia-sticky-notes', files={'shared': dict(content='old-note')})
            if self.path.startswith('/gists?'):
                payload = [payload] if mode == 'find' else []
            self.send_response(503 if mode == 'failure' else 200); self.send_header('Content-Type', 'application/json'); self.end_headers()
            try:
                self.wfile.write(json.dumps(payload).encode())
            except (BrokenPipeError, ConnectionResetError):
                pass

        do_GET = call
        do_PATCH = call
        do_POST = call

        def log_message(self, *unused):
            pass

    resources.defer(runner.write_json, out/'requests.json', requests)
    server = resources.serve(ThreadingHTTPServer(('127.0.0.1', 0), Handler))
    utility = plugin/'utils/gistSync.js'
    text = utility.read_text()
    old = 'var API_BASE_URL = "https://api.github.com";'
    assert text.count(old) == 1
    utility.write_text(text.replace(old, 'var API_BASE_URL = "http://127.0.0.1:'+str(server.server_port)+'";'))
    original_lint = False
    try:
        log = runner.run_fixture(profile, install, case, out, args.source/'Scripts/dev/fixtures/plugin-settings-sticky-native.qml', extra_env=dict(PHA_STICKY_CASE=str(case), PHA_STICKY_SCOPE=scope, PHA_STICKY_MODE=mode, PHA_STICKY_CAPTURE=str(out/'full-screen.png'), HOME=str(case/'home')), extra_lint=tuple(sorted(plugin.rglob('*.qml'))), timeout=120)
    except RuntimeError as error:
        # The unchanged original's duplicate inherited screen declaration is
        # an explicit failed lint receipt, never candidate lint acceptance.
        if not args.original_plugins or str(error) != 'fixture lint failed in the actual qs/native universe; see lint.log':
            raise
        lint = (out/'lint.log').read_text()
        assert 'Property "screen" already exists in base type "WindowInterface"' in lint
        assert (out/'runtime.exit').read_text().strip() == '0'
        log = (out/'runtime.log').read_text()
        original_lint = True
    resources.close()
    assert 'STICKY: PASS '+scope+' '+mode in log
    assert not any(word in log for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')), log
    actual = dict(shared=json.loads((case/'config/settings/plugins/sticky-notes.json').read_text()), bar=json.loads((case/'config/settings/bar.json').read_text()))
    expected = deepcopy(initial)
    if mode == 'native' and scope == 'shared':
        expected['shared']['githubToken'] = 'edited-token'
        expected['shared']['syncEnabled'] = True
    elif mode == 'original':
        expected['bar']['widgets']['left'][0]['instanceSettings']['githubToken'] = 'selected-token'
    elif mode in ('replace', 'original-replace'):
        expected['shared']['githubToken'] = 'replacement-token'
    elif mode == 'target-replace':
        expected['shared']['githubGistId'] = 'replacement-gist'
    elif mode in ('create', 'find'):
        expected['shared']['githubGistId'] = 'created-gist' if mode == 'create' else 'found-gist'
    elif mode == 'reset':
        target = expected['shared'] if scope == 'shared' else expected['bar']['widgets']['left'][0]['instanceSettings']
        for key in ('githubToken', 'syncEnabled'):
            target.pop(key)
    assert actual == expected, (actual, expected)
    runner.write_json(out/'documents.json', dict(status='PASS', initial=initial, expected=expected, actual=actual))
    if mode in ('cold', 'missing', 'reset', 'capture'):
        assert not requests
    elif mode in ('replace', 'target-replace', 'destroy'):
        assert len(requests) == 1 and requests[0]['method'] == 'GET', requests
    elif mode == 'failure':
        assert [row['method'] for row in requests] == ['GET', 'GET'], requests
    elif mode in ('create', 'find'):
        assert [row['method'] for row in requests] == ['GET', 'POST' if mode == 'create' else 'PATCH'], requests
        assert all(row['token'] == 'Bearer shared-token' for row in requests)
        assert requests[-1]['body']['files'] == {'shared': {'content': 'shared-note'}}
    else:
        assert [row['method'] for row in requests] == ['GET', 'PATCH'], requests
        wanted = 'edited-token' if scope == 'shared' and mode == 'native' else 'shared-token'
        assert all(row['token'] == 'Bearer '+wanted and row['path'] == '/gists/shared-gist' for row in requests), requests
        content = 'unadmitted-later-content' if mode == 'original-replace' else 'shared-note'
        assert requests[-1]['body']['files'] == {'shared': {'content': content}}, requests
    runner.write_json(out/'result.json', dict(status='PASS', scope=scope, mode=mode, completeDocuments=True, requestCount=len(requests), inheritedOriginalLintFailed=original_lint, physicalProof=False))
    if mode in ('native', 'create', 'find', 'reset'):
        cold = out/'cold'; cold.mkdir()
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
        count = len(requests)
        cold_log = runner.run_fixture(profile, install, case, cold, args.source/'Scripts/dev/fixtures/plugin-settings-sticky-native.qml', extra_env=dict(PHA_STICKY_CASE=str(case), PHA_STICKY_SCOPE=scope, PHA_STICKY_MODE='cold', HOME=str(case/'home')), extra_lint=tuple(sorted(plugin.rglob('*.qml'))), timeout=120)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case/'config').rglob('*.json')}
        assert 'STICKY: PASS '+scope+' cold' in cold_log and before == after and len(requests) == count
        runner.write_json(cold/'configuration-hashes.json', dict(status='PASS', before=before, after=after, nonpublishing=True))
    runner.remove_completed_installs(case, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--original-plugins', type=Path)
    parser.add_argument('--mode', choices=('native', 'original', 'cold', 'replace', 'destroy', 'original-replace', 'target-replace', 'busy', 'create', 'find', 'failure', 'missing', 'reset', 'capture'), default='native')
    parser.add_argument('--scope', choices=('shared', 'instance'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve()/'Scripts/dev/plugin-settings-sticky-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs = [Path(__file__), args.source/'Scripts/dev/fixtures/plugin-settings-sticky-native.qml']
        runner.write_json(args.output/'inputs.json', {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        for scope in ((args.scope,) if args.scope else ('instance', 'shared')):
            run(args, profile, scope, args.mode)
        runner.write_json(args.output/'result.json', dict(status='PASS', mode=args.mode))
    print('STICKY_REGRESSION: PASS')


if __name__ == '__main__':
    main()
