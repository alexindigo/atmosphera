// Inert entrypoint copied to the candidate config root by the VM driver.
// Calls production components/services, then saves and verifies in a cold process.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Modules.Bar.Extras as Extras
import qs.Modules.Panels.Settings.Bar as BarSettings
import qs.Modules.Panels.Settings.Tabs.Audio as AudioSettings

Item {
  id: root
  readonly property var testScreen: Quickshell.screens[0]
  property bool started: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"

  BarSettings.MonitorWidgetsConfig {
    id: monitor
    screen: root.testScreen
  }
  AudioSettings.MediaSubTab {
    id: media
  }
  Extras.TrayMenu {
    id: tray
    shellScreen: root.testScreen
    widgetSection: "left"
    widgetIndex: 0
    trayItem: ({"tooltipTitle": "I4 synthetic tray", "menu": null})
  }

  function check(ok, name) {
    if (!ok)
      throw new Error("I4_CONSUMER_ASSERT: " + name);
  }

  function screenWidgets() {
    return Settings.getBarWidgetsForScreen(testScreen.name);
  }

  function finalChecks() {
    check(Settings.data.audio.mprisBlacklist.join(",") === "alpha,gamma", "blacklist owner");
    check(screenWidgets().left[0].id === "Tray" && screenWidgets().left[0].pinned.length === 0, "tray unpin owner");
    check(screenWidgets().left[0].compact === true && screenWidgets().left[0].opaque === "keep", "screen dialog patch");
    check(Settings.data.bar.widgets.left[0].compact === true && Settings.data.bar.widgets.left[0].opaque === "keep", "global dialog patch");
    check(Settings.data.bar.widgets.right.length === 0 && screenWidgets().right.length === 0, "plugin removals");
    check(Settings.data.desktopWidgets.monitorWidgets[0].widgets.length === 1, "desktop removal");
    check(Settings.data.desktopWidgets.monitorWidgets[0].opaque === "monitor" && Settings.data.desktopWidgets.monitorWidgets[0].widgets[0].opaque === "widget", "desktop ancestry retained");
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        finalChecks();
        console.log("I4_CONSUMER_COPIES: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      Settings.data.bar.widgets.left = [{"id": "Tray", "pinned": [], "opaque": "keep"}];
      Settings.data.bar.widgets.center = [];
      Settings.data.bar.widgets.right = [];
      Settings.data.bar.screenOverrides = [];
      Settings.data.audio.mprisBlacklist = ["alpha", "beta", "gamma"];
      Settings.data.desktopWidgets.monitorWidgets = [{"name": "offline", "opaque": "monitor", "widgets": [{"id": "plugin:i4-keep", "opaque": "widget"}, {"id": "plugin:i4-remove"}]}];

      var copy = monitor._getWidgetsContainer();
      check(Object.keys(copy).sort().join(",") === "center,left,right", "namespace copy contains only declared data leaves");
      copy.right.push({"id": "unpublished"});
      check(!Settings.hasScreenOverride(testScreen.name, "widgets"), "copy getter creates no choice");
      check(Settings.data.bar.widgets.right.length === 0, "copy getter does not alias global");
      monitor._addWidgetToSection("I4-A", "right");
      monitor._addWidgetToSection("I4-B", "right");
      monitor._reorderWidgetInSection("right", 0, 1);
      check(screenWidgets().right[0].id === "I4-B", "monitor reorder");
      monitor._updateWidgetSettingsInSection("right", 0, {"id": "I4-B", "opaque": "updated"});
      monitor._moveWidgetBetweenSections("right", 0, "center");
      check(screenWidgets().center[0].opaque === "updated" && screenWidgets().right[0].id === "I4-A", "monitor atomic move");
      monitor._removeWidgetFromSection("center", 0);
      monitor._removeWidgetFromSection("right", 0);
      BarService.updateWidgetSettings("", "left", 0, {"compact": true});
      BarService.updateWidgetSettings(testScreen.name, "left", 0, {"compact": true});
      tray.addToPinned(function(pin) {
        try {
          check(pin.status !== "failed", "tray pin receipt");
          check(screenWidgets().left[0].pinned[0] === "I4 synthetic tray", "tray pin owner");
          tray.removeFromPinned(function(unpin) {
            try {
              check(unpin.status !== "failed", "tray unpin receipt");
              root.finishOtherWriters();
            } catch (error) { root.fail(error); }
          });
        } catch (error) { root.fail(error); }
      });
    } catch (error) { fail(error); }
  }

  function finishOtherWriters() {
    try {
      media.removeBlacklistedPlayer("beta");
      check(Service.addWidgetToBar("plugin:i4-added", "right"), "plugin add command");
      check(Settings.data.bar.widgets.right[0].id === "plugin:i4-added" && screenWidgets().right[0].id === "plugin:i4-added", "plugin global and screen add");
      Settings.saveImmediate(function(result) {
        try {
          // I4 deliberately exercises the active old owner's Boolean callback.
          // I5 must port this witness with the facade's structured receipt API.
          check(result === true, "add receipt");
          check(Service.removeWidgetFromBar("plugin:i4-added"), "plugin remove command");
          check(Service.removePluginDesktopWidgetsFromSettings("i4-remove"), "desktop remove command");
          Settings.saveImmediate(function(finalResult) {
            try {
              check(finalResult === true, "final receipt");
              finalChecks();
              console.log("I4_CONSUMER_COPIES: SAVED_PASS");
              Qt.exit(0);
            } catch (error) { root.fail(error); }
          });
        } catch (error) { root.fail(error); }
      });
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
    // Several real controls enqueue full old-owner saves before our fence. This
    // is a functional witness, not I6's separate GUI-thread timing gate.
    interval: 90000
    running: true
    onTriggered: root.fail("I4 consumer watchdog")
  }
}
