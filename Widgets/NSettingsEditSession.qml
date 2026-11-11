import QtQuick
import "../Helpers/SettingsValues.js" as SettingsValues
import "../Helpers/SettingsReceipts.js" as SettingsReceipts

QtObject {
  id: root

  // editor.apply(value, callback), editor.discard(). No consumer/Settings import.
  property var editor: null
  property var value: null
  property var inputGuard: null
  property var _initialValue: null
  property bool busy: false
  property bool failed: false
  property bool discardPending: false
  readonly property bool dirty: failed || (inputGuard && inputGuard.dirty) || !SettingsValues.equal(value, _initialValue)
  signal accepted(var value)
  signal closeRequested

  function begin(handle, initialValue) {
    if (busy)
      return false;
    if (editor)
      editor.discard();
    editor = handle;
    _initialValue = initialValue;
    if (inputGuard)
      inputGuard.reset();
    failed = false;
    discardPending = false;
    return true;
  }

  function apply() {
    if (busy || !editor)
      return;
    if (inputGuard)
      inputGuard.commit();
    // Own the submission across queued completion and later caller mutations.
    var submitted = JSON.parse(JSON.stringify(value));
    var inputFence = inputGuard ? inputGuard.capture() : 0;
    busy = true;
    failed = false;
    try {
      editor.apply(submitted, function (result) {
        root.busy = false;
        if (!SettingsReceipts.acknowledged(result)) {
          root.failed = true;
          return;
        }
        root._initialValue = submitted;
        if (root.inputGuard)
          root.inputGuard.acknowledge(inputFence);
        root.accepted(submitted);
      });
    } catch (error) {
      // Checked ingress can reject synchronously, before there is a receipt.
      busy = false;
      failed = true;
    }
  }

  function requestClose() {
    if (busy)
      return;
    if (inputGuard)
      inputGuard.commit();
    if (dirty) {
      discardPending = true;
    } else {
      confirmDiscard();
    }
  }

  function confirmDiscard() {
    if (busy || (editor && editor.discard() === false))
      return;
    discardPending = false;
    closeRequested();
  }
}
