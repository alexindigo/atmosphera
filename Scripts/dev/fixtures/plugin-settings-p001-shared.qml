// Actual Todo shared page on the field-only capability, not catalog proof.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var main: null
  property var result: null
  readonly property bool cold: Quickshell.env("PHA_TODO_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }
  PanelWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: function (receipt) {
        root.result = receipt;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("P001_SHARED_ASSERT: " + message);
  }
  function contents() {
    check(main.rawTodos.length === 2 && main.rawTodos[0].id === 1, "Main tasks remain");
    check(api.pluginSettings.todos.length === 2 && api.pluginSettings.current_page_id === 7, "shared content remains");
    check(api.pluginSettings.count === 2 && api.pluginSettings.completedCount === 0, "operational counters remain");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "native shared owner");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/" + manifest.entryPoints.main);
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("todo", "main", component, root, api, {});
        api.mainInstance = main;
        contents();
        if (cold) {
          check(api.pluginSettings.pages[1].name === "Renamed" && api.pluginSettings.exportEmptySections, "cold shared outcome");
          console.log("P001_SHARED: COLD_PASS");
          Qt.exit(0);
          return;
        }
        check(popup.openPluginSettings(manifest, "settings"), "shared popup request");
        phase = "page";
      } catch (error) {
        fail(error);
      }
    });
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function drive() {
    if (phase === "page" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.scopeKind === "plugin" && popup.settingsPage.sharedContent, "shared page opens with correct scope");
      check(!popup.dirty && !popup._editor.dirty, "opening submits no intent");
      check(popup.requestClose(), "untouched shared Close nonpublishing");
      phase = "reopen";
    } else if (phase === "reopen" && !popup.visible) {
      check(popup.openPluginSettings(api.manifest, "settings"), "reopen shared page");
      phase = "config";
    } else if (phase === "config" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.field("exportEmptySections").set(true), "explicit shared configuration field intent");
      check(popup.applySettings(), "selected config Apply");
      phase = "config-result";
    } else if (phase === "config-result" && result && !popup.busy) {
      check(result.status === "saved" && result.refreshState === "current", "accepted config receipt");
      contents();
      check(api.pluginSettings.pages[1].name === "Synthetic", "config Apply does not gather pages");
      check(popup.settingsPage.renamePage(7, "Renamed"), "explicit shared content command");
      result = null;
      check(popup.applySettings(), "explicit content Apply");
      phase = "content-result";
    } else if (phase === "content-result" && result && !popup.busy && api.pluginSettings.pages[1].name === "Renamed") {
      check(result.status === "saved" && result.refreshState === "current", "accepted content receipt");
      contents();
      check(popup._pageApi.contentField("pages").pendingIntent === "" && !popup.settingsPage.namesPending, "acknowledged content intents consumed");
      check(popup.requestClose(), "shared Close after current save");
      console.log("P001_SHARED: PASS");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("shared watchdog " + phase)
  }
  Component.onCompleted: begin()
}
