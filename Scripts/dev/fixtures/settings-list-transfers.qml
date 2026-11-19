// Inert real-owner transfer boundary; the VM driver relocates it to shell root.
import QtQuick
import Quickshell
import qs.Commons
import "../../../Helpers/RecordListEditor.js" as Lists

Item {
  id: root
  property bool started: false
  property int currentCase: 0
  property int invalidCase: 0
  property int refused: 0
  property int screenWrites: 0
  property int desktopWrites: 0
  property int centerWrites: 0
  property var session: null
  property var cases: [
    {from: ["bar", "widgets", "left"], to: ["bar", "widgets", "center"], source: [], destination: []},
    {from: ["controlCenter", "shortcuts", "left"], to: ["controlCenter", "shortcuts", "right"], source: [], destination: []},
    {from: ["bar", "screenOverrides"], to: ["bar", "screenOverrides"], source: [{index: 0}, {key: "widgets"}, {key: "left"}], destination: [{index: 0}, {key: "widgets"}, {key: "right"}]},
    {from: ["desktopWidgets", "monitorWidgets"], to: ["desktopWidgets", "monitorWidgets"], source: [{index: 0}, {key: "widgets"}], destination: [{index: 1}, {key: "widgets"}]}
  ]
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  function check(ok, name) {
    if (!ok)
      throw new Error("I4_TRANSFER_ASSERT: " + name);
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function value(path) {
    var node = Settings.data;
    for (var i = 0; i < path.length; ++i)
      node = node[path[i]];
    return Lists.copy(node);
  }
  function write(path, data) {
    var node = Settings.data;
    for (var i = 0; i < path.length - 1; ++i)
      node = node[path[i]];
    node[path[path.length - 1]] = data;
  }
  function state(entry) { return Lists.stamp([value(entry.from), value(entry.to)]); }
  function capture(entry) {
    var path = entry.from.slice();
    var address = Lists.copy(entry.source);
    var targets = [{path: entry.to.slice(), listAddress: Lists.copy(entry.destination)}];
    var editor = Settings.createRecordListEditor(path, address, targets);
    check(editor !== null && typeof editor.endpoint === "function", "captured transfer API");
    path[0] = "caller-mutated";
    address.push({key: "caller-mutated"});
    targets[0].path[0] = "caller-mutated";
    targets[0].listAddress.push({key: "caller-mutated"});
    editor.initialValue[0].opaque.keep = false;
    return editor;
  }
  function command(editor) { return {op: "transfer", from: editor.endpoint(0), to: editor.endpoint(1, 1)}; }
  function failed(result, code) {
    check(result.status === "failed" && result.error.code === code, code);
    refused++;
  }
  function invalid() {
    try {
      var entry = cases[currentCase];
      if (invalidCase === 7) {
        staleSource(entry);
        return;
      }
      var move = command(session);
      var edits = [move];
      var code = "list-edit-operation";
      switch (invalidCase++) {
      case 0: move.to.index = 99; break;
      case 1: move.to.extra = true; break;
      case 2: move.to.generation = 1; break;
      case 3: move.to.listAddress = [{each: true}]; break;
      case 4: move.to.policyId = "uncaptured"; break;
      case 5: edits.push({op: "remove", index: 99}); break;
      case 6: move.to.generation = "99999999999999999999"; code = "list-edit-conflict"; break;
      }
      var before = state(entry);
      var sync = true;
      check(!session.submit(edits, function (result) {
        try { check(!sync, "async refusal"); failed(result, code); invalid(); } catch (error) { fail(error); }
      }), "invalid batch refused");
      check(state(entry) === before, "no half transfer from invalid batch");
      sync = false;
    } catch (error) { fail(error); }
  }
  function staleSource(entry) {
    var original = value(entry.from);
    var changed = Lists.copy(original);
    Lists.listAt(changed, entry.source).reverse();
    write(entry.from, changed);
    var before = state(entry);
    check(!session.submit([command(session)], function (result) {
      try {
        failed(result, "list-edit-conflict");
        check(state(entry) === before, "repeated-ID stale source unchanged");
        write(entry.from, original);
        session = capture(entry);
        var target = value(entry.to);
        var altered = Lists.copy(target);
        Lists.listAt(altered, entry.destination).push({id: "temporary"});
        write(entry.to, altered);
        write(entry.to, target);
        check(!session.submit([command(session)], function (aba) {
          try {
            failed(aba, "list-edit-conflict");
            check(Lists.stamp(value(entry.to)) === Lists.stamp(target), "destination notified ABA retained");
            transfer(entry);
          } catch (error) { fail(error); }
        }), "destination ABA refused");
      } catch (error) { fail(error); }
    }), "source stale refused");
  }
  function transfer(entry) {
    session = capture(entry);
    var move = command(session);
    var beforeScreen = screenWrites;
    var beforeDesktop = desktopWrites;
    var sync = true;
    check(session.submit([{op: "set", index: 0, field: "explicit", value: false}, move], function (result) {
      try {
        check(!sync && result.status === "admitted" && result.refreshState === "current", "current admission, not save");
        check(Lists.listAt(value(entry.from), entry.source).length === 1, "actual source consumer");
        var destination = Lists.listAt(value(entry.to), entry.destination);
        check(destination.length === 2 && destination[1].tag === "first" && destination[1].opaque.keep && destination[1].explicit === false, "actual destination consumer retains row");
        if (currentCase === 2)
          check(screenWrites === beforeScreen + 1, "one atomic screen leaf assignment");
        if (currentCase === 3)
          check(desktopWrites === beforeDesktop + 1, "one atomic desktop leaf assignment");
        session.detach();
        check(!session.submit([command(session)], function (closed) {
          try {
            failed(closed, "list-editor-closed");
            currentCase++;
            if (currentCase === cases.length)
              sameList();
            else {
              invalidCase = 0;
              session = capture(cases[currentCase]);
              invalid();
            }
          } catch (error) { fail(error); }
        }), "closed refusal");
      } catch (error) { fail(error); }
    }), "transfer admitted");
    move.from.listAddress.push({key: "caller-mutated"});
    move.to.index = 99;
    check(!session.submit([], function (busy) {
      try { failed(busy, "list-editor-busy"); } catch (error) { fail(error); }
    }), "busy refusal");
    sync = false;
  }
  function sameList() {
    var path = cases[0].to;
    session = Settings.createRecordListEditor(path, []);
    var before = value(path);
    var invalidMove = {op: "transfer", from: session.endpoint(0), to: session.endpoint(2)};
    check(!session.submit([invalidMove], function (result) {
      try {
        failed(result, "list-edit-operation");
        var writes = centerWrites;
        // Destination slot is after removal, and both generations address the
        // initial publication even in a sequential two-transfer batch.
        check(session.submit([
          {op: "transfer", from: session.endpoint(1), to: session.endpoint(0)},
          {op: "transfer", from: session.endpoint(0), to: session.endpoint(1)}
        ], function (admitted) {
          try {
            check(admitted.status === "admitted" && admitted.refreshState === "current", "same-list sequential transfers");
            check(centerWrites <= writes + 1, "at most one same-leaf assignment notification");
            check(Lists.stamp(value(path)) === Lists.stamp(before), "after-removal end slot");
            save();
          } catch (error) { fail(error); }
        }), "same-list batch admitted");
      } catch (error) { fail(error); }
    }), "pre-removal end slot refused");
    check(Lists.stamp(value(path)) === Lists.stamp(before), "invalid self transfer unchanged");
  }
  function finalChecks() {
    for (var i = 0; i < cases.length; ++i) {
      var entry = cases[i];
      var source = Lists.listAt(value(entry.from), entry.source);
      var target = Lists.listAt(value(entry.to), entry.destination);
      check(source.length === 1 && source[0].tag === "second" && source[0].explicit === undefined, "source final " + i);
      check(target.length === 2 && target[0].tag === "destination" && target[1].tag === "first", "destination final " + i);
      check(target[1].explicit === false && target[1].opaque.keep && target[1].deprecatedData.token === "retain", "unknown row members retained " + i);
      check(!Object.prototype.hasOwnProperty.call(target[1], "injectedDefault"), "no default materialization " + i);
    }
    check(Settings.data.bar.screenOverrides[0].opaque === "screen" && Settings.data.desktopWidgets.monitorWidgets[1].opaque === "desktop", "owner ancestry retained");
  }
  function save() {
    finalChecks();
    check(refused === cases.length * 11 + 1, "all refusal callbacks delivered");
    Settings.setBindingsUnresolved(true);
    Settings.saveResult(function (failedSave) {
      try {
        check(failedSave.status === "failed", "failed aggregate save is not admitted/saved");
        finalChecks();
        Settings.setBindingsUnresolved(false);
        // Retry persistence, never replay the membership command.
        Settings.saveResult(function (result) {
          try {
            check(result.status === "saved" || result.status === "nothing_to_save", "actual retry receipt");
            finalChecks();
            console.log("I4_LIST_TRANSFERS: SAVED_PASS");
            Qt.exit(0);
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_LIST_TRANSFERS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      var rows = [{id: "Repeat", tag: "first", opaque: {keep: true}, deprecatedData: {token: "retain"}}, {id: "Repeat", tag: "second"}];
      var destination = [{id: "Repeat", tag: "destination"}];
      Settings.data.bar.widgets.left = Lists.copy(rows);
      Settings.data.bar.widgets.center = Lists.copy(destination);
      Settings.data.controlCenter.shortcuts.left = Lists.copy(rows);
      Settings.data.controlCenter.shortcuts.right = Lists.copy(destination);
      Settings.data.bar.screenOverrides = [{name: "offline.屏/1", opaque: "screen", widgets: {left: Lists.copy(rows), center: [], right: Lists.copy(destination)}}];
      Settings.data.desktopWidgets.monitorWidgets = [{name: "offline.屏/1", widgets: Lists.copy(rows)}, {name: "other.屏/2", opaque: "desktop", widgets: Lists.copy(destination)}];
      session = capture(cases[0]);
      invalid();
    } catch (error) { fail(error); }
  }
  Connections { target: Settings.data.bar; function onScreenOverridesChanged() { root.screenWrites++; } }
  Connections { target: Settings.data.desktopWidgets; function onMonitorWidgetsChanged() { root.desktopWrites++; } }
  Connections { target: Settings.data.bar.widgets; function onCenterChanged() { root.centerWrites++; } }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 90000; running: true; onTriggered: root.fail("transfer watchdog") }
}
