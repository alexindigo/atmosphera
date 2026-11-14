import QtQuick
import "../Helpers/RecordListEditor.js" as RecordListEditor

// Immediate/debounced field edits, not an Apply/Cancel draft. The injected
// editor submits owned fields and completes with an actual persistence receipt.
QtObject {
  id: root
  property var editor: null
  property var pending: null
  property bool busy: false
  property bool failed: false
  property bool closePending: false
  property int _sequence: 0
  readonly property bool dirty: pending !== null
  signal completed(var result)
  signal closeRequested
  property Timer _timer: Timer {
    interval: 150
    onTriggered: root.flush()
  }

  function queue(fields) {
    if (!fields || typeof fields !== "object" || Array.isArray(fields))
      return false;
    var owned;
    try {
      owned = RecordListEditor.copy(root.pending || {});
      var input = RecordListEditor.copy(fields);
      Object.keys(input).forEach(function (key) {
        owned[key] = input[key];
      });
    } catch (error) {
      root.failed = true;
      return false;
    }
    pending = owned;
    _sequence++;
    _timer.restart();
    return true;
  }

  function saveAndClose() {
    closePending = true;
    _timer.stop();
    flush();
  }

  function flush() {
    if (busy)
      return;
    if (pending === null) {
      if (closePending) {
        closePending = false;
        closeRequested();
      }
      return;
    }
    var submitted = RecordListEditor.copy(pending);
    var sequence = _sequence;
    var delivered = false;
    busy = true;
    failed = false;
    function complete(result) {
      if (delivered)
        return;
      delivered = true;
      root.busy = false;
      if (!result || (result.status !== "saved" && result.status !== "nothing_to_save") || (result.refreshState !== undefined && result.refreshState !== "current")) {
        root.failed = true;
        root.closePending = false;
        root._timer.stop();
        root.completed(result);
        return;
      }
      if (sequence === root._sequence)
        root.pending = null;
      root.completed(result);
      if (root.pending !== null) {
        if (root.closePending)
          root.flush();
        else
          root._timer.restart();
      } else if (root.closePending) {
        root.closePending = false;
        root.closeRequested();
      }
    }
    try {
      if (!editor || typeof editor.submit !== "function")
        throw new Error("editor-detached");
      editor.submit(submitted, complete);
    } catch (error) {
      // No guessed success on synchronous ingress failure. Retain local work.
      Qt.callLater(function () {
        complete({
                   status: "failed",
                   error: {
                     code: "editor-input"
                   }
                 });
      });
    }
  }

  // Called only after the consumer's explicit confirmation. Admitted live
  // settings are never rolled back; discard detaches the remaining local input.
  function confirmDiscard() {
    if (busy)
      return false;
    _timer.stop();
    pending = null;
    failed = false;
    closePending = false;
    if (editor && typeof editor.detach === "function")
      editor.detach();
    closeRequested();
    return true;
  }
}
