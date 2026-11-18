#!/usr/bin/env python3
"""Exercise the real niri backend with explicitly ordered event/query replies.

Run inside the project VM. The private QML module replaces only niri's transport;
the backend under test is copied unchanged from --source. No live shell starts.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from workspace_guard import require_disk_backed_paths


EVENTS = """pragma Singleton
import QtQml
QtObject {
  signal windowsChanged(var windows)
  signal workspacesChanged(var workspaces)
  signal windowOpenedOrChanged(var window)
  signal windowClosed(int id)
  signal windowLayoutsChanged(var changes)
  signal windowFocusChanged(int id)
  signal workspaceActiveWindowChanged(int workspaceId, int windowId)
  signal workspaceActivated(int workspaceId, bool focused)
  signal keyboardLayoutsChanged(var layouts)
  signal keyboardLayoutSwitched(int idx)
  signal overviewOpenedOrClosed(bool isOpen)
}
"""
REQUESTS = """pragma Singleton
import QtQml
QtObject {
  property var pending: []
  property var counts: ({})
  function request(domain) {
    const reply = Qt.createQmlObject('import QtQml; QtObject { property bool isError: false; property var value; property var error: ({message: "scripted failure"}); signal finished() }', this);
    pending.push({domain: domain, reply: reply});
    counts[domain] = (counts[domain] || 0) + 1;
    return reply;
  }
  function windows() { return request("windows"); }
  function workspaces() { return request("workspaces"); }
  function keyboardLayouts() { return request("keyboardLayouts"); }
  function outputs() { return request("outputs"); }
  function deliver(domain, value, failed) {
    const index = pending.findIndex(p => p.domain === domain);
    if (index < 0) throw new Error("No pending " + domain);
    const reply = pending.splice(index, 1)[0].reply;
    reply.value = value;
    reply.isError = !!failed;
    reply.finished();
  }
  function reset() { pending = []; counts = ({}); }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    require_disk_backed_paths(output.parent, os.environ.get('TMPDIR', ''))
    output.mkdir()
    tree = output / 'tree'

    def write(name, content):
        path = tree / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    backend = tree / 'Services/Compositor/NiriIpcBackend.qml'
    backend.parent.mkdir(parents=True)
    shutil.copy2(source / 'Services/Compositor/NiriIpcBackend.qml', backend)
    helpers = re.findall(r'import "../../Helpers/([^"/]+\.js)"', backend.read_text())
    for name in helpers:
        (tree / 'Helpers').mkdir(exist_ok=True)
        shutil.copy2(source / 'Helpers' / name, tree / 'Helpers' / name)
    write('Commons/Logger.qml', 'pragma Singleton\nimport QtQml\nQtObject { function d() {} function w() {} function e() {} }\n')
    write('Commons/qmldir', 'singleton Logger 1.0 Logger.qml\n')
    write('Services/Keyboard/KeyboardLayoutService.qml', 'pragma Singleton\nimport QtQml\nQtObject { function setCurrentLayout(current, fallback) {} }\n')
    write('Services/Keyboard/qmldir', 'singleton KeyboardLayoutService 1.0 KeyboardLayoutService.qml\n')
    write('Services/Compositor/CompositorService.qml', 'pragma Singleton\nimport QtQml\nQtObject { property int forwardCount: 0; property var forwardedOutputs: ({}); function onDisplayScalesUpdated(outputs) { forwardedOutputs=outputs; forwardCount++; } }\n')
    write('Services/Compositor/qmldir', 'NiriIpcBackend 1.0 NiriIpcBackend.qml\nsingleton CompositorService 1.0 CompositorService.qml\n')
    write('Niri/NiriEvents.qml', EVENTS)
    write('Niri/NiriRequests.qml', REQUESTS)
    write('Niri/NiriConnection.qml', 'pragma Singleton\nimport QtQml\nQtObject { property bool isConnected: true; signal connectedChanged(); onIsConnectedChanged: connectedChanged() }\n')
    write('Niri/qmldir', '\n'.join(['module Niri'] + [f'singleton {name} 1.0 {name}.qml' for name in ['NiriEvents', 'NiriRequests', 'NiriConnection']]) + '\n')
    write('shell.qml', (Path(__file__).parent / 'fixtures/niri-bootstrap.qml.in').read_text())
    env = dict(os.environ, QML_IMPORT_PATH=str(tree), QML2_IMPORT_PATH=str(tree))
    with (output / 'shell.log').open('x') as log:
        result = subprocess.run(['timeout', '--kill-after=3', '35', 'qs', '-p', str(tree), '--no-color'],
                                env=env, cwd=tree, stdout=log, stderr=subprocess.STDOUT, timeout=40)
    lines = [line.split('BOOTSTRAP_RESULT|', 1)[1] for line in (output / 'shell.log').read_text().splitlines() if 'BOOTSTRAP_RESULT|' in line]
    cases = json.loads(lines[-1]) if lines else []
    passed = result.returncode == 0 and len(cases) == 15 and all(c['passed'] for c in cases)
    for case in cases:
        print(case['name'], 'PASS' if case['passed'] else 'FAIL', case.get('error', ''))
    (output / 'result.json').write_text(json.dumps(dict(passed=passed, exit_code=result.returncode, cases=cases), indent=2) + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
