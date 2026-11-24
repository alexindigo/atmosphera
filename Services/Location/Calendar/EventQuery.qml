import QtQuick
import Quickshell.Io

Process {
  id: root
  required property var parseEvents
  property var _complete: null

  function start(args, complete) {
    command = args;
    _complete = complete;
    running = true;
    checkForStartFailure(complete);
  }

  function finish(result, error) {
    const complete = _complete;
    _complete = null;
    if (complete)
      complete(result, error);
  }

  // FailedToStart may only emit runningChanged, not exited.
  function checkForStartFailure(complete) {
    Qt.callLater(function () {
      if (complete && root._complete === complete && !root.running)
        root.finish([], "Calendar provider did not start");
    });
  }

  stdout: StdioCollector {
    id: output
  }
  stderr: StdioCollector {
    id: errors
  }
  onRunningChanged: if (!running && _complete)
                      checkForStartFailure(_complete)
  onExited: (code, status) => {
    const error = errors.text.trim();
    if (code !== 0 || status !== 0 || error) {
      finish([], error || `Calendar provider exited (${code}, ${status})`);
      return;
    }
    let events;
    try {
      events = parseEvents(output.text.trim());
      if (!Array.isArray(events))
        throw new Error("Expected an event list");
    } catch (e) {
      finish([], "Failed to parse calendar events: " + e);
      return;
    }
    finish(events, "");
  }
}
