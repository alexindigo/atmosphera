// P001 characterization: actual released host, Todo page, Main and desktop.
// All plugin code and preference files belong to this fresh guest case.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings.DesktopWidgets
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var instanceApi: null
  property var main: null
  property var desktop: null
  property int confirmedSaves: 0
  readonly property bool cold: Quickshell.env("PHA_RED_COLD") === "1"
  readonly property var placement: ({kind: "desktop", screenName: Quickshell.screens[0].name, index: 0})

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }

  function check(condition, message) {
    if (!condition)
      throw new Error("P001_RED_ASSERT: " + message);
  }

  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }

  function construct(entry, parent, context) {
    var url = "file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry];
    var component = Qt.createComponent(url);
    check(component.status === Component.Ready, entry + " compiles: " + component.errorString());
    var item = PluginLoader.createObject("todo", entry, component, parent,
                                         entry === "desktopWidget" ? instanceApi : api, context);
    check(item !== null, entry + " constructed through real loader");
    return item;
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    // Only fixture registration is supplied; schema, store, API and components
    // are the real production implementations.
    Registry.installedPlugins = {todo: manifest};
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "native Todo owner opened");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {todo: {api: api}};
        check(api.pluginSettings.todos.length === (cold ? 0 : 2)
              && api.pluginSettings.pages.length === (cold ? 1 : 2),
              cold ? "separate cold owner sees persisted loss" : "seeded content exists before host opens");
        main = construct("main", root, {});
        api.mainInstance = main;
        if (cold) {
          instanceApi = PluginInstances.apiFor("todo", placement);
          check(instanceApi !== null, "cold selected desktop API");
          phase = "cold-runtime";
          return;
        }
        Settings.data.desktopWidgets.monitorWidgets = [{name: placement.screenName, widgets: [{id: "plugin:todo"}]}];
        Settings.saveSelected([["desktopWidgets", "monitorWidgets"]], function (receipt) {
          try {
            check(receipt.status !== "failed", "desktop placement persisted");
            instanceApi = PluginInstances.apiFor("todo", placement);
            check(instanceApi !== null, "real selected desktop API");
            phase = "runtime";
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }

  function drive() {
    if (phase === "cold-runtime" && instanceApi.settingsReady) {
      desktop = construct("desktopWidget", host.contentItem,
                          {screen: Quickshell.screens[0], widgetData: {id: "plugin:todo"}, widgetIndex: 0});
      check(main.rawTodos.length === 0 && desktop.rawTodos.length === 0,
            "cold Main and desktop independently see persisted loss");
      console.log("RED_CONTROL P001: COLD_REPRODUCED");
      Qt.exit(0);
    } else if (phase === "runtime" && instanceApi.settingsReady) {
      desktop = construct("desktopWidget", host.contentItem,
                          {screen: Quickshell.screens[0], widgetData: {id: "plugin:todo"}, widgetIndex: 0});
      check(main.rawTodos.length === 2 && desktop.rawTodos.length === 2,
            "Main and actual desktop see seeded tasks");
      check(host.showDialog(dialog), "actual popup presentation admitted");
      dialog.open();
      phase = "page";
    } else if (phase === "page" && dialog.opened) {
      // No interaction, field edit, dirty predicate or page method is injected.
      // This is the real host's public Close action.
      check(api.pluginSettings.todos.length === 2, "opening alone did not remove tasks");
      confirmedSaves = 0;
      dialog.saveAndClose();
      phase = "closed";
    } else if (phase === "closed" && confirmedSaves > 0 && api.pluginSettings.todos.length === 0
               && main.rawTodos.length === 0 && desktop.rawTodos.length === 0) {
      check(api.pluginSettings.pages.length === 1 && api.pluginSettings.current_page_id === 0,
            "untouched old fallback replaced shared pages and current page");
      console.log("RED_CONTROL P001: REPRODUCED (untouched Close, actual native save, Main and desktop lost seeded tasks)");
      Qt.exit(0);
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) {
      if (phase === "closed" && pluginId === "todo" && result.status !== "failed")
        confirmedSaves++;
    }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    DesktopWidgetSettingsDialog {
      id: dialog
      parent: host.dialogParent
      widgetId: "plugin:todo"
      widgetIndex: 0
      widgetData: ({id: "plugin:todo"})
      screen: Quickshell.screens[0]
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try { root.drive(); } catch (error) { root.fail(error); }
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("P001_RED_ASSERT: watchdog at " + root.phase)
  }
  Component.onCompleted: begin()
}
