#!/usr/bin/env python3
"""Individual source/chain/read/cache/action lifetimes; native matrix is separate."""
import argparse
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
import threading
import time
from urllib.parse import parse_qs, unquote, urlparse

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('http_lifetime_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
MEMBERS = ('news', 'ntfy-notifications', 'habitica')


def run(args, profile, plugin):
    case, out = args.work_root / plugin, args.output / plugin
    case.mkdir(); out.mkdir()
    for part in ('config', 'cache', 'state', 'home', 'bin'):
        (case / part).mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
    dest = case / ('config/plugins/' + plugin) if plugin == 'habitica' else case / 'plugin'
    shutil.copytree(args.plugins / plugin, dest)
    requests = case / 'requests.jsonl'; requests.write_text(''); lock = threading.Lock()

    class Endpoint(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_GET(self):
            parsed = urlparse(self.path)
            name = parse_qs(parsed.query).get('q', [''])[0] if plugin == 'news' else unquote(parsed.path.split('/')[1])
            authorization = self.headers.get('Authorization', '')
            with lock:
                with requests.open('a') as stream:
                    stream.write(json.dumps(dict(path=self.path, name=name, authorization=authorization)) + '\n')
            if name == 'held': time.sleep(1.4)
            if plugin == 'news':
                data = dict(status='ok', articles=[dict(title='headline-' + name, description='controlled ' + name)])
            else:
                data = dict(event='message', id='message-' + name, time=2000000000, topic=name, title='headline-' + name, message=authorization)
            self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
            try: self.wfile.write((json.dumps(data) + '\n').encode())
            except BrokenPipeError: pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Endpoint)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    base = 'http://127.0.0.1:' + str(server.server_address[1])
    if plugin == 'news':
        path = dest / 'NewsSettingsClient.qml'; text = path.read_text()
        assert text.count('https://newsapi.org/v2') == 1
        path.write_text(text.replace('https://newsapi.org/v2', base))
    elif plugin == 'habitica':
        path = case / 'bin/curl'; shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-http-endpoint.py', path); path.chmod(0o755)
    wanted = []
    if args.negative_control:
        path = dest / 'Main.qml'; text = path.read_text()
        if args.negative_control == 'duplicate-toast':
            old, new = 'root._notified.has(key)', 'false'
            wanted = ['one common toast for duplicate event across current clients']
        elif args.negative_control == 'cache-owner':
            old = 'return pluginApi?.settingsContext.current() && caller === settingsConsumer && caller.current && caller._worker === worker && worker.active && worker.userId === settingsConsumer.userId'
            new = 'return caller.current && worker.active'
            wanted = ['unqualified legacy cache not assigned to a new source', 'only original shared cache writer publishes qualified shared account']
        else:
            old, new = '(_scoreOwner && _scoreOwner !== worker)', 'false'
            wanted = ['common score admission refuses second client while held']
        if text.count(old) != 1: raise RuntimeError('stale HTTP lifetime mutation: ' + old)
        path.write_text(text.replace(old, new))
        runner.write_json(out / 'mutation.json', dict(path='Main.qml', control=args.negative_control, before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest()))
    manifest = json.loads((dest / 'manifest.json').read_text())
    native_shared = dict(habiticaUserId='shared', habiticaApiToken='controlled-token', _habiticaCache=json.dumps(dict(user=dict(profile=dict(name='unqualified-legacy')), timestamp=2140000000), separators=(',', ':')), opaque=dict(keep='cache-owner-sentinel'))
    if plugin == 'habitica':
        (case / 'config/settings/plugins').mkdir(parents=True)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        runner.write_json(case / 'config/settings/plugins/habitica.json', native_shared)
    runner.write_json(case / 'input.json', dict(plugin=plugin, manifest=manifest, directory=str(dest), base=base, nativeShared=native_shared))
    try:
        rejected = None
        try:
            text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-http-lifecycle.qml', extra_env=dict(PHA_HTTP_PLUGIN=plugin, PHA_HTTP_CASE=str(case), PHA_HTTP_REQUESTS=str(requests), PHA_HTTP_OUTPUT=str(out), PHA_HTTP_CACHE_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-http-cache-disk.py'), HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH']), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=90)
        except RuntimeError:
            text = (out / 'runtime.log').read_text() if (out / 'runtime.log').is_file() else ''
            rejected = next((value for value in wanted if value in text), None)
            if not rejected or (out / 'runtime.exit').read_text().strip() != '2': raise
        if rejected:
            for row in [json.loads(line) for line in requests.read_text().splitlines()]:
                path = Path('/proc') / str(row.get('pid', -1)) / 'stat'
                if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('negative HTTP endpoint survived engine')
            runner.write_json(out / 'result.json', dict(status='PASS', kind='rejecting-control', rejectedAt=rejected, completePlanAcceptance=False))
            runner.remove_completed_installs(case, out)
            print('HTTP_LIFECYCLE_CONTROL ' + args.negative_control + ': PASS', flush=True)
            return
        if wanted: raise RuntimeError('HTTP lifetime mutation escaped')
        if 'HTTP_LIFECYCLE: PASS ' + plugin not in text or any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'HTTP_LIFECYCLE_ASSERT:')):
            raise RuntimeError('HTTP individual lifetime/diagnostic failure')
        rows = [json.loads(line) for line in requests.read_text().splitlines()]
        for row in rows:
            if 'pid' not in row: continue
            path = Path('/proc') / str(row['pid']) / 'stat'
            if path.exists() and path.read_text().split(') ', 1)[1].split()[19] == row['start']:
                raise RuntimeError('Habitica endpoint survived engine')
        runner.write_json(out / 'requests.json', rows)
        if plugin == 'habitica' and json.loads((out / 'native-cache.json').read_text())['status'] != 'PASS':
            raise RuntimeError('missing independent native cache proof')
        runner.write_json(out / 'result.json', dict(status='PASS', plugin=plugin, nativeSharedCacheWriter=plugin == 'habitica', nativePlacementAcceptance=False, completePlanAcceptance=False))
        runner.remove_completed_installs(case, out)
        print('HTTP_LIFECYCLE ' + plugin + ': PASS', flush=True)
    finally:
        server.shutdown(); server.server_close(); thread.join()


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=MEMBERS)
    parser.add_argument('--negative-control', choices=('duplicate-toast', 'cache-owner', 'score-admission'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if args.negative_control and args.plugin != ('ntfy-notifications' if args.negative_control == 'duplicate-toast' else 'habitica'): parser.error('control requires its explicit member')
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-http-lifecycle-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), args.source / 'Scripts/dev/fixtures/plugin-settings-http-lifecycle.qml', args.source / 'Scripts/dev/fixtures/plugin-settings-http-endpoint.py', args.source / 'Scripts/dev/fixtures/plugin-settings-http-cache-disk.py']}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for member in ((args.plugin,) if args.plugin else MEMBERS) for p in (args.plugins / member).rglob('*') if p.is_file()}))
        for plugin in ((args.plugin,) if args.plugin else MEMBERS): run(args, profile, plugin)
        runner.write_json(args.output / 'result.json', dict(status='PASS', completePlanAcceptance=False))


if __name__ == '__main__': main()
