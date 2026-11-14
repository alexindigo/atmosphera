// Approved C2 command shape on the injected old owner; SDK mapping is I5 work.
import QtQuick
import Quickshell
import qs.Commons
import "../../../Helpers/RecordListEditor.js" as Lists

Item {
  id: root
  property bool started: false
  property int step: 0
  property int screenWrites: 0
  property int desktopWrites: 0
  property int globalWrites: 0
  property var continuation: null
  readonly property string screenName: "new.屏/__proto__"
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  function check(ok, name) { if (!ok) throw new Error("I4_CONTAINER_ASSERT: " + name); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function later(next) {check(continuation===null,"one fixture continuation");continuation=next;readyWait.start();}
  Timer {
    id:readyWait;interval:20;repeat:true
    onTriggered:{try{
      var paths=[["bar","widgets","left"],["bar","widgets","center"],["bar","widgets","right"],["bar","screenOverrides"],["desktopWidgets","monitorWidgets"]];
      var probes=paths.map(function(path){return Settings.createRecordListEditor(path,[]);});
      var ready=probes.every(function(probe){return !!probe;});probes.forEach(function(probe){if(probe)probe.detach();});
      if(!ready)return;stop();var next=root.continuation;root.continuation=null;next();
    }catch(error){stop();root.fail(error);}}
  }
  function address(name, section) { return [{field: "name", equals: name}, {key: "widgets"}, {key: section}]; }
  function desktop(name) { return [{field: "name", equals: name}, {key: "widgets"}]; }
  function screens() { return Lists.copy(Settings.data.bar.screenOverrides); }
  function monitors() { return Lists.copy(Settings.data.desktopWidgets.monitorWidgets); }
  function stamp() { return Lists.stamp([screens(), monitors(), Lists.copy(Settings.data.bar.widgets.left), Lists.copy(Settings.data.bar.widgets.center), Lists.copy(Settings.data.bar.widgets.right)]); }
  function captureScreen() {
    return Settings.createRecordListEditor(["bar", "screenOverrides"], address(screenName, "left"), [
      {path: ["bar", "screenOverrides"], listAddress: address(screenName, "center"), ensure: true},
      {path: ["bar", "screenOverrides"], listAddress: address(screenName, "right"), ensure: true},
      {path: ["bar", "widgets", "left"], listAddress: []},
      {path: ["bar", "widgets", "center"], listAddress: []},
      {path: ["bar", "widgets", "right"], listAddress: []}
    ], {ensure: true});
  }
  function copies(editor) {
    return [
      {op: "copy", from: editor.target(3, false), to: editor.target()},
      {op: "copy", from: editor.target(4, false), to: editor.target(1)},
      {op: "copy", from: editor.target(5, false), to: editor.target(2)}
    ];
  }
  function reject(editor, edits, code, next, workerValidation) {
    var before = stamp();
    var sync = true;
    var queued = editor.submit(edits, function (result) {
      try {
        check(!sync && result.status === "failed" && result.error.code === code, code + " observed " + result.status + "/" + result.error.code);
        check(stamp() === before, "refused batch leaves every owner unchanged");
        later(next);
      } catch (error) { fail(error); }
    });
    check(workerValidation ? queued : !queued, "refusal ingress contract " + code);
    check(stamp() === before, "no intermediate creation/admission");
    sync = false;
  }
  function firstCopies() {
    var editor = captureScreen();
    check(editor && editor.initialValue.length === 0 && !screens().some(function (row) { return row.name === screenName; }), "absent capture creates no preference");
    var invalid = copies(editor).concat([{op: "remove", index: 99}]);
    reject(editor, invalid, "list-edit-operation", function () {
      var sourceEnsure = copies(editor);
      sourceEnsure[0].from.ensure = false;
      reject(editor, sourceEnsure, "list-edit-operation", function () {
        reject(editor, [], "list-edit-operation", function () {
          var stale = copies(editor);
          stale[1].from.generation = "99999999999999999999";
          reject(editor, stale, "list-edit-conflict", function () {
            var writes = screenWrites;
            var global = globalWrites;
            var edits = copies(editor).concat([{op: "set", index: 0, field: "edited", value: true}]);
            check(editor.submit(edits, function (result) {
              try {
                check(result.status === "admitted" && result.refreshState === "current", "copy+field admission");
                check(screenWrites === writes + 1 && globalWrites === global, "one destination assignment, copy sources fence-only");
                var left = Lists.listAt(screens(), address(screenName, "left"));
                var center = Lists.listAt(screens(), address(screenName, "center"));
                check(left[0].edited && left[0].opaque.keep && center[0].unknown === "global-center", "owned inherited rows retained");
                reject(editor, copies(editor), "list-edit-operation", function () {
                  reject(editor, [{op: "copy", from: editor.target(5, false), to: editor.target(2)}], "list-edit-operation", function () {
                    // Copy sources are fenced only by commands that read them.
                    // Later local edits must not recapture or depend on globals.
                    Settings.data.bar.widgets.left = [{id: "Volume", opaque: {keep: true}, afterCopy: true}];
                    check(editor.submit([{op: "set", index: 0, field: "afterCopyTarget", value: true}], function (local) {
                      try {
                        check(local.status === "admitted" && local.refreshState === "current", "later local command ignores unused copy sources");
                        editor.detach();
                        staleAbsence();
                      } catch (error) { fail(error); }
                    }), "local edit after global change");
                  }, true);
                }, true);
              } catch (error) { fail(error); }
            }), "complete copy batch admitted");
            edits[0].to.listAddress[0].equals = "caller-mutated";
          });
        });
      });
    });
  }
  function staleAbsence() {
    var name = "created-after-capture";
    var editor = Settings.createRecordListEditor(["bar", "screenOverrides"], address(name, "left"), [], {ensure: true});
    Settings.setScreenOverride(name, "position", "left");
    reject(editor, [{op: "insert", index: 0, value: {id: "Volume"}}], "list-edit-conflict", function () {
      editor.detach();
      identity();
    });
  }
  function identity() {
    check(Settings.setScreenOverride("dup", "position", "left"), "first-match property edit");
    later(function () {
    var duplicate = screens().filter(function (row) { return row.name === "dup"; });
    check(duplicate[0].position === "left" && duplicate[1].opaque === "later" && duplicate[1].position === undefined, "later duplicate is untouched");
    check(Settings.clearScreenOverride("dup", "position"), "unset property");
    later(function () {
    check(screens().filter(function (row) { return row.name === "dup"; })[0].opaque === "first", "unknown member prevents prune");
    check(Settings.setScreenOverride("prune", "density", "compact"), "set last known property");
    later(function () {
    check(Settings.clearScreenOverride("prune", "density"), "prune last known property");
    later(function () {
    check(!screens().some(function (row) { return row.name === "prune"; }), "name-only record pruned");
    check(Settings.clearScreenOverride("created-after-capture"), "clear all first match");
    later(multiTarget);
    }); }); }); });
  }
  function multiTarget() {
    var editor = Settings.createRecordListEditor(["bar", "screenOverrides"], address(screenName, "left"), [
      {path: ["bar", "screenOverrides"], listAddress: address("existing", "right"), ensure: true},
      {path: ["desktopWidgets", "monitorWidgets"], listAddress: desktop("new-desktop"), ensure: true}
    ]);
    var beforeScreen = screenWrites;
    var beforeDesktop = desktopWrites;
    var edits = [
      {op: "insert", index: 1, value: {id: "new-left"}},
      {op: "insert", index: 0, value: {id: "new-right"}, at: editor.target(1)},
      {op: "insert", index: 0, value: {id: "new-desktop"}, at: editor.target(2)}
    ];
    reject(editor, edits.concat([{op: "remove", index: 99, at: editor.target(2)}]), "list-edit-operation", function () {
      check(editor.submit(edits, function (result) {
        try {
          check(result.status === "admitted" && result.refreshState === "current", "at multi-owner admission");
          check(screenWrites === beforeScreen + 1 && desktopWrites === beforeDesktop + 1, "at coalesces each owning leaf");
          editor.detach();
          transferNewMonitor();
        } catch (error) { fail(error); }
      }), "at batch admitted");
    });
  }
  function transferNewMonitor() {
    var destination = desktop("transfer-destination");
    var editor = Settings.createRecordListEditor(["desktopWidgets", "monitorWidgets"], destination, [
      {path: ["desktopWidgets", "monitorWidgets"], listAddress: desktop("source")}
    ], {ensure: true});
    var writes = desktopWrites;
    var edits = [
      {op: "transfer", from: editor.endpoint(0, 1, false), to: editor.endpoint(0)},
      {op: "set", index: 0, field: "x", value: 100},
      {op: "set", index: 0, field: "y", value: 100},
      {op: "set", index: 0, field: "scale", value: 1.0}
    ];
    check(editor.submit(edits, function (result) {
      try {
        check(result.status === "admitted" && desktopWrites === writes + 1, "ensured transfer and placement one assignment");
        editor.detach();
        finalChecks();
        Settings.saveResult(function (saved) {
          try {
            check(saved.status !== "failed", "actual container save receipt");
            finalChecks();
            console.log("I4_LIST_CONTAINERS: SAVED_PASS");
            Qt.exit(0);
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    }), "ensured transfer admitted");
  }
  function finalChecks() {
    var all = screens();
    check(all[0].name === "existing" && all[0].opaque === "keep" && all[0].widgets.left[0].unknown === "existing-row", "unrelated record/list members");
    check(Lists.listAt(all, address(screenName, "left"))[0].edited === true && Lists.listAt(all, address(screenName, "left"))[1].id === "new-left", "inherited edit and at insert consumer");
    check(Lists.listAt(all, address(screenName, "left"))[0].afterCopyTarget === true, "copy source is not a lasting dependency");
    check(Lists.listAt(all, address("existing", "right"))[0].id === "new-right", "absent section created");
    check(!all.some(function (row) { return row.name === "prune" || row.name === "created-after-capture" || row.name === "caller-mutated"; }), "prune, stale and submitted aliases");
    var duplicate = all.filter(function (row) { return row.name === "dup"; });
    check(duplicate.length === 2 && duplicate[0].opaque === "first" && duplicate[1].opaque === "later", "first-match duplicate contract");
    var desktopRows = monitors();
    var moved = Lists.listAt(desktopRows, desktop("transfer-destination"))[0];
    check(moved.id === "Clock" && moved.payload.keep && moved.x === 100 && moved.y === 100 && moved.scale === 1, "original row plus explicit placement fields");
    check(desktopRows[0].opaque === "source" && desktopRows[0].widgets.length === 0 && Lists.listAt(desktopRows, desktop("new-desktop"))[0].id === "new-desktop", "desktop ancestry, empty source and at target");
    check(Settings.data.bar.widgets.left[0].edited === undefined && Settings.data.bar.widgets.left.length === 1, "copy did not edit global source");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_LIST_CONTAINERS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      Settings.data.bar.widgets.left = [{id: "Volume", opaque: {keep: true}}];
      Settings.data.bar.widgets.center = [{id: "Clock", unknown: "global-center"}];
      Settings.data.bar.widgets.right = [];
      var valid = [
        {name: "existing", position: "top", opaque: "keep", widgets: {left: [{id: "Volume", unknown: "existing-row"}]}},
        {name: "dup", opaque: "first"}, {name: "dup", opaque: "later"}
      ];
      Settings.data.bar.screenOverrides = valid;
      [{name:"null-widgets",widgets:null},{name:"wrong-list",widgets:{left:"not a list"}}].forEach(function(invalid){
        var before=JSON.stringify(Settings.data.bar.screenOverrides),refused=false;
        try{Settings.data.bar.screenOverrides=valid.concat([invalid]);}catch(error){refused=String(error).indexOf("configqml:")!==-1;}
        check(refused&&JSON.stringify(Settings.data.bar.screenOverrides)===before,"invalid container atomically refused at typed ingress "+invalid.name);
      });
      Settings.data.desktopWidgets.monitorWidgets = [{name: "source", opaque: "source", widgets: [{id: "Clock", payload: {keep: true}, x: 5, y: 9, scale: 2}]}];
      later(function () {
      check(Settings.createRecordListEditor(["bar", "screenOverrides"], address("missing", "left")) === null, "unensured absence refuses");
      check(Settings.createRecordListEditor(["bar", "screenOverrides"], [{field: "opaque", equals: "keep"}, {key: "widgets"}, {key: "left"}], [], {ensure: true}) === null, "undeclared/optional match field refuses");
      check(Settings.createRecordListEditor(["bar", "screenOverrides"], [{index: 99}, {key: "widgets"}, {key: "left"}], [], {ensure: true}) === null, "index never creates");
      var staleSource = captureScreen();
      check(staleSource !== null, "absent capture creates no preference");
      var original = Lists.copy(Settings.data.bar.widgets.left);
      Settings.data.bar.widgets.left = [{id: "Volume", tag: "intervening"}];
      Settings.data.bar.widgets.left = original;
      reject(staleSource, copies(staleSource), "list-edit-conflict", function () {
        staleSource.detach();
        Settings.data.audio.mprisBlacklist = ["unrelated path does not invalidate selected leaves"];
        firstCopies();
      });
      });
    } catch (error) { fail(error); }
  }
  Connections { target: Settings.data.bar; function onScreenOverridesChanged() { root.screenWrites++; } }
  Connections { target: Settings.data.desktopWidgets; function onMonitorWidgetsChanged() { root.desktopWrites++; } }
  Connections { target: Settings.data.bar.widgets; function onLeftChanged() { root.globalWrites++; } function onCenterChanged() { root.globalWrites++; } function onRightChanged() { root.globalWrites++; } }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 90000; running: true; onTriggered: root.fail("container command watchdog") }
}
