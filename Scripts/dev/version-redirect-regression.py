#!/usr/bin/env python3
"""Run in a Quickshell/Niri test VM with TMPDIR on the guest workspace disk."""
import argparse
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
from threading import Thread

from qml_probe import inject_probe, probe_owner_path
from workspace_guard import require_disk_backed_paths


RELEASE = '/repos/atmosphera-dev/atmosphera/releases/latest'
MAIN = '/repos/atmosphera-dev/atmosphera/commits/main'
QS = '/repos/quickshell-mirror/quickshell/releases/latest'
CONTRIBUTORS = '/repos/noctalia-dev/noctalia-shell/contributors?per_page=100'
SHA = 'ab' * 20
ANSWERS = {RELEASE: {'tag_name': 'v91.2.3'}, MAIN: {'sha': SHA},
           QS: {'tag_name': 'v8.7.6'}, CONTRIBUTORS: [{'login': 'redirect-fixture'}]}

PROBE = r'''
  Timer {
    property int ticks: 0
    interval: 200; running: true; repeat: true
    onTriggered: {
      if (!Settings.isLoaded)
        return;
      if (++ticks < 15)
        return;
      console.log("VERSION_REDIRECT|" + JSON.stringify({release: Version.latestVersion,
        sha: Version.latestMainCommit, qs: Version.latestQSVersion,
        contributor: Version.contributors[0]?.login ?? ""}));
      Qt.callLater(Qt.quit);
    }
  }
'''


def run(source, work, loop):
    work.mkdir()
    requests = Counter()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests[self.path] += 1
            if self.path in ANSWERS:
                self.send_response(301)
                self.send_header('Location', self.path if loop and self.path == RELEASE else '/moved' + self.path)
                self.end_headers()
            elif self.path.startswith('/moved') and self.path.removeprefix('/moved') in ANSWERS:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(ANSWERS[self.path.removeprefix('/moved')]).encode())
            else:
                self.send_error(404)

        def log_message(self, *args):
            pass

    shell = work / 'shell'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__'))
    probe = probe_owner_path(shell)
    probe.write_text(inject_probe(probe.read_text(), PROBE))
    for name in ('tmp', 'home', 'config', 'data', 'cache', 'state', 'bin'):
        (work / name).mkdir()
    config = work / 'config/atmosphera/settings'
    config.mkdir(parents=True)
    (config / 'general.json').write_text('{"showChangelogOnStartup":false,"autoUpdatePlugins":false}')
    bus = work / 'dbus.conf'
    bus.write_text(Path('/usr/share/dbus-1/session.conf').read_text().replace('unix:tmpdir=/tmp', f'unix:tmpdir={work}/tmp'))
    curl = work / 'bin/curl'
    # Keep the actual command's options; route only GitHub API requests to the fixture.
    curl.write_text('''#!/usr/bin/env python3
import os, sys
url = sys.argv[-1]
prefix = 'https://api.github.com'
if not url.startswith(prefix + '/'):
    sys.exit(2)
os.execv('/usr/bin/curl', ['curl', '--noproxy', '*', *sys.argv[1:-1],
                          os.environ['FIXTURE_ORIGIN'] + url.removeprefix(prefix)])
''')
    curl.chmod(0o700)
    with HTTPServer(('127.0.0.1', 0), Handler) as server:
        thread = Thread(target=server.serve_forever)
        thread.start()
        try:
            env = dict(os.environ, HOME=str(work / 'home'), TMPDIR=str(work / 'tmp'),
                       PATH=f'{curl.parent}:{os.environ["PATH"]}', FIXTURE_ORIGIN=f'http://127.0.0.1:{server.server_port}',
                       QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', ATMOSPHERA_DEBUG='0',
                       ATMOSPHERA_GITHUB_FILE=str(work / 'cache/github.json'), ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9',
                       **{f'XDG_{name.upper()}_HOME': str(work / name) for name in ('config', 'data', 'cache', 'state')})
            result = subprocess.run(['timeout', '--kill-after=5s', '20s', 'dbus-run-session',
                                     '--config-file=' + str(bus), '--', 'qs', '--no-color', '-p', str(shell / 'shell.qml')],
                                    env=env, capture_output=True, text=True, timeout=30)
        finally:
            server.shutdown()
            thread.join()
    output = result.stdout + result.stderr
    (work / 'shell.log').write_text(output)
    assert result.returncode == 0 and 'Configuration Loaded' in output, output[-2000:]
    values = [json.loads(line.split('VERSION_REDIRECT|', 1)[1]) for line in output.splitlines() if 'VERSION_REDIRECT|' in line]
    assert len(values) == 1, (values, requests)
    print(json.dumps({'case': work.name, 'requests': dict(requests), 'version': values[0]}), flush=True)
    for endpoint in ANSWERS:
        if loop and endpoint == RELEASE:
            assert requests[endpoint] == 4 and not requests['/moved' + endpoint], requests
        else:
            assert requests[endpoint] == requests['/moved' + endpoint] == 1, requests
    expected = {'release': 'v91.2.3', 'sha': SHA, 'qs': 'v8.7.6', 'contributor': 'redirect-fixture'}
    if loop:
        assert values[0]['release'] != expected['release'], values
        del values[0]['release'], expected['release']
    assert values[0] == expected, values


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    require_disk_backed_paths(source, output, os.environ['TMPDIR'])
    if output.is_relative_to(source):
        parser.error('output must be outside the source tree')
    output.mkdir()
    run(source, output / 'redirect', False)
    run(source, output / 'loop', True)
