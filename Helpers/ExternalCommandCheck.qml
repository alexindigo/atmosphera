import QtQuick
import Quickshell
import Quickshell.Io

// Availability only: neither the command nor its arguments are ever executed.
Scope {
  id: root
  property string commandText: ""
  property bool enabled: true
  property var checkerCommand: ["python3", Quickshell.shellPath("Scripts/python/check-external-command.py")]
  readonly property string state: _state
  property string _state: "empty"
  property int _revision: 0
  property bool _active: false

  function refresh() {
    _revision++;
    _state = commandText.trim() === "" ? "empty" : "pending";
    debounce.restart();
  }

  function _start() {
    if (!enabled || _active || checker.running || _state !== "pending" || debounce.running)
      return;
    checker.revision = _revision;
    checker.command = checkerCommand.concat([commandText]);
    _active = true;
    deadline.restart();
    checker.running = true;
  }

  function _finish(result) {
    if (!_active)
      return;
    _active = false;
    deadline.stop();
    if (checker.revision === _revision)
      _state = result;
    Qt.callLater(_start);
  }

  onCommandTextChanged: refresh()
  onEnabledChanged: if (enabled)
                      refresh()
  Component.onCompleted: refresh()

  Timer {
    id: debounce
    interval: 400
    onTriggered: root._start()
  }
  Timer {
    id: deadline
    interval: 3000
    onTriggered: {
      // Only the owned, non-executing checker, never the configured command.
      checker.signal(9);
      root._finish("error");
    }
  }
  Process {
    id: checker
    property int revision: -1
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode, exitStatus) {
      const result = stdout.text.trim();
      root._finish(exitCode === 0 && exitStatus === 0 && ["available", "missing", "unverified", "empty"].indexOf(result) >= 0 ? result : "error");
    }
    // Quickshell 0.3.2 emits no exited signal for FailedToStart.
    onRunningChanged: if (!running) {
                        root._finish("error");
                        Qt.callLater(root._start);
                      }
  }
}
