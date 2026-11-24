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
import time

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
                with self.server.lock:
                    self.server.streams += 1
                    first = self.server.streams == 1
                if not first and self.server.scenario in ('overview', 'spawn'):
                    # Keep the replacement stream unready while request sockets work.
                    self.server.spawned.wait(3)
                self.send({'Ok': 'Handled'})
                self.send({'WorkspacesChanged': {'workspaces': [workspace(LO, 1), workspace(0, 2)]}})
                self.send({'WindowsChanged': {'windows': [window(HI), window(0)]}})
                self.send({'OverviewOpenedOrClosed': {'is_open': False}})
                self.send({'ConfigLoaded': {'failed': False}})
                self.send({'CastsChanged': {'casts': []}})
                if first and self.server.scenario in ('overview', 'spawn', 'edge'):
                    if not self.server.retire.wait(8):
                        return
                    if self.server.scenario == 'overview':
                        for opened in (True, False, True):
                            self.send({'OverviewOpenedOrClosed': {'is_open': opened}})
                            time.sleep(.15)
                    return
                continue
            if request == 'Version':
                self.send({'Ok': {'Version': '26.04.0'}})
                continue
            if request == 'Outputs':
                self.send({'Ok': {'Outputs': {}}})
                continue
            if request == 'Workspaces':
                if not self.server.retire.is_set():
                    self.server.retire.set()
                    if self.server.scenario == 'edge':
                        # Release only after the client observes the new ready generation.
                        if not self.server.release.wait(8):
                            return
                self.send({'Ok': {'Workspaces': [workspace(LO, 1), workspace(0, 2)]}})
                continue
            if request == 'Windows':
                self.server.release.set()
                with self.server.lock:
                    moves = sum('MoveWindowToWorkspace' in row for row in self.server.actions)
                rows = [window(0)]
                if self.server.scenario != 'actions' or moves != 2:
                    rows.append(dict(window(HI), workspace_id=0 if moves >= 3 else LO))
                self.send({'Ok': {'Windows': rows}})
                continue
            action = request.get('Action') if isinstance(request, dict) else None
            if action:
                with self.server.lock:
                    prior_moves = sum('MoveWindowToWorkspace' in row for row in self.server.actions)
                    self.server.actions.append(action)
                if 'MoveWindowToWorkspace' in action and not prior_moves:
                    self.send({'Err': 'fixture rejection'})
                    continue
                if 'Spawn' in action:
                    self.server.spawned.set()
            self.send({'Ok': 'Handled'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scenario', choices=('actions', 'overview', 'spawn', 'edge'), default='actions')
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    require_disk_backed_paths(source, output, os.environ.get('TMPDIR', ''))
    output.mkdir()
    template = Path(__file__).parent / 'fixtures/niri-action-wire.qml.in'
    with tempfile.TemporaryDirectory(prefix='wire-') as temp, tempfile.NamedTemporaryFile(
            mode='w', suffix='.qml', prefix='WireFixture-', dir=source) as entry:
        entry.write(template.read_text().replace('@SCENARIO@', args.scenario))
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
            peer.scenario = args.scenario
            peer.streams = 0
            peer.retire, peer.release, peer.spawned = (threading.Event() for _ in range(3))
            worker = threading.Thread(target=peer.serve_forever)
            worker.start()
            try:
                with (output / 'shell.log').open('x') as log:
                    process = subprocess.run(['timeout', '--kill-after=3', '15', 'qs', '-p', entry.name, '--no-color'],
                                             env=env, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=20)
            finally:
                peer.retire.set()
                peer.release.set()
                peer.spawned.set()
                peer.shutdown()
                worker.join()
            actual = peer.actions
    expected_move = {'MoveWindowToWorkspace': {'window_id': HI, 'reference': {'Id': 0}, 'focus': False}}
    single = [{'FocusWindow': {'id': HI}}, {'CloseWindow': {'id': 0}},
              {'FocusWorkspace': {'reference': {'Id': 0}}}]
    ordered = [row for row in actual if 'MoveWindowToWorkspace' in row or 'MoveWorkspaceToIndex' in row]
    unordered = [row for row in actual if row not in ordered]
    expected_order = [expected_move] * 3 + [{'MoveWorkspaceToIndex': {'index': 1, 'reference': {'Id': 0}}}]
    marker = 'NIRI_ACTION_WIRE_RESULT|true|' in (output / 'shell.log').read_text()
    if args.scenario == 'actions':
        wire_matches = ordered == expected_order and len(unordered) == len(single) and all(row in unordered for row in single)
    else:
        wire_matches = actual == ([{'Spawn': {'command': ['fixture-spawn']}}] if args.scenario == 'spawn' else [])
    passed = marker and process.returncode == 0 and wire_matches
    result = dict(passed=passed, exit_code=process.returncode, actions=actual)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
