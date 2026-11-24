import Qt.labs.folderlistmodel
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  property bool started: false
  property var api: null
  property var target: null
  property var thumbnails: null
  property var main: null
  property var heldScreenCallback: null
  property var obsoleteScreenCallback: null
  property string phase: "owner"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string afterDisk: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/mpvpaper/manifest.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  FolderListModel {
    id: emptyFolder
    folder: "file://" + root.base + "/empty-folder"
    showDirs: false
  }
  Item {
    id: content
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete native MPV documents differ");
      else
        root.phase = root.afterDisk;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_MPV_LIFETIME_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function probe(boundary, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WALLPAPER_DISK"), base, Quickshell.env("PHA_WALLPAPER_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    const descriptor = JSON.parse(manifest.text());
    Registry.installedPlugins = {
      mpvpaper: descriptor
    };
    Service._openSettingsOwner("mpvpaper", owner => {
      try {
        check(owner, "actual native shared cache owner");
        api = Service.createPluginAPI("mpvpaper", descriptor, owner, {}, {}, {});
        Service.loadedPlugins = {
          mpvpaper: {
            api: api
          }
        };
        // Hold the screen-detector collaborator, never the native preference API.
        api.withCurrentScreen = function (callback) {
          root.heldScreenCallback = callback;
        };
        target = PluginInstances.apiFor("mpvpaper", {
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
    check(Date.now() - since < 18000, "finite MPV lifetime phase deadline");
    if (phase === "ready" && target.settingsReady && emptyFolder.status === FolderListModel.Ready)
      probe("initial", "construct");
    else if (phase === "construct") {
      const component = Qt.createComponent("file://" + api.pluginDir + "/main/Thumbnails.qml");
      check(component.status === Component.Ready, component.errorString());
      thumbnails = component.createObject(content, {
                                            pluginApi: api,
                                            currentWallpaper: base + "/original-color.mp4",
                                            thumbCacheReady: false,
                                            folderModel: emptyFolder
                                          });
      check(thumbnails, "actual shared thumbnail/cache owner");
      thumbnails.thumbGeneration();
      phase = "published";
    } else if (phase === "published" && api.pluginSettings.thumbCacheReady) {
      phase = "saving";
      Service.waitForPluginSaves(api, result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "shared cache native publication");
          probe("ready", "color");
        } catch (error) {
          fail(error);
        }
      }, false);
    } else if (phase === "color") {
      thumbnails.startColorGen(target.settingsContext, base + "/original-color.mp4");
      thumbnails.currentWallpaper = base + "/replacement-color.mp4";
      phase = "held-color";
    } else if (phase === "held-color" && heldScreenCallback) {
      const callback = heldScreenCallback;
      heldScreenCallback = null;
      callback(Quickshell.screens[0]);
      phase = "captured";
    } else if (phase === "captured" && rows().length === 1 && heldScreenCallback) {
      const command = rows()[0].argv;
      check(command[command.indexOf("-i") + 1] === base + "/original-color.mp4", "delayed color retains admitted source path");
      obsoleteScreenCallback = heldScreenCallback;
      heldScreenCallback = null;
      thumbnails.startColorGen(target.settingsContext, base + "/obsolete-color.mp4");
      phase = "replacement-callback";
    } else if (phase === "replacement-callback" && heldScreenCallback) {
      check(rows().length === 1, "queued callbacks do not run themselves");
      obsoleteScreenCallback(Quickshell.screens[0]);
      obsoleteScreenCallback = null;
      check(rows().length === 1, "obsolete callback cannot launch replacement request");
      phase = "held-retirement";
    } else if (phase === "held-retirement" && heldScreenCallback) {
      const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
      check(component.status === Component.Ready, component.errorString());
      main = component.createObject(content, {
                                      pluginApi: api
                                    });
      check(main && main.registerRuntime(target), "actual Main registers native placement before retirement");
      const entries = Settings.store.copyValue(Settings.data.bar.widgets.left);
      entries[0].id = "plugin:retired-wallpaper";
      Settings.data.bar.widgets.left = entries;
      Settings.saveSelected([["bar", "widgets", "left"]], result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "native retirement");
          phase = "retired";
        } catch (error) {
          fail(error);
        }
      });
      phase = "retiring";
    } else if (phase === "retired" && !target.settingsContext.current()) {
      const callback = heldScreenCallback;
      heldScreenCallback = null;
      callback(Quickshell.screens[0]);
      phase = "retired-drain";
    } else if (phase === "retired-drain" && Date.now() - since > 250) {
      check(rows().length === 1, "retired delayed callback cannot reach physical color endpoint");
      PluginInstances._dropPlugin("mpvpaper");
      phase = "retired-api";
    } else if (phase === "retired-api" && Date.now() - since > 150) {
      check(main.activatePolicy(api.settingsContext), "shared policy can be reselected after registered API destruction");
      check(main.runtimeWriter === api, "destroyed placement cannot poison shared writer lookup");
      probe("retired", "finish");
    } else if (phase === "finish") {
      console.log("WALLPAPER_MPV_LIFETIME: PASS");
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
    interval: 35
    running: true
    repeat: true
    onTriggered: {
      try {
        if (root.started)
          root.drive();
        else
          root.begin();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
