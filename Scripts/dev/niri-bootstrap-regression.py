#!/usr/bin/env python3
"""Exercise the real niri backend with scripted canonical state and replies.

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
import tempfile

from workspace_guard import require_disk_backed_paths


EVENTS = """pragma Singleton
import QtQml
QtObject {
  signal configLoaded(bool failed)
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
STATE = """pragma Singleton
import QtQml
QtObject {
  property bool initialStateReceived: false
  property var _windows: []
  property var _workspaces: []
  property var focusedWindowId: null
  property var focusedWorkspaceId: null
  property var keyboardLayouts: null
  property bool overviewOpen: false
  signal stateChanged()
  function windowsSnapshot() { return _windows; }
  function workspacesSnapshot() { return _workspaces; }
  function publish(ready, windows, workspaces, windowId, workspaceId, keyboard, overview) {
    _windows = windows;
    _workspaces = workspaces;
    focusedWindowId = windowId;
    focusedWorkspaceId = workspaceId;
    keyboardLayouts = keyboard;
    overviewOpen = overview;
    initialStateReceived = ready;
    stateChanged();
  }
}
"""
REQUESTS = """pragma Singleton
import QtQml
QtObject {
  id: root
  // Use a stable QML type across cases instead of compiling one per request.
  property Component replyComponent: Component {
    id: replyType
    QtObject {
      property bool completed: false
      property bool isError: false
      property var value
      property var error: ({message: "scripted failure"})
      signal finished()
      function cancel() { if (!completed) { completed = true; isError = true; finished(); } }
    }
  }
  property var pending: []
  property var counts: ({})
  function request(domain) {
    const reply = replyType.createObject(root);
    pending.push({domain: domain, reply: reply});
    counts[domain] = (counts[domain] || 0) + 1;
    return reply;
  }
  function windows() { return request("windows"); }
  function workspaces() { return request("workspaces"); }
  function keyboardLayouts() { return request("keyboardLayouts"); }
  function outputs() { return request("outputs"); }
  function deliver(domain, value, failed, last) {
    const index = last ? pending.map(p => p.domain).lastIndexOf(domain) : pending.findIndex(p => p.domain === domain);
    if (index < 0) throw new Error("No pending " + domain);
    const reply = pending.splice(index, 1)[0].reply;
    if (reply.completed) return;
    reply.value = value;
    reply.isError = !!failed;
    reply.completed = true;
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
    write('Commons/Logger.qml', 'pragma Singleton\nimport QtQml\nQtObject { function d() {} function i() {} function w() {} function e() {} }\n')
    write('Commons/qmldir', 'singleton Logger 1.0 Logger.qml\n')
    write('Services/Keyboard/KeyboardLayoutService.qml', 'pragma Singleton\nimport QtQml\nQtObject { function setCurrentLayout(current, fallback) {} }\n')
    write('Services/Keyboard/qmldir', 'singleton KeyboardLayoutService 1.0 KeyboardLayoutService.qml\n')
    write('Services/Compositor/CompositorService.qml', 'pragma Singleton\nimport QtQml\nQtObject { property int forwardCount: 0; property var forwardedOutputs: ({}); function onDisplayScalesUpdated(outputs) { forwardedOutputs=outputs; forwardCount++; } }\n')
    session = tree / 'Services/Compositor/NiriSessionIpc.qml'
    shutil.copy2(source / 'Services/Compositor/NiriSessionIpc.qml', session)
    write('Services/Compositor/qmldir', 'NiriIpcBackend 1.0 NiriIpcBackend.qml\nNiriSessionIpc 1.0 NiriSessionIpc.qml\nsingleton CompositorService 1.0 CompositorService.qml\n')
    write('Niri/NiriEvents.qml', EVENTS)
    write('Niri/NiriState.qml', STATE)
    write('Niri/NiriRequests.qml', REQUESTS)
    write('Niri/NiriConnection.qml', 'pragma Singleton\nimport QtQml\nQtObject { property bool isConnected: true; property var peerInfo: null; signal connectedChanged(); onIsConnectedChanged: connectedChanged() }\n')
    write('Niri/NiriActions.qml', '''pragma Singleton
import QtQml
QtObject {
  property var calls: []
  function action(name, args) { calls.push([name, ...args]); return NiriRequests.request(name); }
  function sendAction(action) { return actionReply(action); }
  function actionReply(payload) { return action(Object.keys(payload)[0], [payload]); }
  function focusWindow(id) { return action("focusWindow", [id]); }
  function closeWindow(id) { return action("closeWindow", [id]); }
  function focusWorkspace(ref) { return action("focusWorkspace", [ref]); }
  function moveWindowToWorkspace(id, ref, focus) { return action("moveWindowToWorkspace", [id, ref, focus]); }
  function moveWorkspaceToIndex(idx, ref) { return action("moveWorkspaceToIndex", [idx, ref]); }
}
''')
    write('Niri/qmldir', '\n'.join(['module Niri'] + [f'singleton {name} 1.0 {name}.qml' for name in ['NiriEvents', 'NiriState', 'NiriRequests', 'NiriConnection', 'NiriActions']]) + '\n')
    write('shell.qml', (Path(__file__).parent / 'fixtures/niri-canonical-state.qml.in').read_text())
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QML_IMPORT_PATH=str(tree), QML2_IMPORT_PATH=str(tree))
    with (output / 'shell.log').open('x') as log:
        result = subprocess.run(['timeout', '--kill-after=3', '35', 'qs', '-p', str(tree), '--no-color'],
                                env=env, cwd=tree, stdout=log, stderr=subprocess.STDOUT, timeout=40)
    lines = [line.split('BOOTSTRAP_RESULT|', 1)[1] for line in (output / 'shell.log').read_text().splitlines() if 'BOOTSTRAP_RESULT|' in line]
    cases = json.loads(lines[-1]) if lines else []
    widget_case = workspace_widget(source, output)
    passed = (result.returncode == 0 and len(cases) == 13
              and all(c['passed'] for c in cases) and widget_case['passed'])
    cases.append(widget_case)
    for case in cases:
        print(case['name'], 'PASS' if case['passed'] else 'FAIL', case.get('error', ''))
    (output / 'result.json').write_text(json.dumps(dict(passed=passed, exit_code=result.returncode, cases=cases), indent=2) + '\n')
    return 0 if passed else 1


def workspace_widget(source, output):
    # The widget depends on the real shell's relative imports, not the mock
    # backend tree. Give this QS process its own XDG profile nevertheless.
    profile = {}
    for key in ('CONFIG', 'DATA', 'CACHE', 'STATE'):
        directory = output / 'widget-profile' / key.lower()
        directory.mkdir(parents=True)
        profile[f'XDG_{key}_HOME'] = str(directory)
    env = dict(os.environ, **profile)
    env.pop('NIRI_SOCKET', None)
    env['QT_QPA_PLATFORM'] = 'wayland'
    template = Path(__file__).parent / 'fixtures/niri-workspace-widget.qml.in'
    log_path = output / 'workspace-widget.log'
    with tempfile.NamedTemporaryFile(mode='w', suffix='.qml', prefix='WidgetFixture-', dir=source) as entry:
        entry.write(template.read_text())
        entry.flush()
        with log_path.open('x') as log:
            result = subprocess.run(['timeout', '--kill-after=3', '15', 'qs', '-p', entry.name, '--no-color'],
                                    env=env, cwd=source, stdout=log, stderr=subprocess.STDOUT, timeout=20)
    lines = [line.split('WORKSPACE_WIDGET_RESULT|', 1)[1] for line in log_path.read_text().splitlines()
             if 'WORKSPACE_WIDGET_RESULT|' in line]
    detail = json.loads(lines[-1]) if lines else {'exit_code': result.returncode}
    passed = result.returncode == 0 and detail.get('passed', False)
    return dict(name='workspace widget preserves both wide IDs, zero and null', passed=passed,
                error='' if passed else repr(detail))


if __name__ == '__main__':
    raise SystemExit(main())
