#!/usr/bin/env python3
"""Selected Spotify native pages and inert runtime OAuth/action continuations."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
from copy import deepcopy
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
import re
from pathlib import Path
import select
import shutil
import socket
import threading
from fixture_resources import FixtureResources
import time
from urllib.parse import parse_qs, urlparse
import base64

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('spotify_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


@receipt_run
def run(args, profile, scope):
    with FixtureResources() as resources:
        result, case, out = run_with_endpoint(args, profile, scope, resources)
    for line in (case / 'endpoint-pids.jsonl').read_text().splitlines() if (case / 'endpoint-pids.jsonl').exists() else []:
        row = json.loads(line); stat = Path('/proc') / str(row['pid']) / 'stat'
        if stat.exists() and stat.read_text().split(') ', 1)[1].split()[19] == row['start']: raise RuntimeError('Spotify endpoint survived engine')
    runner.remove_completed_installs(case, out)
    print('SPOTIFY ' + scope + ': PASS', flush=True); return result


def run_with_endpoint(args, profile, scope, resources):
    case, out = args.work_root / scope, args.output / scope
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    for part in ('config/settings/plugins', 'cache', 'state', 'home', 'bin'):
        (case / part).mkdir(parents=True)
    install = case / 'install'
    shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
    dest = case / 'config/plugins/spotify-player'; shutil.copytree(args.plugins / 'spotify-player', dest)
    with socket.socket() as port_socket:
        port_socket.bind(('127.0.0.1', 0)); port = port_socket.getsockname()[1]
    shared = dict(clientId='shared', clientSecret='controlled-secret', callbackPort=port, playerId='shared-player', accessToken='seed-access', refreshToken='seed-refresh', tokenExpiresAt=0, opaque=dict(keep='shared'))
    bar = dict(widgets=dict(left=[dict(id='plugin:spotify-player', instanceSettings=dict(opaque=dict(keep='selected'), accessToken='selected-legacy-access', refreshToken='selected-legacy-refresh', tokenExpiresAt=0)), dict(id='plugin:spotify-player', instanceSettings=dict(clientId='sibling', playerId='sibling-player')), dict(id='plugin:spotify-player', instanceSettings=dict(opaque=dict(keep='inherited')))]))
    initial = dict(shared=shared, bar=bar); edited = deepcopy(initial)
    (edited['shared'] if scope == 'shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['clientId'] = 'selected'
    reset = deepcopy(edited); (reset['shared'] if scope == 'shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('clientId')
    following = deepcopy(reset); following['shared']['clientId'] = 'following'
    expected = dict(initial=initial, discarded=initial, edited=edited, **{'reset-staged': edited}, reset=reset, following=following)
    for path, value in [('input.json', dict(plugin='spotify-player')), ('expectations.json', expected), ('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/spotify-player.json', shared), ('config/settings/bar.json', bar)]: runner.write_json(case / path, value)
    request_file = case / 'requests.jsonl'; request_file.write_text('')
    record_lock = threading.Lock()
    released = threading.Event()
    request_id = 0

    def record(row):
        with request_file.open('a') as log: log.write(json.dumps(row) + '\n')

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def peer_closed(self):
            if not select.select([self.connection], [], [], 0)[0]:
                return False
            try:
                return self.connection.recv(1, socket.MSG_PEEK) == b''
            except ConnectionResetError:
                return True

        def respond(self):
            nonlocal request_id
            body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
            client = ''
            if self.headers.get('Authorization', '').startswith('Basic '):
                client = base64.b64decode(self.headers['Authorization'][6:]).decode().split(':')[0]
            marker = case / ('hold-' + client) if client else case / 'hold-api'
            held = marker.exists()
            with record_lock:
                request_id += 1
                identity = request_id
                record(dict(id=identity, path=self.path, method=self.command, client=client, bearer=self.headers.get('Authorization', '') if not client else '', body=body, held=held))
            end = time.monotonic() + 15
            if held:
                while not released.is_set():
                    # Before any response bytes, EOF/reset confirms this exact
                    # held connection cannot get a response. A server write
                    # (including a failed write) is not a client receipt.
                    if self.peer_closed():
                        with record_lock:
                            record(dict(cancelled=identity))
                        return
                    if not marker.exists() or time.monotonic() >= end:
                        break
                    released.wait(.025)
                if released.is_set():
                    return
            if self.path == '/api/token':
                values = parse_qs(body)
                data = dict(access_token=('late-' if held else 'access-') + client, refresh_token='refresh-' + client, expires_in=3600)
                if values.get('code') == ['fail']: data = dict(error='controlled-denial')
            elif self.path.startswith('/v1/me/player/devices'): data = dict(devices=[dict(name='Controlled device', id='device-selected')])
            elif self.path.startswith('/v1/search'): data = dict(tracks=dict(items=[dict(type='track', uri='spotify:track:controlled', name='Late track' if held else 'Controlled track', artists=[dict(name='Controlled artist')])]), albums=dict(items=[]), playlists=dict(items=[]))
            elif self.path.startswith('/v1/me/playlists'): data = dict(items=[dict(type='playlist', uri='spotify:playlist:controlled', name='Controlled playlist', owner=dict(display_name='Controlled owner'))])
            else: data = dict(shuffle_state=False)
            payload = json.dumps(data).encode()
            try:
                self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.send_header('X-Fixture-Request', str(identity)); self.end_headers(); self.wfile.write(payload)
            except (BrokenPipeError, ConnectionResetError): pass
        do_GET = respond
        do_POST = respond
        do_PUT = respond

    def copy_if_present(name):
        if (case / name).exists(): shutil.copy2(case / name, out / name)

    def remove_hold_markers():
        with FixtureResources() as markers:
            for marker in case.glob('hold-*'): markers.defer(marker.unlink, missing_ok=True)

    resources.defer(shutil.copy2, request_file, out / 'requests.jsonl')
    for name in ('endpoint-pids.jsonl', 'browser.jsonl'):
        resources.defer(copy_if_present, name)
    resources.defer(remove_hold_markers)
    server = resources.serve(ThreadingHTTPServer(('127.0.0.1', 0), Handler), daemon=True, release=released.set)
    origin = 'http://127.0.0.1:' + str(server.server_port)
    substitutions = []
    if (dest / 'Auth.js').read_text().count('https://accounts.spotify.com/api/token') != 1:
        raise RuntimeError('review changed token origin before any runtime IO')
    for path in dest.glob('*'):
        if path.suffix not in ('.qml', '.js'): continue
        original = path.read_text()
        changed = original.replace('https://accounts.spotify.com/api/token', origin + '/api/token').replace('https://api.spotify.com', origin)
        if any(url != 'https://accounts.spotify.com/authorize?' for url in re.findall(r'https://[^\s"\x27]+', changed)):
            raise RuntimeError('unreviewed external Spotify origin in ' + path.name)
        if changed != original:
            path.write_text(changed); substitutions.append(dict(path=path.name, kind='inert-loopback-origin', before=hashlib.sha256(original.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest()))
    listener = dest / 'callback_server.py'; original = listener.read_text()
    observed = '''import json, os
from pathlib import Path
with (Path(os.environ['PHA_SPOTIFY_CASE']) / 'endpoint-pids.jsonl').open('a') as receipt:
    receipt.write(json.dumps(dict(pid=os.getpid(), start=Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19], command='callback_server')) + '\\n')
'''
    listener.write_text(observed + original)
    substitutions.append(dict(path=listener.name, kind='listener-pid-start-observation', before=hashlib.sha256(original.encode()).hexdigest(), after=hashlib.sha256(listener.read_bytes()).hexdigest()))
    for command in ('curl', 'xdg-open'):
        endpoint = case / 'bin' / command
        endpoint.write_text((args.source / 'Scripts/dev/fixtures/plugin-settings-spotify-endpoint.py').read_text()); endpoint.chmod(0o755)
    wanted = 'original refresh uses saved selected credentials' if args.old_red else None
    if args.control:
        path = dest / 'Main.qml'
        old, new, wanted = ('var writer = runtimeApi;', 'var writer = root.pluginApi;', 'operational action preserves independent native documents')
        text = path.read_text()
        if text.count(old) != 1: raise RuntimeError('stale Spotify control: ' + args.control)
        path.write_text(text.replace(old, new)); substitutions.append(dict(path=path.name, kind=args.control, before=hashlib.sha256(text.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest()))
    runner.write_json(out / 'substitutions.json', substitutions)
    env = dict(PHA_SPOTIFY_CASE=str(case), PHA_SPOTIFY_OUTPUT=str(out), PHA_SPOTIFY_SCOPE=scope, PHA_SPOTIFY_OLD_RED='1' if args.old_red else '0', PHA_SPOTIFY_ACTION_BASE='initial' if args.control or args.actions_only else 'following', PHA_SPOTIFY_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-spotify-disk.py'), PHA_SPOTIFY_ORIGIN=origin, HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'])
    modes = [('edit', ''), ('cold', 'edited'), ('reset', ''), ('cold', 'reset'), ('follow', ''), ('cold', 'following'), ('actions', ''), ('action-cold', '')]
    if args.old_red: modes = [('edit', '')]
    if args.control or args.actions_only: modes = [('actions', '')] + ([] if args.control else [('action-cold', '')])
    result = prove_modes(args, profile, scope, modes, case, out, install, dest, env, wanted, expected)
    return result, case, out


def prove_modes(args, profile, scope, modes, case, out, install, dest, env, wanted, expected):
        for mode, boundary in modes:
            output = out / (mode + ('-' + boundary if boundary else '')); output.mkdir()
            before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'config/settings').rglob('*.json')}
            try:
                text = runner.run_fixture(profile, install, case, output, args.source / 'Scripts/dev/fixtures/plugin-settings-spotify-native.qml', extra_env=dict(env, PHA_SPOTIFY_MODE=mode, PHA_SPOTIFY_BOUNDARY=boundary), extra_lint=tuple(sorted(dest.rglob('*.qml'))), timeout=160)
            except RuntimeError:
                log = (output / 'runtime.log').read_text()
                if not wanted or wanted not in log or (output / 'runtime.exit').read_text().strip() != '2': raise
                if args.old_red and not (out / 'persisted/edited.json').is_file(): raise RuntimeError('original red precedes independent native publication')
                result = dict(status='PASS', kind='original-native-red' if args.old_red else 'rejecting-runtime-control', rejectedAt=wanted, completePlanAcceptance=False)
                stage_receipt(out / 'result.json', result); break
            if wanted: raise RuntimeError('Spotify control escaped')
            if 'SPOTIFY_NATIVE: PASS ' + scope + ' ' + mode not in text or any(k in text for k in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'SPOTIFY_ASSERT:')): raise RuntimeError('Spotify runtime outcome/diagnostic failure')
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'config/settings').rglob('*.json')}
            if mode in ('cold', 'action-cold') and before != after: raise RuntimeError('cold Spotify reader published')
            stage_receipt(output / 'observed.json', dict(status='PASS', mode=mode, configurationBefore=before, configurationAfter=after))
        else:
            result = dict(status='PASS', scope=scope, independentBoundaries=sorted(expected) if not args.actions_only else [], unchangedHashColdReaders=(['authorized'] if args.actions_only else ['edited', 'reset', 'following', 'authorized']), runtimeAuthorization=True, nativePageProof=not args.actions_only, physicalProof=False, completePlanAcceptance=False)
            stage_receipt(out / 'result.json', result)
        return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--scope', choices=('shared', 'instance')); parser.add_argument('--old-red', action='store_true'); parser.add_argument('--control', choices=('writer',)); parser.add_argument('--actions-only', action='store_true')
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-spotify-regression.py': parser.error('execute supplied source')
    if (args.old_red or args.control) and args.scope != 'instance': parser.error('control requires instance scope')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__)] + list((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-spotify-*'))
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'spotify-player').rglob('*') if p.is_file()}))
        results = [run(args, profile, scope) for scope in ((args.scope,) if args.scope else ('instance', 'shared'))]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, completePlanAcceptance=False))


if __name__ == '__main__': main()
