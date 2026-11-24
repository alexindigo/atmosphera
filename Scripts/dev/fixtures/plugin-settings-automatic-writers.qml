import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_AUTO_CASE")
  property var api: null
  property var selected: null
  property var main: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property string next: ""
  FileView {
    id: manifest
    path: root.base + "/config/plugins/2-in-1-tools/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: root.base + "/config/plugins/2-in-1-tools/i18n/en.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete independent native restore documents");
      else
        root.phase = root.next;
    }
  }
  Process {
    id: change
    onExited: code => {
      root.check(code === 0, "fixture state change");
      root.main.refreshTabletModeState();
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("AUTOMATIC_WRITERS_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function probe(boundary, after) {
    next = after;
    phase = "disk";
    disk.command = ["python3", "-B", base + "/disk.py", base, Quickshell.env("PHA_AUTO_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function state(value) {
    change.command = ["python3", "-c", "from pathlib import Path;import sys;Path(sys.argv[1]).write_text(sys.argv[2])", base + "/tablet-state", value];
    change.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "2-in-1-tools": descriptor
    };
    Service._openSettingsOwner("2-in-1-tools", owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI("2-in-1-tools", descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          "2-in-1-tools": {
            api: api
          }
        };
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("2-in-1-tools", "main", component, content, api, {});
        api.mainInstance = main;
        selected = PluginInstances.apiFor("2-in-1-tools", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "begin")
      return;
    check(Date.now() - since < 18000, "finite native writer phase");
    if (phase === "ready" && selected?.settingsReady && main.compositorBackend === "niri")
      probe("initial", "activate");
    else if (phase === "activate") {
      check(main.activatePolicy(selected.settingsContext), "select placement");
      state("on");
      phase = "active";
    } else if (phase === "active" && Date.now() - since > 1400) {
      check(main._tabletModeDetected && Settings.data.bar.density === "comfortable" && Settings.data.dock.dockType === "exclusive" && Settings.data.dock.enabled, "selected policy changes singular shell bar and dock");
      check(api.pluginSettings.lastNonTabletBarDensity === "compact" && api.pluginSettings.lastNonTabletDockType === "floating" && api.pluginSettings.lastNonTabletDockEnabled === false, "restore state uses shared operational native writer");
      probe("active", "leave");
    } else if (phase === "leave") {
      state("off");
      phase = "restoring";
    } else if (phase === "restoring" && Date.now() - since > 1400) {
      check(!main._tabletModeDetected && Settings.data.bar.density === "compact" && Settings.data.dock.dockType === "floating" && !Settings.data.dock.enabled, "desktop restoration reaches actual shell consumer");
      probe("restored", "finish");
    } else if (phase === "finish") {
      console.log("AUTOMATIC_WRITERS: PASS");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    interval: 30
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
