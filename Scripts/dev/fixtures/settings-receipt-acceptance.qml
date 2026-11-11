import QtQuick
import Quickshell
import qs.Widgets

// Pure component callback contract; no fabricated native-store result.
ShellRoot {
  id: root
  property int index: 0
  property string phase: "begin"
  property int bufferedAccepted: 0
  property int liveClosed: 0
  property bool liveCompleted: false
  readonly property var cases: [
    {receipt: {status: "saved", refreshState: ""}, accepted: true},
    {receipt: {status: "nothing_to_save", refreshState: ""}, accepted: true},
    {receipt: {status: "saved"}, accepted: true},
    {receipt: {status: "saved", refreshState: "current"}, accepted: true},
    {receipt: {status: "nothing_to_save", refreshState: "current"}, accepted: true},
    {receipt: {status: "saved", refreshState: "stale"}, accepted: false},
    {receipt: {status: "saved", refreshState: "not_refreshed"}, accepted: false},
    {receipt: {status: "failed", refreshState: ""}, accepted: false},
    {receipt: {status: "admitted", refreshState: "current"}, accepted: false},
    {receipt: {status: "saved", refreshState: null}, accepted: false}
  ]
  property var collaborator: ({
    apply: function (value, callback) { var receipt = root.cases[root.index].receipt; Qt.callLater(function () { callback(receipt); }); },
    submit: function (value, callback) { var receipt = root.cases[root.index].receipt; Qt.callLater(function () { callback(receipt); }); },
    discard: function () { return true; }
  })
  NSettingsEditSession { id: buffered; onAccepted: root.bufferedAccepted++ }
  NLiveSettingsEditSession {
    id: live
    editor: root.collaborator
    onCompleted: root.liveCompleted = true
    onCloseRequested: root.liveClosed++
  }
  function check(ok, label) { if (!ok) throw new Error("I5_RECEIPT_ACCEPTANCE_ASSERT: " + index + " " + label); }
  function drive() {
    if (phase === "begin") {
      if (index === cases.length) { console.log("I5_RECEIPT_ACCEPTANCE: PASS"); Qt.exit(0); return; }
      bufferedAccepted = 0; liveClosed = 0; liveCompleted = false;
      buffered.begin(collaborator, {label: "before"});
      buffered.value = {label: "after"};
      buffered.apply();
      check(buffered.busy, "buffered completion asynchronous");
      live.queue({label: "after"}); live.saveAndClose();
      check(live.busy, "live completion asynchronous");
      phase = "complete";
    } else if (phase === "complete" && !buffered.busy && !live.busy && liveCompleted) {
      var accepted = cases[index].accepted;
      check(bufferedAccepted === (accepted ? 1 : 0) && buffered.failed === !accepted, "buffered receipt classification");
      check(liveClosed === (accepted ? 1 : 0) && live.failed === !accepted, "live receipt classification and close");
      check(live.dirty === !accepted && buffered.dirty === !accepted, "failed/stale input retained, acknowledged input clean");
      live.confirmDiscard();
      index++; phase = "begin";
    }
  }
  Timer {
    interval: 10; repeat: true; running: true
    onTriggered: { try { root.drive(); } catch (error) { console.error(String(error)); Qt.exit(2); } }
  }
  Timer { interval: 10000; running: true; onTriggered: { console.error("I5_RECEIPT_ACCEPTANCE_ASSERT: watchdog", root.index); Qt.exit(2); } }
}
