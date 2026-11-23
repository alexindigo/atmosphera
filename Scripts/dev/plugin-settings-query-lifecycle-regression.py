#!/usr/bin/env python3
"""Controlled query-generation lifetimes, not native page/instance acceptance."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import base64
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import struct
import threading

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(runner)


from fixture_resources import FixtureResources


class HassEndpoint(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, case):
        self.case = case
        self.stopping = threading.Event()
        self.receipt_lock = threading.Lock()
        self.sockets = set()
        super().__init__(('127.0.0.1', 0), HassConnection)

    def record(self, **row):
        with self.receipt_lock, (self.case / 'socket.jsonl').open('a') as stream:
            stream.write(json.dumps(row) + '\n')

    def finish(self):
        self.stopping.set()
        self.shutdown()
        for peer in tuple(self.sockets):
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class HassConnection(socketserver.StreamRequestHandler):
    def send(self, value):
        data = json.dumps(value).encode()
        size = len(data)
        header = bytes([0x81, size]) if size < 126 else bytes([0x81, 126]) + struct.pack('!H', size)
        self.wfile.write(header + data); self.wfile.flush()

    def exact(self, size):
        data = self.rfile.read(size)
        if len(data) != size:
            raise EOFError()
        return data

    def receive(self):
        head = self.exact(2)
        size = head[1] & 127
        if size == 126:
            size = struct.unpack('!H', self.exact(2))[0]
        elif size == 127:
            size = struct.unpack('!Q', self.exact(8))[0]
        mask = self.exact(4) if head[1] & 128 else None
        payload = self.exact(size)
        if mask:
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        if head[0] & 15 == 8:
            raise EOFError()
        if head[0] & 15 != 1:
            raise RuntimeError('unreviewed WebSocket frame')
        return json.loads(payload)

    def handle(self):
        self.server.sockets.add(self.request)
        label = 'unopened'
        try:
            request = self.rfile.readline().decode().split()
            label = request[1].split('/')[1]
            headers = {}
            while True:
                line = self.rfile.readline().decode().strip()
                if not line:
                    break
                key, value = line.split(':', 1); headers[key.lower()] = value.strip()
            digest = hashlib.sha1((headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()
            self.wfile.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + base64.b64encode(digest) + b'\r\n\r\n'); self.wfile.flush()
            self.server.record(source=label, event='open')
            self.send(dict(type='auth_required'))
            count = 0
            while not self.server.stopping.is_set():
                row = self.receive()
                self.server.record(source=label, event='request', message=row)
                kind = row['type']
                if kind == 'auth':
                    label = row['access_token'].split('-')[0]
                    self.send(dict(type='auth_ok'))
                elif kind == 'get_states':
                    count += 1
                    if label == 'old' and count == 3:
                        (self.server.case / 'socket-held').write_text('held')
                        while not (self.server.case / 'release').exists() and not self.server.stopping.wait(0.02):
                            pass
                        self.server.record(source=label, event='held-release-attempt')
                    states = [dict(entity_id='sensor.' + label, state=label, attributes=dict(friendly_name=label + ' entity'))]
                    self.send(dict(type='result', id=row['id'], success=True, result=states))
                elif kind in ('subscribe_events', 'call_service'):
                    self.send(dict(type='result', id=row['id'], success=True, result=[]))
                else:
                    raise RuntimeError('unreviewed HASS request: ' + kind)
        except (EOFError, OSError):
            self.server.record(source=label, event='closed')
        except Exception as error:
            self.server.record(source=label, event='error', error=str(error))
        finally:
            self.server.sockets.discard(self.request)


PING = '''#!/usr/bin/python3
import json, os, time, sys
from pathlib import Path
case=Path(os.environ['PHA_QUERY_CASE'])
me=Path('/proc')/str(os.getpid())/'stat'
start=me.read_text().split(') ',1)[1].split()[19]
with (case/'ping.jsonl').open('a') as stream:
 stream.write(json.dumps(dict(pid=os.getpid(), start=start, argv=sys.argv[1:]))+'\\n')
if sys.argv[-1]=='192.0.2.2':
 (case/'ping-held').write_text(str(os.getpid()))
 engine=Path('/proc')/str(os.getsid(0))/'stat'
 identity=engine.read_text().split(') ',1)[1].split()[19]
 while not (case/'release').exists():
  try:
   if engine.read_text().split(') ',1)[1].split()[19]!=identity: raise SystemExit(0)
  except FileNotFoundError: raise SystemExit(0)
  time.sleep(0.02)
print('64 bytes: time='+('5' if sys.argv[-1]=='192.0.2.1' else '80')+' ms')
'''


@receipt_run
def run(args, profile, plugin):
    with FixtureResources() as resources:
        return run_with_peer(args, profile, plugin, resources)


def run_with_peer(args, profile, plugin, resources):
    case, out = args.work_root / plugin, args.output / plugin
    case.mkdir(); out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / part).mkdir(parents=True)
    dest = case / ('config/plugins/' + plugin)
    shutil.copytree(args.plugins / plugin, dest)
    manifest = json.loads((dest / 'manifest.json').read_text())
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    for name in ('ping.jsonl', 'socket.jsonl'):
        (case / name).write_text('')
    (case / ('socket-held' if plugin == 'hassio' else 'ping-held')).write_text('')
    (case / 'mpris-old-event-done').write_text('')
    for name in ('ping.jsonl', 'socket.jsonl'):
        resources.defer(shutil.copy2, case / name, out / name)
    extra_env = {}
    if plugin == 'mpris-lyric':
        peer_spec = importlib.util.spec_from_file_location('query_mpris', args.source / 'Scripts/dev/fixtures/plugin-settings-mpris-peer.py')
        module = importlib.util.module_from_spec(peer_spec); peer_spec.loader.exec_module(module)
        runtime = Path(profile.child_environment('')['XDG_RUNTIME_DIR'])
        (case / 'mpris.jsonl').write_text('')
        resources.defer(shutil.copy2, case / 'mpris.jsonl', out / 'mpris.jsonl')
        resources.defer(shutil.copy2, case / 'bus.log', out / 'bus.log')
        peer = module.Fixture(case, runtime, resources)
        resources.defer((case / 'release').touch)
        extra_env['DBUS_SESSION_BUS_ADDRESS'] = peer.address
        shared = dict(playerName='query-base')
        selected = dict(playerName='query-old', updateInterval=1500)
        replacement = dict(playerName='query-new', updateInterval=750)
    elif plugin == 'hassio':
        endpoint = HassEndpoint(case)
        resources.serve(endpoint, interrupt=endpoint.finish, release=(case / 'release').touch)
        base = 'http://127.0.0.1:' + str(endpoint.server_address[1])
        shared = dict(haUrl=base + '/shared', haToken='shared-fake-token', entities=['sensor.shared'])
        selected = dict(haUrl=base + '/old', haToken='old-fake-token', entities=['sensor.old'])
        replacement = dict(haUrl=base + '/new', haToken='new-fake-token', entities=['sensor.new'])
    else:
        resources.defer((case / 'release').touch)
        ping = case / 'bin/ping'; ping.write_text(PING); ping.chmod(0o755)
        shared = dict(hosts=[dict(name='Shared', address='192.0.2.1')], intervalSeconds=10)
        selected = dict(hosts=[dict(name='Old', address='192.0.2.2')], intervalSeconds=10)
        replacement = dict(hosts=[dict(name='New', address='192.0.2.3')], intervalSeconds=15)
    defaults = manifest['metadata']['defaultSettings']
    runner.write_json(case / 'input.json', dict(manifest=manifest, directory=str(dest), shared=dict(defaults, **shared), selected=dict(defaults, **selected), replacement=dict(defaults, **replacement)))
    runner.write_json(out / 'sources.json', {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((args.plugins / plugin).rglob('*')) if path.is_file()})
    wanted = 'source replacement synchronously retires old Hosts' if plugin == 'latency-monitor' else 'source replacement clears browser cache and loading'
    try:
        text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-query-lifecycle.qml',
            extra_env=dict(extra_env, PHA_QUERY_PLUGIN=plugin, PHA_QUERY_CASE=str(case), PATH=str(case / 'bin') + ':' + os.environ['PATH']),
            extra_lint=tuple(sorted(dest.glob('*.qml'))), timeout=50)
    except RuntimeError:
        log = out / 'runtime.log'
        if not args.expect_handoff_red or not log.is_file() or wanted not in log.read_text() or (out / 'runtime.exit').read_text().strip() != '2':
            raise
        result = dict(status='PASS', kind='handoff-red', rejectedAt=wanted, nativeOrUIAcceptance=False)
    else:
        if args.expect_handoff_red:
            raise RuntimeError('handoff red escaped')
        if 'QUERY_LIFECYCLE: PASS ' + plugin not in text:
            raise RuntimeError('missing consumer marker')
        if any(value in text for value in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')):
            raise RuntimeError('unexpected construction/runtime diagnostic')
        result = dict(status='PASS', kind='controlled-query-lifecycle', nativeOrUIAcceptance=False)
    resources.close()
    if plugin == 'latency-monitor':
        rows = [json.loads(line) for line in (case / 'ping.jsonl').read_text().splitlines()]
        for row in rows:
            stat = Path('/proc') / str(row['pid']) / 'stat'
            if stat.exists() and stat.read_text().split(') ', 1)[1].split()[19] == row['start']:
                raise RuntimeError('owned ping endpoint survived engine: ' + str(row['pid']))
        result['endpointProcessesQuiescent'] = True
    elif plugin == 'hassio':
        rows = [json.loads(line) for line in (case / 'socket.jsonl').read_text().splitlines()]
        if any(row['event'] == 'error' for row in rows):
            raise RuntimeError('controlled socket error')
        if not args.expect_handoff_red:
            if not any(row['event'] == 'held-release-attempt' for row in rows):
                raise RuntimeError('held old socket response was not released')
            actions = [row for row in rows if row.get('message', {}).get('type') == 'call_service']
            if len(actions) != 1 or actions[0]['source'] != 'next' or actions[0]['message']['service_data']['entity_id'] != 'sensor.next':
                raise RuntimeError('selected service action target differs')
    else:
        rows = [json.loads(line) for line in (case / 'mpris.jsonl').read_text().splitlines()]
        actions = [(row['player'], row['method']) for row in rows if 'method' in row]
        if actions != [('new', 'Next'), ('new', 'Previous'), ('new', 'Pause')] or not any(row.get('event') == 'late-metadata' for row in rows):
            raise RuntimeError('actual MPRIS action/source-lifetime receipts differ')
    stage_receipt(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    print(plugin + ': ' + json.dumps(result), flush=True)
    return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--plugin', choices=('latency-monitor', 'hassio', 'mpris-lyric'))
    parser.add_argument('--expect-handoff-red', action='store_true')
    args = parser.parse_args()
    if args.expect_handoff_red and args.plugin == 'mpris-lyric':
        parser.error('handoff reds cover only Latency and HASS')
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / Path('Scripts/dev') / Path(__file__).name:
        parser.error('execute from supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), driver=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), fixture=hashlib.sha256((args.source / 'Scripts/dev/fixtures/plugin-settings-query-lifecycle.qml').read_bytes()).hexdigest(), mprisPeer=hashlib.sha256((args.source / 'Scripts/dev/fixtures/plugin-settings-mpris-peer.py').read_bytes()).hexdigest(), nativeOrUIAcceptance=False))
        members = ('latency-monitor', 'hassio') if args.expect_handoff_red else ('latency-monitor', 'hassio', 'mpris-lyric')
        results = [run(args, profile, plugin) for plugin in ((args.plugin,) if args.plugin else members)]
        stage_receipt(args.output / 'result.json', dict(status='PASS', cases=results, nativeOrUIAcceptance=False))


if __name__ == '__main__':
    main()
