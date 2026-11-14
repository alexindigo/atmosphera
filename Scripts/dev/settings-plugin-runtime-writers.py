#!/usr/bin/env python3
"""Native runtime writers not exercised by plugin settings pages; guest only."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'installed', 'output', 'work-root'):
        parser.add_argument('--'+key, type=Path, required=True)
    args = parser.parse_args()
    assert subprocess.check_output(['timeout', '10', 'sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], timeout=15).decode().strip() == '12f17a02-25e9-474c-9dae-fea092c2d2be'
    assert args.work_root.resolve().is_relative_to('/home/tester/Projects/atcq')
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    home = args.work_root/'detected-hermes'
    home.mkdir()
    requests = []

    class Bridge(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_GET(self):
            requests.append(self.path)
            response = {'bridge': {'status': 'online'}, 'session': {'running': False},
                        'hermes': {'status': 'online'}, 'summary': {'model': {'name': 'runtime-model', 'provider': 'runtime-provider'}, 'gateway': {'status': 'online'}}}
            if self.path == '/detect':
                response = dict(hermesHome=str(home), hermesHomeExists=True, hermesCommand='runtime-hermes',
                                model=dict(name='runtime-model', provider='runtime-provider'))
            data = json.dumps(response).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Bridge)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    probe = args.installed/'i5-runtime-writers.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/plugin-runtime-writers.qml').read_bytes())
    cases = []
    try:
        for name in ('todo', 'hermes-agent', 'weekly-calendar'):
            root = args.work_root/name
            config = root/'c'
            (config/'settings/plugins').mkdir(parents=True)
            (root/'cache').mkdir()
            (root/'state').mkdir()
            plugin = config/'plugins'/name
            shutil.copytree(args.plugins/name, plugin)
            (config/'settings.json').write_text('{"settingsVersion":62}')
            (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
            seed = dict(opaque=dict(keep=True))
            if name == 'todo':
                seed.update(pages=[dict(id=0, name='General'), dict(id=7, name='Delete')], current_page_id=7,
                            todos=[dict(id=i, text='task', pageId=7, completed=bool(i), priority='medium', details='', opaque=dict(keep=True)) for i in range(2)], count=2, completedCount=1)
            elif name == 'hermes-agent':
                seed.update(configured=False, clientOnlyMode=True, bridgeHost='127.0.0.1', bridgePort=server.server_port,
                            autoStartBridge=False, autoStartGateway=False, panelPinned=False,
                            hermesHome=str(home), stateFile=str(root/'state/state.json'), statusPollIntervalSec=3600)
            else:
                seed.update(weekStart='', timeFormat='12h', lineColorType='mOnSurfaceVariant', hourLineOpacity=0.1, dayLineOpacity=0.2)
            target = config/'settings/plugins'/(name+'.json')
            target.write_text(json.dumps(seed)[:-1]+',"wide":18446744073709551615}\n')
            prior = None
            for cold in (False, True):
                detect_before = requests.count('/detect')
                env = dict(os.environ, QML_DISABLE_DISK_CACHE='1', I5_RUNTIME_PLUGIN=name, I5_RUNTIME_HOME=str(home),
                           I5_RUNTIME_COLD='1' if cold else '0', I5_RUNTIME_MANIFEST=(plugin/'manifest.json').read_text(),
                           ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root/'cache'), ATMOSPHERA_STATE_DIR=str(root/'state'))
                result = subprocess.run(['timeout', '30', 'qs', '-p', str(probe), '--no-color'], env=env, capture_output=True, text=True, timeout=35)
                text = result.stdout+result.stderr
                label = name+('-cold' if cold else '-saved')
                (args.output/(label+'.log')).write_text(text)
                assert result.returncode == 0 and 'I5_RUNTIME_WRITERS: PASS' in text, text[-7000:]
                assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-7000:]
                raw = target.read_bytes()
                value = json.loads(raw)
                assert value['opaque'] == dict(keep=True) and value['wide'] == 18446744073709551615
                if name == 'todo':
                    assert len(value['pages']) == 1 and value['current_page_id'] == 0 and value['count'] == 2 and value['completedCount'] == 1
                    assert all(row['pageId'] == 0 and row['opaque'] == dict(keep=True) for row in value['todos'])
                elif name == 'hermes-agent':
                    assert value['configured'] and value['hermesCommand'] == 'runtime-hermes' and value['defaultModel'] == 'runtime-model' and value['defaultProvider'] == 'runtime-provider'
                    assert requests.count('/detect') == detect_before if cold else requests.count('/detect') > detect_before
                else:
                    assert all(value[key] == expected for key, expected in dict(weekStart='1', timeFormat='24h', lineColorType='mOutline', hourLineOpacity=0.5, dayLineOpacity=1.0).items())
                metadata = target.stat()
                observed = (raw, metadata.st_ino, metadata.st_mtime_ns, metadata.st_mode)
                if cold:
                    assert observed == prior, 'cold runtime may not republish settings'
                prior = observed
                cases.append(dict(id=label, status='PASS', rawSha256=hashlib.sha256(raw).hexdigest()))
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=cases, bridgeRequests=requests), indent=2)+'\n')
        print('SETTINGS_PLUGIN_RUNTIME_WRITERS: PASS (actual Main save, consumer, raw data and cold)')
    finally:
        probe.unlink()
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
