// Passive Settings consumer probe for Scripts/dev/settings-regression.py.
//
// Run by the regression runner as the qs entry point inside a disposable
// copy of the shell tree:
//   qs -p <case>/shell/settings-regression-probe.qml
// `qs.Commons` resolves via config-root mapping, so this probe exercises the
// ACTUAL Settings singleton of the tree under test — no duplicated adapter,
// no JS-only mock.
//
// Protocol (stdout, one JSON object per line):
//   PROBE|START|<json>    — probe started
//   PROBE|READY|<json>    — settings readiness observed; values = PROBE_VALUES
//   PROBE|RELOADED|<json> — settingsReloaded observed (external-edit cases)
//   PROBE|SAVED|<json>    — settingsSaved observed (save/reset cases)
//   PROBE|DONE|<json>     — final values, probe exits 0
//   PROBE|FAIL|<json>     — watchdog/stage failure, probe exits 2
//
// Modes (PROBE_CASE):
//   observe | verify   — wait ready, report values, exit
//   external-edit      — wait ready, report, wait for settingsReloaded, report, exit
//   save               — wait ready, apply PROBE_EDIT_*, wait settingsSaved, exit
//   pending-edit-save  — apply PROBE_EDIT_* first, THEN announce READY (the
//                        runner's external write races the save debounce),
//                        wait settingsSaved, exit
//   reset              — wait ready, call Settings.resetSection(PROBE_RESET_SECTION),
//                        wait settingsSaved, grace period, report, exit
//
// Env:
//   PROBE_CASE           — mode above
//   PROBE_VALUES         — comma-separated dotted paths under Settings.data to report
//   PROBE_EDIT_PATH      — dotted path to assign (save modes)
//   PROBE_EDIT_VALUE     — JSON-encoded value to assign
//   PROBE_RESET_SECTION  — section name for reset mode

import QtQuick
import Quickshell
import qs.Commons

Item {
  id: probe

  readonly property string probeCase: Quickshell.env("PROBE_CASE") || "observe"
  readonly property string valuePaths: Quickshell.env("PROBE_VALUES") || ""
  readonly property string editPath: Quickshell.env("PROBE_EDIT_PATH") || ""
  readonly property string editValueRaw: Quickshell.env("PROBE_EDIT_VALUE") || ""
  readonly property string resetSectionName: Quickshell.env("PROBE_RESET_SECTION") || ""

  property bool _ready: false
  property string _stage: "init"

  // ---- value helpers ----

  function toPlain(v) {
    if (v === null || v === undefined)
      return v;
    if (typeof v !== "object")
      return v;
    if (Array.isArray(v))
      return v.map(toPlain);
    // QML lists (list<string>, list<var>) are length-indexed, not Array
    if (typeof v.length === "number") {
      var a = [];
      for (var i = 0; i < v.length; i++)
        a.push(toPlain(v[i]));
      return a;
    }
    var o = {};
    for (var k in v) {
      if (Object.prototype.hasOwnProperty.call(v, k))
        o[k] = toPlain(v[k]);
    }
    return o;
  }

  function getPath(path) {
    var parts = path.split(".");
    var cur = Settings.data;
    for (var i = 0; i < parts.length; i++) {
      if (cur === undefined || cur === null)
        return undefined;
      cur = cur[parts[i]];
    }
    return toPlain(cur);
  }

  function collectValues() {
    var out = {};
    if (valuePaths !== "") {
      var paths = valuePaths.split(",");
      for (var i = 0; i < paths.length; i++)
        out[paths[i]] = getPath(paths[i]);
    }
    return out;
  }

  function emit(tag, obj) {
    console.log("PROBE|" + tag + "|" + JSON.stringify(obj));
  }

  function done() {
    emit("DONE", collectValues());
    Qt.exit(0);
  }

  function fail(reason) {
    emit("FAIL", {
           "reason": reason,
           "stage": _stage
         });
    Qt.exit(2);
  }

  // ---- edit command ----

  function applyEdit() {
    var parts = editPath.split(".");
    var obj = Settings.data;
    for (var i = 0; i < parts.length - 1; i++)
      obj = obj[parts[i]];
    obj[parts[parts.length - 1]] = JSON.parse(editValueRaw);
  }

  // ---- stage wiring ----

  Connections {
    target: Settings
    function onSettingsLoaded() {
      probe.onReady();
    }
    function onSettingsReloaded() {
      if (probe._stage === "wait-reload")
        probe.onReloaded();
    }
    function onSettingsSaved() {
      if (probe._stage === "wait-save")
        probe.onSaved();
    }
  }

  Timer {
    id: readyWatchdog
    interval: 30000
    running: true
    onTriggered: probe.fail("readiness-timeout")
  }

  Timer {
    id: stageWatchdog
    interval: 15000
    running: false
    onTriggered: probe.fail("stage-timeout")
  }

  // reset mode: file deletion is execDetached (async) — give it time to land
  Timer {
    id: graceTimer
    interval: 1000
    running: false
    onTriggered: probe.done()
  }

  Component.onCompleted: {
    emit("START", {
           "case": probeCase
         });
    if (Settings.isLoaded)
      onReady();
  }

  function onReady() {
    if (_ready)
      return;
    _ready = true;
    readyWatchdog.stop();

    if (probeCase === "observe" || probeCase === "verify") {
      emit("READY", collectValues());
      done();
    } else if (probeCase === "external-edit") {
      emit("READY", collectValues());
      _stage = "wait-reload";
      stageWatchdog.start();
    } else if (probeCase === "save") {
      emit("READY", collectValues());
      applyEdit();
      _stage = "wait-save";
      stageWatchdog.start();
    } else if (probeCase === "pending-edit-save") {
      // Edit first so the runner's external write lands while the save is pending
      applyEdit();
      emit("READY", collectValues());
      _stage = "wait-save";
      stageWatchdog.start();
    } else if (probeCase === "reset") {
      emit("READY", collectValues());
      _stage = "wait-save";
      stageWatchdog.start();
      Settings.resetSection(resetSectionName);
    } else {
      fail("unknown-case");
    }
  }

  function onReloaded() {
    stageWatchdog.stop();
    emit("RELOADED", collectValues());
    done();
  }

  function onSaved() {
    stageWatchdog.stop();
    emit("SAVED", collectValues());
    if (probeCase === "reset")
      graceTimer.start();
    else
      done();
  }
}
