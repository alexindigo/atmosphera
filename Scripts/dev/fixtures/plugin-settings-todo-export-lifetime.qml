// Explicit-context action lifetime over the actual common Todo Main owner.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("PHA_TODO_EXPORT_CASE")
  property bool started: false
  property var api: null
  property var main: null
  property var origin: null
  property var exportProcess: null
  property var notifications: []
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/todo/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: requestsFile
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
  }
  Component {
    id: contextFactory
    QtObject {
      property bool valid: true
      property var settingsView: ({})
      function current() {
        return valid;
      }
    }
  }
  Process {
    id: release
    command: ["python3", "-B", "-c", "from pathlib import Path; Path(" + JSON.stringify(root.casePath + "/hold") + ").unlink()"]
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notifications = root.notifications.concat([
                                                       {
                                                         title: title,
                                                         type: type
                                                       }
                                                     ]);
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("TODO_EXPORT_LIFE_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function requests() {
    requestsFile.reload();
    requestsFile.waitForJob();
    return requestsFile.text().trim().split("\n").filter(line => line.length).map(line => JSON.parse(line));
  }
  function findProcess(object) {
    if (object && object.command !== undefined && object.running !== undefined)
      return object;
    for (var child of object?.data || []) {
      var found = findProcess(child);
      if (found)
        return found;
    }
    return null;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "actual native content owner");
        api = Service.createPluginAPI("todo", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("todo", "main", component, root, api, {});
        check(main, "actual Main constructs");
        api.mainInstance = main;
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite lifetime deadline");
    if (phase === "ready" && !api._pendingSettingsSaves) {
      exportProcess = findProcess(main);
      check(exportProcess, "actual export Process");
      origin = contextFactory.createObject(root, {
                                             settingsView: {
                                               exportPath: casePath + "/missing/target",
                                               exportFormat: "json",
                                               exportEmptySections: false
                                             }
                                           });
      exportProcess.workingDirectory = casePath + "/missing-working-directory";
      check(main.doExportTodos(origin), "failed-start action admitted");
      phase = "start-failed";
    } else if (phase === "start-failed" && !exportProcess.running) {
      check(!main.exportBusy && notifications.length === 1 && notifications[0].type === "error", "failed-start settles request exactly once");
      exportProcess.workingDirectory = casePath;
      check(main.doExportTodos(origin), "same-origin Retry after failed start admitted");
      phase = "failed";
    } else if (phase === "failed" && !main.exportBusy) {
      check(notifications.length === 2 && notifications[1].type === "error", "failed publication is visible");
      origin.settingsView = {
        exportPath: casePath + "/export-held",
        exportFormat: "markdown",
        exportEmptySections: true
      };
      check(main.doExportTodos(origin), "same-origin explicit Retry admitted");
      phase = "held";
    } else if (phase === "held" && requests().length === 2) {
      check(main.exportBusy, "real export endpoint held");
      var path = main.currentExportPath;
      check(main.doExportTodos(api.settingsContext) === false && main.currentExportPath === path, "busy refusal preserves admitted request");
      check(notifications.length === 3 && notifications[2].title === api.tr("main.export_busy"), "busy refusal is visible");
      origin.settingsView = {
        exportPath: casePath + "/export-later",
        exportFormat: "json",
        exportEmptySections: false
      };
      main.rawTodos = [];
      main.rawPages = [];
      origin.valid = false;
      release.running = true;
      phase = "retired";
    } else if (phase === "retired" && !main.exportBusy && !release.running) {
      check(notifications.length === 3, "retired origin cannot acknowledge export feedback");
      check(main.doExportTodos(origin) === false && requests().length === 2, "retired origin cannot admit a new export");
      console.log("TODO_EXPORT_HELD " + JSON.stringify({
                                                         path: main.currentExportPath,
                                                         requests: requests(),
                                                         notifications: notifications
                                                       }));
      // The common owner is still usable; plugin-level/no-origin export remains explicit.
      main.rawTodos = api.pluginSettings.todos;
      main.rawPages = api.pluginSettings.pages;
      check(main.doExportTodos(), "plugin-level action admitted");
      phase = "shared";
    } else if (phase === "shared" && !main.exportBusy) {
      check(requests().length === 3 && notifications.length === 4 && notifications[3].type !== "error", "common plugin action completes once");
      check(main.currentExportPath.startsWith(casePath + "/export-shared/") && main.currentExportPath.endsWith(".md"), "no-origin export uses plugin policy");
      console.log("TODO_EXPORT_LIFETIME: PASS");
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
    interval: 50
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
  Component.onCompleted: begin()
}
