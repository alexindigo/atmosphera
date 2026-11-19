import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  property bool started: false
  property int callbacks: 0
  property bool waitingCleanup: false
  readonly property var screenObject: Quickshell.screens[0]
  QtObject {
    id: blocker
    function forceActiveFocus() {
    }
  }
  function check(value, label) {
    if (!value)
      throw new Error("SHORTCUT_REFUSAL_ASSERT: " + label);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function checked(callback) {
    return function (result) {
      try {
        callback(result);
      } catch (error) {
        root.fail(error);
      }
    };
  }
  function save(callback) {
    Settings.saveResult(checked(function (result) {
      check(result.status === "saved" || result.status === "nothing_to_save", "native publication acknowledged");
      callback();
    }));
  }
  function verify() {
    var rows = DesktopWidgetRegistry.getWidgetsForMonitor(screenObject.name);
    check(rows.length === 1 && rows[0].id === "Clock" && rows[0].opaque.keep, "unassigned shortcut removed, unrelated row preserved");
  }
  function start() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (Quickshell.env("SHORTCUT_COLD") === "1") {
        verify();
        console.log("SHORTCUT_REFUSAL: COLD_PASS");
        Qt.exit(0);
        return;
      }
      Settings.data.desktopWidgets.monitorWidgets = [
            {
              name: screenObject.name,
              widgets: [
                {
                  id: "Clock",
                  opaque: {
                    keep: true
                  }
                }
              ]
            }
          ];
      save(function () {
        check(DesktopWidgetRegistry.addWidget(screenObject.name, {
                                                id: "AppShortcut",
                                                appId: ""
                                              }, checked(function (result) {
                                                check(result.status === "admitted", "shortcut inserted");
                                                save(function () {
                                                  var rows = DesktopWidgetRegistry.getWidgetsForMonitor(screenObject.name);
                                                  check(rows.length === 2 && rows[1].id === "AppShortcut", "real new shortcut exists before refusal");
                                                  var editor = DesktopWidgetRegistry.createWidgetSettingsEditor(screenObject.name, 1);
                                                  check(editor !== null, "native captured cleanup editor");
                                                  DesktopWidgetRegistry.currentSettingsDialog = blocker;
                                                  DesktopWidgetRegistry.openWidgetSettings(screenObject, 1, "AppShortcut", rows[1], function (screen, index, id, captured) {
                                                    root.callbacks++;
                                                    check(captured !== null && captured !== undefined && root.callbacks === 1, "refused owner cleanup callback exactly once");
                                                    if (Quickshell.env("SHORTCUT_CAPTURED") === "1")
                                                      check(captured === editor, "injected cleanup editor preserved");
                                                    check(captured.removeIfUnassigned(), "real shortcut cleanup submitted");
                                                    root.waitingCleanup = true;
                                                  }, undefined, undefined, undefined, undefined, Quickshell.env("SHORTCUT_CAPTURED") === "1" ? editor : undefined);
                                                });
                                              })), "real shortcut insert submitted");
      });
    } catch (error) {
      fail(error);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.start();
    }
  }
  Component.onCompleted: start()
  Timer {
    interval: 30
    running: root.waitingCleanup
    repeat: true
    onTriggered: {
      if (DesktopWidgetRegistry.getWidgetsForMonitor(root.screenObject.name).length !== 1)
        return;
      root.waitingCleanup = false;
      try {
        root.verify();
        root.save(function () {
          root.check(root.callbacks === 1, "no duplicate cleanup");
          console.log("SHORTCUT_REFUSAL: SAVED_PASS");
          Qt.exit(0);
        });
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: root.fail("SHORTCUT_REFUSAL_ASSERT: callback missing " + root.callbacks)
  }
}
