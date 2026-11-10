// Inert prerequisite, relocated to the installed root by the VM-only runner.
import QtQuick
import Quickshell
import ConfigQml 1.0
import "../../../Helpers/SettingsListCommands.js" as Commands
import qs.Commons as Main

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_LIST_DIR")
  readonly property bool restart: Quickshell.env("I4_VERIFY") === "1"
  readonly property var cfg: store.values
  readonly property var paths: [["bar", "widgets", "left"], ["bar", "widgets", "center"], ["bar", "widgets", "right"], ["controlCenter", "shortcuts", "left"], ["controlCenter", "shortcuts", "right"], ["bar", "screenOverrides"], ["desktopWidgets", "monitorWidgets"]]
  readonly property var addresses: [[], [], [], [], [], [{index: 0}, {key: "widgets"}, {key: "left"}], [{index: 0}, {key: "widgets"}]]
  property var tasks: []
  property int cursor: 0
  property int checks: 0
  property bool started: false
  property int rejected: 0

  function check(ok, label) {
    if (!ok)
      throw new Error("I5_NATIVE_LIST_ASSERT: " + label);
    checks++;
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function later(callback) { Qt.callLater(callback); }
  function editor(index, more, options) {
    return Commands.create(store, paths[index], addresses[index], more, options, later);
  }
  function next() {
    try {
      if (cursor === tasks.length) {
        save();
        return;
      }
      tasks[cursor++]();
    } catch (error) { fail(error); }
  }
  function receipt(result, label) {
    console.log("I5_NATIVE_LIST_RECEIPT: " + label + " " + JSON.stringify(result));
  }
  function seven() {
    for (var n = 0; n < 7; ++n) {
      (function (index) {
        tasks.push(function () {
          var path = paths[index].slice();
          var address = Commands.copy(addresses[index]);
          var session = Commands.create(store, path, address, undefined, undefined, later);
          check(session !== null, "seven factory " + index);
          path[0] = "caller-mutated";
          address.push({key: "caller-mutated"});
          var row = index === 0 ? 1 : 0;
          session.initialValue[row].opaque.keep = false;
          check(editor(index).initialValue[row].opaque.keep === true, "owned display DTO " + index);
          var edits = [{op: "set", index: row, field: "tag", value: "edited"},
                       {op: "set", index: row, field: "__proto__", value: {safe: true}},
                       {op: "set", index: row, field: "constructor", value: {safe: true}},
                       {op: "set", index: row, field: "prototype", value: {safe: true}},
                       {op: "unset", index: row, field: "removeMe"}];
          var synchronous = true;
          check(session.submit(edits, function (result) {
            try {
              receipt(result, "seven-" + index);
              check(!synchronous && result.status === "admitted" && result.refreshState === "current", "native admission " + index);
              check(session.generation === store.info(paths[index]).publicationGeneration, "native published generation " + index);
              var seen = session.initialValue[row];
              check(seen.tag === "edited" && seen.opaque.keep === true && !Object.prototype.hasOwnProperty.call(seen, "removeMe"), "field edit consumer " + index);
              check(seen.__proto__.safe === true && seen.constructor.safe === true && seen.prototype.safe === true, "opaque display members " + index);
              session.detach();
              next();
            } catch (error) { fail(error); }
          }), "native request queued " + index);
          edits[0].value = "caller-mutated";
          edits[1].value.safe = false;
          check(!session.submit([{op: "remove", index: 0}], function (result) {
            try { check(result.error.code === "list-editor-busy", "busy receipt"); rejected++; }
            catch (error) { fail(error); }
          }), "busy refusal");
          synchronous = false;
        });
      })(n);
    }
  }
  function invalidBatch() {
    var session = editor(1);
    var before = JSON.stringify(session.initialValue);
    check(session.submit([{op: "remove", index: 0}, {op: "remove", index: 99}], function (result) {
      try {
        receipt(result, "worker-invalid-batch");
        check(result.status === "failed" && result.error.code === "list-edit-operation", "worker semantic refusal");
        check(JSON.stringify(editor(1).initialValue) === before, "worker batch atomicity");
        session.detach();
        next();
      } catch (error) { fail(error); }
    }), "semantic validation is asynchronous");
  }
  function aba() {
    var session = editor(1);
    store.setRuntime(paths[1], [{id: "intervening"}]);
    store.clearRuntime(paths[1], function (written) {
      try { receipt(written, "ABA-clear-runtime"); check(written.status === "accepted", "ABA input settled"); }
      catch (error) { fail(error); }
    });
    check(!session.submit([{op: "remove", index: 0}], function (result) {
      try {
        check(result.status === "failed" && result.error.code === "list-edit-conflict", "native ingress ABA fence");
        session.detach();
        // reload is an ordered worker barrier, never a fresh edit of the work.
        store.reload(function (loaded) {
          try { check(loaded.status === "reloaded", "ABA barrier"); next(); }
          catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    }), "stale session refuses without value stamps");
  }
  function staleRefresh() {
    var session = editor(2);
    var rows = Commands.copy(session.initialValue);
    check(session.submit([{op: "set", index: 0, field: "tag", value: "superseded"}], function (result) {
      try {
        receipt(result, "stale-refresh");
        check(result.status === "admitted" && result.refreshState === "stale", "newer ingress retains stale preview");
        check(!session.submit([{op: "remove", index: 0}], function (refused) {
          try {
            check(refused.error.code === "list-edit-conflict", "sticky stale refresh");
            session.detach();
            store.clearRuntime(paths[2], function (cleared) {
              try {
                check(cleared.status === "accepted", "newer input settled");
                var current = editor(2);
                check(current.submit([{op: "set", index: 0, field: "tag", value: "edited"}], function (restored) {
                  try {
                    check(restored.status === "admitted", "explicit test field restored");
                    current.detach();
                    next();
                  } catch (error) { fail(error); }
                }), "restore test field through native command");
              } catch (error) { fail(error); }
            });
          } catch (error) { fail(error); }
        }), "sticky conflict");
      } catch (error) { fail(error); }
    }), "stale test native request");
    store.setRuntime(paths[2], rows);
  }
  function normalized() {
    store.updateRecordListPolicy("bar-left", {ready: true, entries: [
      {key: "Repeat", available: true, retain: false, normalize: true, defaults: {showIcon: true}}
    ]}, function (projected) {
      try {
        check(projected.status === "projected", "registry metadata admitted");
        var session = editor(0, [{path: paths[1], listAddress: []}]);
        check(session.initialValue.length === 2 && session.initialValue[0].showIcon === true, "hidden raw row and injected display default");
        check(session.initialValue[0].opaque === undefined && session.initialValue[0].instanceSettings?.keep === true, "normalization preserves instance override");
        check(session.submit([{op: "set", index: 0, field: "showIcon", value: false},
                              {op: "transfer", from: session.endpoint(1, 0, false), to: session.endpoint(2, 1, false)}], function (result) {
          try {
            receipt(result, "normalized-transfer");
            check(result.status === "admitted" && result.refreshState === "current", "normalized transfer admission");
            check(cfg.bar.widgets.left.length === 1 && cfg.bar.widgets.left[0].showIcon === false, "normalized field consumer");
            check(cfg.bar.widgets.center.length === 3 && cfg.bar.widgets.center[2].tag === "second", "transferred raw consumer");
            check(cfg.bar.widgets.center[2].showIcon === undefined, "transfer never materializes default");
            session.detach();
            next();
          } catch (error) { fail(error); }
        }), "normalized batch queued");
      } catch (error) { fail(error); }
    });
  }
  function containers() {
    var address = [{field: "name", equals: "offline.屏/__proto__"}, {key: "widgets"}, {key: "right"}];
    var session = editor(2, [{path: paths[5], listAddress: address, ensure: true}]);
    check(session !== null, "absent matched container capture");
    var source = session.target(0, false);
    var destination = session.target(1);
    check(session.submit([{op: "copy", from: source, to: destination},
                          {op: "set", index: 0, field: "tag", value: "created", at: destination}], function (result) {
      try {
        receipt(result, "copy-ensure-at");
        check(result.status === "admitted" && result.refreshState === "current", "copy ensure and per-op target");
        check(cfg.bar.screenOverrides.length === 2 && cfg.bar.screenOverrides[1].name === address[0].equals, "opaque match consumer");
        check(cfg.bar.screenOverrides[1].widgets.right[0].tag === "created", "created child consumer");
        session.detach();
        next();
      } catch (error) { fail(error); }
    }), "container command queued");
    destination.listAddress[0].equals = "caller-mutated";
  }
  function detached() {
    var session = editor(4);
    check(session.submit([{op: "set", index: 1, field: "tag", value: "detached"}], function () {
      fail("detached callback must not deliver");
    }), "detach admitted request");
    session.detach();
    store.reload(function (result) {
      try {
        check(result.status === "reloaded" && cfg.controlCenter.shortcuts.right[1].tag === "detached", "detach preserves admitted work");
        check(!session.submit([{op: "remove", index: 0}], function (closed) {
          try { check(closed.error.code === "list-editor-closed", "closed receipt"); next(); }
          catch (error) { fail(error); }
        }), "closed refusal");
      } catch (error) { fail(error); }
    });
  }
  function sameOwner() {
    var sibling = [{index: 0}, {key: "widgets"}, {key: "right"}];
    var unused = [{index: 0}, {key: "widgets"}, {key: "center"}];
    var session = editor(5, [{path: paths[5], listAddress: sibling, ensure: true}, {path: paths[5], listAddress: unused, ensure: true}]);
    check(session.submit([{op: "copy", from: session.target(0, false), to: session.target(1)}], function (copied) {
      try {
        check(copied.status === "admitted" && copied.refreshState === "current", "same owning leaf copy");
        check(session.target(0).generation === session.target(1).generation && session.target(0).generation === session.target(2).generation, "same owner endpoint refresh");
        check(session.submit([{op: "set", index: 0, field: "tag", value: "same-leaf", at: session.target(1)}], function (edited) {
          try {
            check(edited.status === "admitted" && edited.refreshState === "current", "same owner sequential target");
            check(cfg.bar.screenOverrides[0].widgets.right[0].tag === "same-leaf", "same owner consumer");
            session.detach();
            next();
          } catch (error) { fail(error); }
        }), "same owner second command queued");
      } catch (error) { fail(error); }
    }), "same owner copy queued");
  }
  function verify() {
    for (var n = 1; n < 7; ++n) {
      var session = editor(n);
      check(session !== null, "cold factory " + n);
      var row = session.initialValue[0];
      check(row.tag === "edited" && row.opaque.keep === true, "cold selected consumer " + n);
      check(row.__proto__.safe === true && row.constructor.safe === true && row.prototype.safe === true, "cold opaque member consumer " + n);
      session.detach();
    }
    check(cfg.bar.widgets.left.length === 2 && cfg.bar.widgets.left[0].id === "Ghost" && cfg.bar.widgets.left[1].showIcon === false, "cold unnormalized left rows");
    check(Commands.own(cfg.bar.widgets.left[1], "__proto__").safe === true, "cold seventh prototype member");
    check(cfg.bar.widgets.center.length === 3 && cfg.bar.widgets.center[2].tag === "second", "cold raw transfer");
    check(cfg.bar.screenOverrides[1].widgets.right[0].tag === "created", "cold copy ensure");
    check(cfg.controlCenter.shortcuts.right[1].tag === "detached", "cold detached work");
    check(cfg.bar.screenOverrides[0].widgets.right[0].tag === "same-leaf", "cold same-owner target");
  }
  function save() {
    check(rejected === 7, "all busy callbacks observed");
    store.save(function (result) {
      try {
        receipt(result, "save");
        check(result.status === "saved", "actual preserving file receipt");
        store.close(function (closed) {
          try {
            check(closed.status === "nothing_to_save", "async worker close");
            console.log("I5_NATIVE_LIST_COMMANDS: SAVED_PASS checks=" + checks);
            Qt.exit(0);
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (!store.ready || started)
      return;
    started = true;
    Qt.callLater(function () {
      try {
        if (restart) {
          verify();
          console.log("I5_NATIVE_LIST_COMMANDS: RESTART_PASS checks=" + checks);
          Qt.exit(0);
          return;
        }
        check(Commands.create(store, ["ui", "fontDefault"], [], undefined, undefined, later) === null, "unsupported owner");
        check(Commands.create(store, paths[5], [{index: 99}, {key: "widgets"}, {key: "left"}], undefined, undefined, later) === null, "missing index never ensured");
        seven();
        tasks = tasks.concat([invalidBatch, aba, staleRefresh, normalized, containers, detached, sameOwner]);
        next();
      } catch (error) { fail(error); }
    });
  }
  Main.SettingsSources {
    id: routes
    settingsFile: root.directory + "/settings.json"
    overridesDirectory: root.directory + "/settings"
  }
  Main.SettingsRecordListPolicies { id: policies }
  MemorySource { id: runtime; sourceId: "mask"; layerId: "runtime"; kind: MemorySource.Runtime; writable: false }
  ConfigStore {
    id: store
    autoSave: false
    evidenceDirectory: root.directory + "/evidence"
    schema: Main.SettingsSchema { homeDirectory: "/inert/home"; defaultFont: "Test Sans"; fixedFont: "Test Mono" }
    sources: [...routes.sources, runtime]
    recordListPolicies: policies.policies
    onReadyChanged: root.begin()
    onStatusChanged: { if (status === ConfigStore.Error) root.fail("store initialization: " + error); }
  }
  Timer { interval: 30000; running: true; onTriggered: root.fail("native list watchdog"); }
}
