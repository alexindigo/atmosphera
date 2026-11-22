import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_OUTPUT_CASE")
  readonly property string plugin: Quickshell.env("PHA_OUTPUT_PLUGIN")
  property var main: null
  property var panel: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  QtObject {
    id: sharedApi
    property var manifest: ({
                              metadata: {
                                defaultSettings: {
                                  niriConfigPath: root.base + "/Shared.kdl",
                                  backend: "sway",
                                  swayCommand: root.base + "/bin/shared-output",
                                  hyprctlCommand: root.base + "/bin/shared-output",
                                  gridSize: 40,
                                  snapToGrid: true
                                }
                              }
                            })
    property var pluginSettings: manifest.metadata.defaultSettings
    property var settingsContext: sharedContext
    property var mainInstance: root.main
    function tr(key, values) {
      return key;
    }
  }
  QtObject {
    id: selectedApi
    property var manifest: sharedApi.manifest
    property var pluginSettings: ({
                                    niriConfigPath: root.base + "/Selected.kdl",
                                    backend: "hyprland",
                                    swayCommand: root.base + "/bin/selected-output",
                                    hyprctlCommand: root.base + "/bin/selected-output",
                                    gridSize: 25,
                                    snapToGrid: true
                                  })
    property var settingsContext: selectedContext
    property var mainInstance: root.main
    function tr(key, values) {
      return key;
    }
  }
  QtObject {
    id: sharedContext
    readonly property var settingsView: sharedApi.pluginSettings
    function current() {
      return true;
    }
  }
  QtObject {
    id: selectedContext
    property bool alive: true
    readonly property var settingsView: selectedApi.pluginSettings
    function current() {
      return alive;
    }
  }
  Item {
    id: content
    width: 1400
    height: 900
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OUTPUT_RUNTIME_ASSERT: " + message);
  }
  function create(name, api) {
    const component = Qt.createComponent("file://" + base + "/plugin/" + name + ".qml");
    check(component.status === Component.Ready, component.errorString());
    const object = component.createObject(content, {
                                            pluginApi: api
                                          });
    check(object, "actual " + name + " constructs");
    return object;
  }
  function findText(object, text, seen) {
    if (!object)
      return false;
    seen = seen || new Set();
    if (seen.has(object))
      return false;
    seen.add(object);
    if (object.text === text)
      return true;
    for (const list of [object.data, object.children]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (const child of list)
        if (findText(child, text, seen))
          return true;
    }
    return false;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    main = create("Main", sharedApi);
    panel = create("Panel", selectedApi);
    phase = "initial";
  }
  function drive() {
    if (phase === "begin")
      return;
    check(Date.now() - since < 18000, "finite output phase " + phase);
    if (phase === "initial") {
      if ((plugin === "display-settings" ? main.loading : main.isRefreshing) || Date.now() - since < 300)
        return;
      if (plugin === "display-settings")
        main.refresh(selectedContext);
      else
        main.refreshOutputs(selectedContext);
      phase = "selected";
    } else if (phase === "selected") {
      if ((plugin === "display-settings" ? panel.loading : main.isRefreshing) || Date.now() - since < 300)
        return;
      if (plugin === "display-settings") {
        check(panel.niriOutputs.length === 1 && panel.niriOutputs[0].name === "Selected" && findText(panel, "Selected"), "selected config path reaches actual Panel card");
        console.log("OUTPUT_RUNTIME: PASS " + plugin);
        Qt.exit(0);
      } else {
        check(main.draftOutputs.length === 1 && main.draftOutputs[0].name === "Selected", "selected backend reaches shared draft layout");
        panel.editPosX = "61";
        panel.editPosY = "74";
        panel.applyTypedPosition();
        check(main.draftOutputs[0].x === 50 && main.draftOutputs[0].y === 75, "actual Panel edit uses selected grid policy");
        check(findText(panel, "Selected"), "selected output reaches actual Panel child Text");
        main.applyLayout(selectedContext);
        phase = "applied";
      }
    } else if (phase === "applied" && !main.isApplying && !main.isRefreshing && Date.now() - since > 300) {
      check(main.errorText === "", "inert selected output apply and follow-up");
      console.log("OUTPUT_RUNTIME: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {
    onReadyChanged: if (ready)
                      root.begin()
  }
  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Component.onCompleted: begin()
}
