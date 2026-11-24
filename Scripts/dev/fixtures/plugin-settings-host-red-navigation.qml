// G81.generic: external service navigation destroys the actual dirty generic
// settings page, although that page's direct Close correctly refuses.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var page: null
  property var popup: null
  property bool pageDestroyed: false
  property bool popupDestroyed: false
  property int completed: 0

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function check(condition, message) {
    if (!condition) throw new Error("G81_GENERIC_RED_ASSERT: " + message);
  }
  // Diagnostic: observe the failing fixture call site, add its JS stack only
  // here, and retain it as value-free failure evidence (no product edit).
  function fail(error) { console.error(String(error) + "\n" + (error.stack || "")); Qt.exit(2); }
  function find(item, predicate, seen) {
    if (!item) return null;
    seen = seen || [];
    if (seen.indexOf(item) !== -1) return null;
    seen.push(item);
    if (predicate(item)) return item;
    // Popup objects are in data, rather than the visual children list. Tests
    // observe that actual presentation; no production hook or page replacement.
    var entries = item.data || item.children || [];
    for (var i = 0; i < entries.length; ++i) {
      var result = find(entries[i], predicate, seen);
      if (result) return result;
    }
    return null;
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {todo: manifest};
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "native Todo owner opened");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {todo: {api: api}};
        Settings.data.desktopWidgets.enabled = true;
        Settings.data.ui.settingsPanelMode = "window";
        Settings.data.desktopWidgets.monitorWidgets = [{name: Quickshell.screens[0].name, widgets: [{id: "plugin:todo"}]}];
        Settings.saveSelected([["desktopWidgets"], ["ui", "settingsPanelMode"]], function (receipt) {
          try {
            check(receipt.status !== "failed", "fixture placement and presentation persisted");
            SettingsPanelService.openToTab(SettingsPanel.Tab.DesktopWidgets);
            phase = "tab";
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function drive() {
    if (phase === "tab" && window.visible) {
      var tab = find(window.contentItem, function (item) { return typeof item._openInstanceSettings === "function"; });
      if (!tab) return;
      popup = find(tab, function (item) { return typeof item.openInstanceSettings === "function"; });
      check(popup !== null, "actual DesktopWidgetsTab generic popup");
      popup.Component.destruction.connect(function () { root.popupDestroyed = true; });
      tab._openInstanceSettings(api.manifest, "settings", Quickshell.screens[0].name, 0);
      phase = "page";
    } else if (phase === "page" && popup.visible && popup.settingsPage) {
      page = popup.settingsPage;
      page.Component.destruction.connect(function () { root.pageDestroyed = true; });
      check(page.valueShowCompleted === true, "configuration baseline");
      var toggle = find(page, function (item) { return item.label === api.tr("settings.show_completed.label") && typeof item.toggled === "function"; });
      check(toggle !== null, "actual page toggle");
      toggle.toggled(false);
      check(page.settingsDirty && page.valueShowCompleted === false, "actual control intent leaves local unsaved configuration");
      check(popup.requestClose() === false && popup.discardPending, "direct Close refuses dirty page");
      popup.keepEditing();
      check(popup.visible && popup.settingsPage === page, "Keep editing preserves original page");
      SettingsPanelService.openToTab(SettingsPanel.Tab.General);
      phase = "navigated";
    } else if (phase === "navigated" && pageDestroyed && popupDestroyed) {
      check(completed === 0, "neither acknowledged Apply nor discard was requested");
      check(api.pluginSettings.showCompleted === true && api.pluginSettings.todos.length === 2,
            "live consumer retains saved configuration while unsaved input was destroyed");
      console.log("RED_CONTROL G81.generic: REPRODUCED (external SettingsPanelService navigation destroyed dirty page without admission)");
      Qt.exit(0);
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) { if (pluginId === "todo") root.completed++; }
  }
  SettingsPanelWindow { id: window }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } }
  }
  Timer { interval: 45000; running: true; onTriggered: root.fail("watchdog at " + root.phase); }
  Component.onCompleted: begin()
}
