// Inert entrypoint relocated to the installed shell root by the VM-only driver.
import QtQuick
import Quickshell
import qs.Commons
import "../../../Helpers/RecordListEditor.js" as RecordListEditor

Item {
  id: root
  property bool started: false
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property string ownerMode: Quickshell.env("I4_SETTINGS_OWNER")
  property var cases: []
  property int caseIndex: 0
  property int failedCallbacks: 0

  function check(ok, name) {
    if (!ok)
      throw new Error("I4_RECORD_LIST_ASSERT: " + name);
  }

  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }

  function value(path) {
    var node = Settings.data;
    for (var i = 0; i < path.length; ++i)
      node = node[path[i]];
    return node;
  }
  function list(path, address) { return RecordListEditor.listAt(RecordListEditor.copy(value(path)), address); }

  function finalChecks() {
    for (var i = 0; i < cases.length; ++i) {
      var rows = list(cases[i].path, cases[i].address);
      check(rows.length === 2 && rows[0].id === "Repeat" && rows[0].tag === "second", "sequential final row " + i);
      check(rows[1].id === "Repeat" && rows[1].tag === "edited" && rows[1].opaque.keep === true, "field-only edit retains opaque " + i);
      check(!Object.prototype.hasOwnProperty.call(rows[1], "removeMe"), "explicit unset " + i);
      check(Object.prototype.hasOwnProperty.call(rows[1], "constructor") && rows[1].constructor.safe === true, "constructor field " + i);
      check(Object.prototype.hasOwnProperty.call(rows[1], "prototype") && rows[1].prototype.safe === true, "prototype field " + i);
      // Run the original assertion on both owners. Only the old-owner cold leg
      // expects this exact failure (I4-answer-3; mandatory PASS in I5).
      var expectedFailure = verifyOnly && ownerMode === "legacy";
      var observedFailure = "";
      try {
        check(Object.prototype.hasOwnProperty.call(rows[1], "__proto__") && rows[1]["__proto__"].safe === true, "opaque field " + i);
      } catch (error) {
        if (!expectedFailure)
          throw error;
        observedFailure = String(error);
      }
      if (expectedFailure) {
        check(observedFailure === "Error: I4_RECORD_LIST_ASSERT: opaque field " + i, "XPASS or unexpected failure for old-owner opaque field " + i);
        console.log("I4_RECORD_LIST_PROTO: XFAIL row=" + i + " reason=I4-answer-3 old QtObj2JS prototype setter; required PASS at I5");
      }
    }
    check(Settings.data.bar.screenOverrides[0].opaque === "monitor" && Settings.data.desktopWidgets.monitorWidgets[0].opaque === "desktop", "nested owner ancestry");
  }

  function failed(result, code) {
    check(result.status === "failed" && result.error.code === code, code);
    failedCallbacks++;
  }

  function nextCase() {
    try {
      if (caseIndex === cases.length) {
        finish();
        return;
      }
      var entry = cases[caseIndex++];
      var selectedPath = entry.path.slice();
      var selectedAddress = RecordListEditor.copy(entry.address);
      var editor = Settings.createRecordListEditor(selectedPath, selectedAddress);
      check(editor !== null, "factory " + caseIndex);
      selectedPath[0] = "not-an-owner";
      selectedAddress.push({key: "not-a-list"});
      editor.initialValue[0].opaque.keep = false;
      check(list(entry.path, entry.address)[0].opaque.keep === true, "owned initial snapshot");
      var before = JSON.stringify(value(entry.path));
      var sync = true;
      check(!editor.submit([{op: "remove", index: 0}, {op: "remove", index: 99}], function (result) {
        try { check(!sync, "async invalid"); failed(result, "list-edit-operation"); } catch (error) { fail(error); }
      }), "invalid batch refused");
      check(JSON.stringify(value(entry.path)) === before, "invalid batch atomicity");
      var edits = [{op: "set", index: 0, field: "tag", value: "edited"},
                   {op: "set", index: 0, field: "__proto__", value: {safe: true}},
                   {op: "set", index: 0, field: "constructor", value: {safe: true}},
                   {op: "set", index: 0, field: "prototype", value: {safe: true}},
                   {op: "unset", index: 0, field: "removeMe"},
                   {op: "insert", index: 2, value: {id: "temporary"}},
                   {op: "move", index: 0, to: 1}, {op: "remove", index: 2}];
      check(editor.submit(edits, function (result) {
        try {
          check(!sync && result.status === "admitted" && result.refreshState === "current", "async admission, not persistence");
          check(editor.generation === result.generation, "capture refreshed after own admission");
          check(editor.submit([{op: "set", index: 1, field: "tag", value: "edited"}], function (again) {
            try {
              check(again.status === "admitted", "sequential live command");
              editor.detach();
              check(!editor.submit([{op: "remove", index: 0}], function (closed) {
                try { failed(closed, "list-editor-closed"); nextCase(); } catch (error) { fail(error); }
              }), "closed refusal");
            } catch (error) { fail(error); }
          }), "next command admitted");
        } catch (error) { fail(error); }
      }), "batch admitted");
      edits[0].value = "caller-mutated";
      edits[1].value.safe = false;
      check(!editor.submit([{op: "remove", index: 0}], function (busy) {
        try { failed(busy, "list-editor-busy"); } catch (error) { fail(error); }
      }), "busy refusal");
      sync = false;
    } catch (error) { fail(error); }
  }

  function finish() {
    check(failedCallbacks === cases.length * 3, "all async refusals delivered");
    finalChecks();
    // Same type IDs cannot protect an old index; the complete owner is fenced.
    var path = ["bar", "widgets", "left"];
    var stale = Settings.createRecordListEditor(path, []);
    var rows = RecordListEditor.copy(value(path));
    Settings.data.bar.widgets.left = [rows[1], rows[0]];
    check(!stale.submit([{op: "remove", index: 0}], function (result) {
      try {
        failed(result, "list-edit-conflict");
        Settings.data.bar.widgets.left = rows;
        var aba = Settings.createRecordListEditor(path, []);
        Settings.data.bar.widgets.left = [{id: "intervening"}];
        Settings.data.bar.widgets.left = rows;
        check(!aba.submit([{op: "remove", index: 0}], function (abaResult) {
          try {
            failed(abaResult, "list-edit-conflict");
            var late = Settings.createRecordListEditor(path, []);
            check(late.submit([{op: "set", index: 0, field: "tag", value: "stale-preview"}], function (lateResult) {
              try {
                check(lateResult.status === "admitted" && lateResult.refreshState === "stale", "later ingress retained");
                check(!late.submit([{op: "remove", index: 0}], function (sticky) {
                  try {
                    failed(sticky, "list-edit-conflict");
                    saveFinal();
                  } catch (error) { fail(error); }
                }), "stale refresh is sticky");
              } catch (error) { fail(error); }
            }), "held callback command");
            Settings.data.bar.widgets.left = rows;
          } catch (error) { fail(error); }
        }), "notification ABA refusal");
      } catch (error) { fail(error); }
    }), "repeated-ID reorder refusal");
  }

  function saveFinal() {
    finalChecks();
    Settings.saveResult(function (result) {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "actual persistence receipt");
        finalChecks();
        console.log("I4_RECORD_LIST_EDITORS: SAVED_PASS");
        Qt.exit(0);
      } catch (error) { fail(error); }
    });
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      check(ownerMode === "legacy" || ownerMode === "configqml", "explicit I4_SETTINGS_OWNER required");
      cases = [{path: ["bar", "widgets", "left"], address: []},
               {path: ["bar", "widgets", "center"], address: []},
               {path: ["bar", "widgets", "right"], address: []},
               {path: ["controlCenter", "shortcuts", "left"], address: []},
               {path: ["controlCenter", "shortcuts", "right"], address: []},
               {path: ["bar", "screenOverrides"], address: [{index: 0}, {key: "widgets"}, {key: "left"}]},
               {path: ["desktopWidgets", "monitorWidgets"], address: [{index: 0}, {key: "widgets"}]}];
      if (verifyOnly) {
        finalChecks();
        console.log("I4_RECORD_LIST_EDITORS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      check(RecordListEditor.nextGeneration("99999999999999999999") === "100000000000000000000", "exact local generation increment");
      var rows = [{id: "Repeat", tag: "first", opaque: {keep: true}, removeMe: true}, {id: "Repeat", tag: "second"}];
      Settings.data.bar.widgets.left = RecordListEditor.copy(rows);
      Settings.data.bar.widgets.center = RecordListEditor.copy(rows);
      Settings.data.bar.widgets.right = RecordListEditor.copy(rows);
      Settings.data.controlCenter.shortcuts.left = RecordListEditor.copy(rows);
      Settings.data.controlCenter.shortcuts.right = RecordListEditor.copy(rows);
      Settings.data.bar.screenOverrides = [{name: "offline.屏/1", opaque: "monitor", widgets: {left: RecordListEditor.copy(rows), center: [], right: []}}];
      Settings.data.desktopWidgets.monitorWidgets = [{name: "offline.屏/1", opaque: "desktop", widgets: RecordListEditor.copy(rows)}];
      check(Settings.createRecordListEditor(["ui", "fontDefault"], []) === null, "unsupported owner");
      check(Settings.createRecordListEditor(["bar", "screenOverrides"], [{index: 9}, {key: "widgets"}]) === null, "missing list");
      nextCase();
    } catch (error) { fail(error); }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("record-list watchdog")
  }
}
