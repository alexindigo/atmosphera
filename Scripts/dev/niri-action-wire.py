#!/usr/bin/env python3
"""Assert exact action bytes from the installed niriqml, using a private IPC peer."""
import argparse
import json
import os
from pathlib import Path
import socketserver
import subprocess
import tempfile
import threading

from workspace_guard import require_disk_backed_paths


HI = 9007199254740993
LO = 9007199254740992


def window(id):
    return dict(id=id, workspace_id=LO, title=str(id), app_id='fixture', is_focused=id == HI,
                is_floating=False, is_urgent=False, layout=dict(tile_size=[800, 600],
                                                              window_size=[800, 600], window_offset_in_tile=[0, 0]))


def workspace(id, idx):
    return dict(id=id, idx=idx, name=None, output='Virtual-1', is_active=idx == 1,
                is_focused=idx == 1, is_urgent=False, active_window_id=HI if idx == 1 else None)


class Peer(socketserver.StreamRequestHandler):
    def send(self, payload):
        self.wfile.write(json.dumps(payload).encode() + b'\n')

    def handle(self):
        for line in self.rfile:
            request = json.loads(line)
            if request == 'EventStream':
                self.send({'Ok': 'Handled'})
                self.send({'WorkspacesChanged': {'workspaces': [workspace(LO, 1), workspace(0, 2)]}})
                self.send({'WindowsChanged': {'windows': [window(HI), window(0)]}})
                self.send({'OverviewOpenedOrClosed': {'is_open': False}})
                self.send({'ConfigLoaded': {'failed': False}})
                self.send({'CastsChanged': {'casts': []}})
                continue
            if request == 'Version':
                self.send({'Ok': {'Version': '26.04.0'}})
                continue
            if request == 'Outputs':
                self.send({'Ok': {'Outputs': {}}})
                continue
            action = request.get('Action') if isinstance(request, dict) else None
            if action:
                with self.server.lock:
                    prior_moves = sum('MoveWindowToWorkspace' in row for row in self.server.actions)
                    self.server.actions.append(action)
                if 'MoveWindowToWorkspace' in action and not prior_moves:
                    self.send({'Err': 'fixture rejection'})
                    continue
            self.send({'Ok': 'Handled'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    require_disk_backed_paths(source, output, os.environ.get('TMPDIR', ''))
    output.mkdir()
    template = Path(__file__).parent / 'fixtures/niri-action-wire.qml.in'
    with tempfile.TemporaryDirectory(prefix='wire-') as temp, tempfile.NamedTemporaryFile(
            mode='w', suffix='.qml', prefix='WireFixture-', dir=source) as entry:
        entry.write(template.read_text())
        entry.flush()
        path = str(Path(temp) / 'socket')
        env = dict(os.environ, NIRI_SOCKET=path, QT_QPA_PLATFORM='wayland', ATMOSPHERA_LOCKSCREEN='1')
        for key in ('CONFIG', 'DATA', 'CACHE', 'STATE'):
            directory = output / key.lower()
            directory.mkdir()
            env[f'XDG_{key}_HOME'] = str(directory)
        with socketserver.ThreadingUnixStreamServer(path, Peer) as peer:
            peer.lock = threading.Lock()
            peer.actions = []
            worker = threading.Thread(target=peer.serve_forever)
            worker.start()
            try:
                with (output / 'shell.log').open('x') as log:
                    process = subprocess.run(['timeout', '--kill-after=3', '15', 'qs', '-p', entry.name, '--no-color'],
                                             env=env, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=20)
            finally:
                peer.shutdown()
                worker.join()
            actual = peer.actions
    expected_move = {'MoveWindowToWorkspace': {'window_id': HI, 'reference': {'Id': 0}, 'focus': False}}
    single = [{'FocusWindow': {'id': HI}}, {'CloseWindow': {'id': 0}},
              {'FocusWorkspace': {'reference': {'Id': 0}}}]
    ordered = [row for row in actual if 'MoveWindowToWorkspace' in row or 'MoveWorkspaceToIndex' in row]
    unordered = [row for row in actual if row not in ordered]
    expected_order = [expected_move, expected_move, {'MoveWorkspaceToIndex': {'index': 1, 'reference': {'Id': 0}}}]
    marker = 'NIRI_ACTION_WIRE_RESULT|true|' in (output / 'shell.log').read_text()
    passed = marker and process.returncode == 0 and ordered == expected_order and len(unordered) == len(single) and all(row in unordered for row in single)
    result = dict(passed=passed, exit_code=process.returncode, actions=actual)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
