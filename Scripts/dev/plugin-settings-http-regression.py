#!/usr/bin/env python3
"""Selected HTTP results: real pages/native documents and final Bar/Panel children."""
from fixture_receipts import receipt_run, stage_receipt
from fixtures.source_delivery import link_or_copy
import argparse
from copy import deepcopy
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import shutil
import threading
from urllib.parse import parse_qs, unquote, urlparse

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('http_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
MEMBERS = ('news', 'ntfy-notifications')


def hashes(case):
    return {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case / 'config').rglob('*.json'))}


@receipt_run
def run(args, profile, plugin, scope):
    with FixtureResources() as resources:
        return run_with_endpoint(args, profile, plugin, scope, resources)


def run_with_endpoint(args, profile, plugin, scope, resources):
    case, out = args.work_root / (plugin + '-' + scope), args.output / (plugin + '-' + scope)
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    rows, row_lock = [], threading.Lock()

    class Endpoint(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            request = urlparse(self.path); query = parse_qs(request.query)
            name = query.get('q', [''])[0] if plugin == 'news' else unquote(request.path.split('/')[1])
            with row_lock:
                rows.append(dict(path=self.path, authorization=self.headers.get('Authorization', '')))
            if plugin == 'news':
                data = json.dumps(dict(status='ok', articles=[dict(title='headline-' + name, description='controlled ' + name)]))
            else:
                data = json.dumps(dict(event='message', id='message-' + name, time=2000000000, topic=name, title='headline-' + name, message='controlled ' + name)) + '\n'
            self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(data.encode())

    resources.defer(runner.write_json, out / 'requests.json', rows)
    server = resources.serve(ThreadingHTTPServer(('127.0.0.1', 0), Endpoint), daemon=True)
    base_url = 'http://127.0.0.1:' + str(server.server_address[1])
    install = case / 'install'
    shutil.copytree(args.source, install, copy_function=link_or_copy, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
    for part in ('config/settings/plugins', 'cache', 'state', 'home'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin); shutil.copytree(args.plugins / plugin, dest)
    news = plugin == 'news'; field, value = ('category', 'technology') if news else ('topics', 'selected')
    shared = dict(opaque=dict(keep='shared'))
    shared.update(dict(apiKey='controlled-key', category='general') if news else dict(serverUrl=base_url, topics='shared', authMethod='token', authToken='controlled-token', enableToasts=False, readMessageIds=['protected-read']))
    overrides = dict(opaque=dict(keep='selected'))
    bar = dict(widgets=dict(left=[dict(id='plugin:' + plugin, instanceSettings=overrides), dict(id='plugin:' + plugin, instanceSettings={field: value}), dict(id='plugin:' + plugin, instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])[field] = value
    reset = deepcopy(edited); (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop(field)
    following = deepcopy(reset); following['shared'][field] = value
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    if not news:
        actions = deepcopy(following)
        actions['shared']['readMessageIds'].append('message-selected')
        expected['actions'] = actions
    for path, data in [('input.json', dict(plugin=plugin)), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/' + plugin + '.json', shared), ('config/settings/bar.json', bar)]:
        runner.write_json(case / path, data)
    # Replace only the fixed external provider origin, never the request builder,
    # selected policy, parsing, callback or final child consumers.
    if news:
        files = [dest / ('BarWidget.qml' if args.old_red else 'NewsSettingsClient.qml')]
        for path in files:
            text = path.read_text()
            if text.count('https://newsapi.org/v2') != 1:
                raise RuntimeError('review controlled News origin boundary')
            path.write_text(text.replace('https://newsapi.org/v2', base_url))
    wanted = 'original shared HTTP result does not render saved selected source' if args.old_red else None
    if args.negative_control:
        path = dest / 'Panel.qml'; old = 'settingsConsumerFor(pluginApi.settingsContext)'
        text = path.read_text()
        if text.count(old) != 1:
            raise RuntimeError('stale selected HTTP consumer mutation')
        path.write_text(text.replace(old, 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)'))
        wanted = 'actual views share exact selected HTTP client'
    env = dict(PHA_HTTP_PLUGIN=plugin, PHA_HTTP_SCOPE=scope, PHA_HTTP_CASE=str(case), PHA_HTTP_OUTPUT=str(out), PHA_HTTP_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-http-disk.py'), PHA_HTTP_OLD_RED='1' if args.old_red else '0', HOME=str(case / 'home'))
    sequence = [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following')]
    if not news: sequence += [('actions', ''), ('cold', 'actions')]
    for mode, boundary in sequence:
        output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir(); before = hashes(case)
        try:
            text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-http-native.qml', extra_env=dict(env, PHA_HTTP_MODE=mode, PHA_HTTP_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            if not wanted or not (output / 'runtime.log').is_file() or wanted not in (output / 'runtime.log').read_text() or (output / 'runtime.exit').read_text().strip() != '2':
                raise
            if args.old_red and not (out / 'persisted/edited.json').is_file():
                raise RuntimeError('original HTTP red never reached independent native publication')
            result = dict(status='PASS', kind='original-shared-http-red' if args.old_red else 'rejecting-control', rejectedAt=wanted, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out); return result
        if 'HTTP_NATIVE: PASS ' + plugin + ' ' + scope + ' ' + mode not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'HTTP_NATIVE_ASSERT:')):
            raise RuntimeError('HTTP native consumer/diagnostic failure')
        if mode == 'cold' and hashes(case) != before:
            raise RuntimeError('cold HTTP reader published configuration')
        stage_receipt(output / 'observed.json', dict(status='PASS', configurationHashes=hashes(case)))
    if wanted:
        raise RuntimeError('HTTP control escaped')
    for boundary, data in expected.items():
        if json.loads((out / ('persisted/' + boundary + '.json')).read_text()) != dict(status='PASS', values=data):
            raise RuntimeError('complete HTTP documents differ')
    result = dict(status='PASS', plugin=plugin, scope=scope, independentBoundaries=sorted(expected), unchangedHashColdReaders=['edited', 'reset', 'following'] + ([] if news else ['actions']), physicalProof=False, completePlanAcceptance=False)
    stage_receipt(out / 'result.json', result); runner.remove_completed_installs(case, out)
    print('HTTP_NATIVE ' + plugin + '/' + scope + ': PASS', flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=MEMBERS); parser.add_argument('--scope', choices=('shared', 'instance'))
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--old-red', action='store_true')
    oracle.add_argument('--negative-control', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-http-regression.py':
        parser.error('execute supplied source')
    if (args.old_red or args.negative_control) and (not args.plugin or args.scope != 'instance'):
        parser.error('control requires explicit instance member')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-http-native.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-http-disk.py']
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for member in ((args.plugin,) if args.plugin else MEMBERS) for p in (args.plugins / member).rglob('*') if p.is_file()}))
        results = [run(args, profile, plugin, scope) for plugin in ((args.plugin,) if args.plugin else MEMBERS) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__':
    main()
