// Actual monitor owner/factory contract; inert until the named VM runner invokes it.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Modules.Panels.Settings.Bar as Bar

Item {
  id: root
  readonly property var testScreen: Quickshell.screens[0]
  readonly property string name: testScreen.name
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property bool started: false
  property int writes: 0
  property int globalWrites: 0
  property int refusals: 0
  property var live: null
  Bar.MonitorWidgetsConfig { id: monitor; screen: root.testScreen }
  function check(ok, message) { if (!ok) throw new Error("I4_MONITOR_ASSERT: " + message); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function shown(): var { return Settings.getBarWidgetsForScreen(name); }
  function seed() {
    Settings.data.bar.widgets.left = [{id: "Volume", tag: "first", opaque: {keep: true}}, {id: "Volume", tag: "second"}];
    Settings.data.bar.widgets.center = [{id: "Clock", tag: "center"}];
    Settings.data.bar.widgets.right = [];
    Settings.data.bar.screenOverrides = [
      {name: name, enabled: true, position: "top", opaque: "monitor"},
      {name: name, opaque: "later-duplicate", widgets: {left: [{id: "Volume", tag: "duplicate"}], center: [], right: []}}
    ];
  }
  function untouched() {
    check(Settings.data.bar.screenOverrides[0].widgets === undefined, "no inherited preference created");
    check(Settings.data.bar.screenOverrides[1].widgets.left[0].tag === "duplicate", "later duplicate untouched");
  }
  function reject(interaction, action, target, code, next) {
    var before = JSON.stringify(Settings.data.bar.screenOverrides);
    check(!interaction.submit(action, target, function (result) {
      try {
        check(result.status === "failed" && result.error.code === code, code);
        check(JSON.stringify(Settings.data.bar.screenOverrides) === before, "refused interaction changes nothing");
        interaction.detach();
        refusals++;
        next();
      } catch (error) { fail(error); }
    }), "synchronous refused admission");
    check(JSON.stringify(Settings.data.bar.screenOverrides) === before, "no transient inheritance on refusal");
  }
  function staleGlobal() {
    var interaction = typeof monitor.captureWidgetInteraction === "function" ? monitor.captureWidgetInteraction("left", 0) : null;
    if (interaction)
      interaction.initialValue.opaque.keep = false;
    Settings.data.bar.widgets.center = [{id: "Clock", tag: "intervening"}];
    if (!interaction) {
      // Parent red exercises the actual old late-index owner, not a fake receipt.
      monitor._moveWidgetBetweenSections("left", 0, "center");
      check(!Settings.hasScreenOverride(name, "widgets"), "stale global created an override");
      return;
    }
    reject(interaction, "move", "center", "list-edit-conflict", function () {
      untouched();
      seed();
      var route = monitor.captureWidgetInteraction("left", 0);
      Settings.setScreenOverride(name, "widgets", {left: [{id: "Volume", tag: "foreign"}], center: [], right: []});
      reject(route, "remove", null, "list-edit-conflict", function () {
        check(shown().left[0].tag === "foreign", "concurrent creator retained");
        seed();
        invalidThenMove();
      });
    });
  }
  function invalidThenMove() {
    var canceled = monitor.captureWidgetInteraction("left", 0);
    canceled.detach();
    untouched();
    check(monitor.captureWidgetInteraction("left", 99) === null, "invalid source index creates nothing");
    var invalid = monitor.captureWidgetInteraction("left", 0);
    reject(invalid, "reorder", 99, "list-edit-operation", function () {
      untouched();
      var interaction = monitor.captureWidgetInteraction("left", 0);
      var before = writes;
      var globals = globalWrites;
      check(interaction.submit("move", "center", function (result) {
        try {
          check(result.status === "admitted" && result.refreshState === "current", "inherited transfer admission");
          check(writes === before + 1 && globalWrites === globals, "copy three plus transfer is one destination assignment");
          check(shown().left[0].tag === "second" && shown().center[1].tag === "first" && shown().center[1].opaque.keep, "original displayed row transferred");
          check(Settings.data.bar.widgets.left.length === 2 && Settings.data.bar.widgets.center.length === 1, "global copy sources not written");
          check(Settings.data.bar.screenOverrides[0].opaque === "monitor" && Settings.data.bar.screenOverrides[1].opaque === "later-duplicate", "monitor unknowns and duplicate retained");
          interaction.detach();
          firstLiveEdit();
        } catch (error) { fail(error); }
      }), "copy plus transfer admitted");
    });
  }
  function firstLiveEdit() {
    seed();
    live = monitor.captureWidgetSettings("left", 0);
    check(live !== null && live.initialValue.tag === "first", "live editor captures inherited row");
    live.initialValue.opaque.keep = false;
    untouched();
    Settings.setBindingsUnresolved(true);
    var before = writes;
    check(live.submit({edited: true}, function (result) {
      try {
        check(result.status === "failed", "real failed save receipt");
        check(shown().left[0].edited === true && shown().left[0].opaque.keep && writes === before + 1, "failed save retains one inherited admission");
        Settings.setBindingsUnresolved(false);
        Settings.data.bar.widgets.left = [{id: "Volume", tag: "new-global"}];
        Settings.data.bar.widgets.center = [{id: "Clock", tag: "new-center"}];
        // The first copy is already admitted. Retry only this field command and
        // persistence, without re-copying changed globals or retargeting the row.
        check(live.submit({again: true}, function (saved) {
          try {
            check(saved.status !== "failed" && shown().left[0].tag === "first" && shown().left[0].again === true, "same-session local retry after own route change");
            check(shown().center[0].tag === "center" && Settings.data.bar.widgets.center[0].tag === "new-center", "frozen copied layout independent of later globals");
            live.detach();
            missingSection();
          } catch (error) { fail(error); }
        }), "later local edit ignores unused copy sources");
      } catch (error) { fail(error); }
    }), "first inherited field input admitted");
  }
  function missingSection() {
    var existing = monitor.captureWidgetSettings("left", 0);
    var duplicate = Settings.data.bar.screenOverrides[1];
    Settings.data.bar.screenOverrides = [
      {name: name, enabled: true, opaque: "monitor", widgets: {left: [{id: "Volume", tag: "kept", opaque: {keep: true}}]}},
      duplicate
    ];
    check(!existing.submit({mustNotLand: true}, function (result) {
      try {
        check(result.status === "failed" && result.error.code === "list-edit-conflict", "live repeated-row replacement refuses");
        existing.detach();
        check(monitor._addWidgetToSection("Clock", "center"), "missing section insert");
        Settings.saveResult(function (saved) {
          try {
            check(saved.status !== "failed" && shown().center[0].id === "Clock" && shown().left[0].tag === "kept", "section insert leaves stored layout intact");
            var moved = monitor.captureWidgetInteraction("center", 0);
            check(moved.submit("move", "right", function (admitted) {
              try {
                check(admitted.status === "admitted" && shown().center.length === 0 && shown().right[0].id === "Clock", "existing route ensured transfer");
                moved.detach();
                disabledStoredOverride();
              } catch (error) { fail(error); }
            }), "existing route move");
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    }), "live stale input refused");
  }
  function finalChecks() {
    var rows = Settings.data.bar.screenOverrides;
    check(rows.length === 2 && rows[0].opaque === "monitor" && rows[0].widgets.left[0].tag === "kept" && rows[0].widgets.left[0].opaque.keep, "final owning monitor/data");
    check(rows[0].widgets.left[0].mustNotLand === undefined && rows[0].widgets.center.length === 0 && rows[0].widgets.right[0].id === "Clock", "final section command consumers");
    check(rows[1].opaque === "later-duplicate" && rows[1].widgets.left[0].tag === "duplicate", "first-match duplicate contract");
    check(Settings.data.bar.widgets.left[0].tag === "new-global" && Settings.data.bar.widgets.center[0].tag === "new-center", "independent globals retained");
  }
  function disabledStoredOverride() {
    Settings.setScreenOverride(name, "enabled", false);
    var interaction = monitor.captureWidgetInteraction("left", 0);
    check(interaction !== null, "disabled unreachable path captured for refusal");
    reject(interaction, "remove", null, "list-edit-operation", function () {
      Settings.setScreenOverride(name, "enabled", true);
      finalSave();
    });
  }
  function finalSave() {
    finalChecks();
    Settings.saveResult(function (result) {
      try {
        check(result.status !== "failed" && refusals === 4, "final actual save/refusal observations");
        finalChecks();
        console.log("I4_MONITOR_SECTIONS: SAVED_PASS");
        Qt.exit(0);
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
        console.log("I4_MONITOR_SECTIONS: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      seed();
      var owned = monitor._getWidgetsContainer();
      owned.right.push({id: "unpublished"});
      untouched();
      check(Settings.data.bar.widgets.right.length === 0, "read copy has no live aliases");
      staleGlobal();
    } catch (error) { fail(error); }
  }
  Connections { target: Settings.data.bar; function onScreenOverridesChanged() { root.writes++; } }
  Connections { target: Settings.data.bar.widgets; function onLeftChanged() { root.globalWrites++; } function onCenterChanged() { root.globalWrites++; } function onRightChanged() { root.globalWrites++; } }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 90000; running: true; onTriggered: root.fail("monitor commands watchdog") }
}
