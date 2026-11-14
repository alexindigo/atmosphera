// Inert entrypoint copied into an installed candidate by the VM804 driver.
import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras as Extras

Item {
  id: root
  readonly property var testScreen: Quickshell.screens[0]
  property bool started: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property int route: 0

  Extras.TrayMenu {
    id: tray
    shellScreen: root.testScreen
    widgetSection: "left"
    widgetIndex: 0
    trayItem: ({"tooltipTitle": "I4 captured tray", "menu": null})
  }

  function check(ok, name) {
    if (!ok)
      throw new Error("I4_TRAY_ASSERT: " + name);
  }

  function rows() {
    return Settings.getBarWidgetsForScreen(testScreen.name).left;
  }

  function capture() {
    // The parent control has no capture boundary. Keep its real public writer
    // in the stale schedule so red observes an incorrect consumer, not a typo.
    if (typeof tray.capturePinEditor === "function")
      tray.capturePinEditor();
  }

  function assignRows(value) {
    if (route === 0)
      Settings.data.bar.widgets.left = value;
    else
      Settings.data.bar.screenOverrides = [{"name": testScreen.name, "opaque": "monitor", "widgets": {"left": value, "center": [], "right": [{"id": "I4 sibling"}]}}];
  }

  function seed() {
    assignRows([{"id": "Tray", "pinned": [], "opaque": "keep"}, {"id": "Tray", "pinned": [], "opaque": "sibling"}]);
  }

  function failed(result, code, name) {
    check(result.status === "failed" && result.error.code === code, name);
  }

  function staleCases() {
    seed();
    capture();
    var original = JSON.parse(JSON.stringify(rows()));
    assignRows([original[1], original[0]]);
    var before = JSON.stringify(rows());
    tray.addToPinned(function(result) {
      try {
        failed(result, "list-edit-conflict", "repeated-ID conflict receipt " + route);
        abaCase();
      } catch (error) { root.fail(error); }
    });
    check(JSON.stringify(rows()) === before, "captured pin refuses repeated-ID replacement " + route);
  }

  function abaCase() {
    seed();
    capture();
    var original = JSON.parse(JSON.stringify(rows()));
    assignRows([{"id": "I4 intervening"}]);
    assignRows(original);
    check(tray.addToPinned(function(result) {
      try {
        failed(result, "list-edit-conflict", "ABA conflict receipt " + route);
        if (route === 0)
          routingCase();
        else
          failureCase();
      } catch (error) { root.fail(error); }
    }) === false, "notified ABA refused " + route);
    check(rows()[0].pinned.length === 0, "ABA unchanged consumer " + route);
  }

  function routingCase() {
    seed();
    capture();
    Settings.data.bar.screenOverrides = [{"name": testScreen.name, "widgets": {"left": [{"id": "Tray", "pinned": []}], "center": [], "right": []}}];
    check(tray.addToPinned(function(result) {
      try {
        failed(result, "list-edit-conflict", "route change conflict");
        check(rows()[0].pinned.length === 0 && Settings.data.bar.widgets.left[0].pinned.length === 0, "neither route changed");
        Settings.data.bar.screenOverrides = [{"name": testScreen.name, "enabled": false, "widgets": {"left": [{"id": "Tray", "pinned": []}], "center": [], "right": []}}];
        seed();
        capture();
        tray.addToPinned(function(disabled) {
          try {
            check(disabled.status !== "failed", "disabled override edits displayed global route");
            check(Settings.data.bar.widgets.left[0].pinned.join(",") === "I4 captured tray", "disabled override global consumer");
            check(Settings.data.bar.screenOverrides[0].widgets.left[0].pinned.length === 0, "disabled override unchanged");
            Settings.data.bar.screenOverrides = [];
            failureCase();
          } catch (error) { root.fail(error); }
        });
      } catch (error) { root.fail(error); }
    }) === false, "route change refused");
  }

  function failureCase() {
    seed();
    capture();
    Settings.setBindingsUnresolved(true);
    check(tray.addToPinned(function(result) {
      try {
        check(result.status === "failed", "aggregate failure reported " + route);
        check(rows()[0].pinned.join(",") === "I4 captured tray", "failed save retains admitted pin " + route);
        Settings.setBindingsUnresolved(false);
        check(tray.addToPinned(function(retry) {
          try {
            check(retry.status !== "failed", "same captured session retry " + route);
            check(rows()[0].pinned.join(",") === "I4 captured tray", "retry does not duplicate pin " + route);
            saveCase();
          } catch (error) { root.fail(error); }
        }) === true, "retry admitted " + route);
      } catch (error) { root.fail(error); }
    }) === true, "failed-save pin admitted " + route);
  }

  function saveCase() {
    seed();
    capture();
    check(tray.addToPinned(function(result) {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "acknowledged pin " + route);
        check(rows()[0].pinned.join(",") === "I4 captured tray", "pin consumer " + route);
        check(rows()[0].opaque === "keep" && rows()[1].opaque === "sibling" && rows()[1].pinned.length === 0, "only explicit field changed " + route);
        check(tray.removeFromPinned(function(unpin) {
          try {
            check(unpin.status === "saved" || unpin.status === "nothing_to_save", "acknowledged unpin " + route);
            check(rows()[0].pinned.length === 0, "unpin consumer " + route);
            // Keep one pin on the final owning route for the cold witness.
            check(tray.addToPinned(function(finalResult) {
              try {
                check(finalResult.status !== "failed", "final pin receipt " + route);
                if (route === 0) {
                  route = 1;
                  staleCases();
                } else {
                  finalChecks();
                  console.log("I4_TRAY_COMMANDS: SAVED_PASS");
                  Qt.exit(0);
                }
              } catch (error) { root.fail(error); }
            }) === true, "final pin admitted " + route);
          } catch (error) { root.fail(error); }
        }) === true, "unpin admitted " + route);
      } catch (error) { root.fail(error); }
    }) === true, "pin admitted " + route);
    check(tray.removeFromPinned(function(result) {
      try { failed(result, "list-editor-busy", "competing command refused " + route); }
      catch (error) { root.fail(error); }
    }) === false, "busy refusal " + route);
  }

  function finalChecks() {
    check(Settings.data.bar.widgets.left[0].pinned.join(",") === "I4 captured tray", "global final consumer");
    check(rows()[0].pinned.join(",") === "I4 captured tray", "screen final consumer");
    check(rows()[0].opaque === "keep" && rows()[1].opaque === "sibling", "screen unknown fields");
    check(Settings.data.bar.screenOverrides[0].opaque === "monitor" && Settings.getBarWidgetsForScreen(testScreen.name).right[0].id === "I4 sibling", "monitor and section ancestry");
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_TRAY_COMMANDS: RESTART_PASS");
        Qt.exit(0);
      } else {
        Settings.data.bar.screenOverrides = [];
        staleCases();
      }
    } catch (error) { fail(error); }
  }

  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 120000
    running: true
    onTriggered: root.fail("tray commands watchdog")
  }
}
