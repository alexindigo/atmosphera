import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: root
        property var api: null
        property var items: ({})
        property int receipts: 0
        property var lastReceipt: null
        property string phase: "open"
        property bool started: false
        property bool automationSeen: false
        property bool mpvVolumeObserved: false
        property var mpvClampReceipt: null
        property int oldWallpaperSignals: 0
        property double startupDeadline: 0
        property var thumbnailControl: ({calls: 0})
        readonly property string name: Quickshell.screens[0].name
        readonly property string mode: Quickshell.env("I5_VIDEO_MODE")
        readonly property string directory: Settings.configDir + "plugins/video-wallpaper"
        readonly property var manifest: JSON.parse(Quickshell.env("I5_VIDEO_MANIFEST"))
        Component { id: pageApiFactory; PluginSettingsPageApi {} }
        function check(ok, label) { if (!ok) throw new Error("I5_VIDEO_RUNTIME_ASSERT: " + phase + " " + label); }
        function record(name) { return Object.getOwnPropertyDescriptor(api.pluginSettings.monitors || {}, name)?.value; }
        function component(path, properties) {
          var source = Qt.createComponent("file://" + directory + "/" + path, Component.PreferSynchronous);
          check(source.status === Component.Ready, path + " loads: " + source.errorString());
          var item = source.createObject(root, properties);
          check(item !== null, path + " constructed");
          return item;
        }
        function pass() { console.log("I5_VIDEO_RUNTIME: PASS " + mode); Qt.exit(0); }
        function saveNext(next) { phase = next; api.saveSettings(); }
        function begin() {
          if (started || !Settings.isLoaded) return;
          started = true;
          Service._openSettingsOwner("video-wallpaper", function (owner) {
            try {
              check(owner !== null, "native video owner opens");
              api = Service.createPluginAPI("video-wallpaper", manifest, owner, {}, {}, {});
              var loaded = Object.assign({}, Service.loadedPlugins); loaded["video-wallpaper"] = {api: api}; Service.loadedPlugins = loaded;
              var nativeSave = api.saveSettings;
              api.saveSettings = function (callback) {
                return nativeSave(function (result) {
                  root.lastReceipt = result; root.receipts++;
                  if (root.phase === "mpv-clamp") root.mpvClampReceipt = result;
                  if (typeof callback === "function") callback(result);
                });
              };
              if (mode === "cold") {
                check(record(name).currentWallpaper === "settings-choice" && record("__proto__").volume === 0.625, "cold consumers see saved choices");
                pass(); return;
              }
              if (mode === "reset-cold") {
                check(record(name).currentWallpaper === "legacy-choice", "cold reset reveals preserved historical record");
                pass(); return;
              }
              if (mode === "empty") {
                check(Object.keys(api.pluginSettings.monitors).length === 0, "explicit empty map shadows legacy");
                pass(); return;
              }
              check(record(name).currentWallpaper === "legacy-choice", "worker projects historical screen record");
              if (mode === "startup" || mode === "startup-enabled") {
                WallpaperService.init(); phase = "startup-service"; return;
              }
              if (mode === "reset" || mode === "namespace-reset") {
                api.pluginSettings.monitors = {};
                api.saveSettings(function (result) {
                  try {
                    check(result.status === "saved", "explicit empty map saved");
                    check(Object.keys(api.pluginSettings.monitors).length === 0, "present empty map shadows historical records");
                    owner.store.reset(mode === "reset" ? ["settings", "monitors"] : ["settings"], "user", function (reset) {
                      try {
                        check(reset.status !== "failed", "native reset admitted");
                        api.saveSettings(function (saved) {
                          try {
                            check(saved.status === "saved", "reset save receipt");
                            check(record(name).currentWallpaper === "legacy-choice", "reset reveals historical record in-session");
                            pass();
                          } catch (error) { console.error(String(error)); Qt.exit(2); }
                        });
                      } catch (error) { console.error(String(error)); Qt.exit(2); }
                    });
                  } catch (error) { console.error(String(error)); Qt.exit(2); }
                });
                return;
              }
              items.timer = component("common/SaveTimer.qml", {pluginApi: api, screenName: name});
              items.timer.completed.connect(function (result) {
                if (mode !== "timer-failure") return;
                try {
                  check(result.status === "failed" && items.timer.failed && items.timer._pending !== null, "failed timer receipt retains captured work");
                  check(record(name).volume === 0.375, "failed publication retains runtime input");
                  pass();
                } catch (error) { console.error(String(error)); Qt.exit(2); }
              });
              if (mode === "timer-failure") {
                phase = "timer-failure"; items.timer.save("volume", 0.375); items.timer.screenName = "caller-mutated"; return;
              }
              if (mode === "inner" || mode === "inner-failure") {
                WallpaperService.init();
                items.thumbFolder = component("common/FolderModel.qml", {folder: Quickshell.env("I5_VIDEO_THUMBS")});
                phase = "inner-availability"; return;
              }
              if (["thumbnails", "thumbnail-failure", "thumbnail-generation", "thumbnail-retry"].indexOf(mode) !== -1) {
                api.pluginSettings.wallpapersFolder = Quickshell.env("I5_VIDEO_MEDIA_DIR");
                items.folder = component("common/FolderModel.qml", {folder: Quickshell.env("I5_VIDEO_MEDIA_DIR"), filters: ["*.mp4"]});
                items.thumbFolder = component("common/FolderModel.qml", {folder: Quickshell.env("I5_VIDEO_THUMBS"), filters: ["*.bmp"]});
                items.thumbnails = component("main/Thumbnails.qml", {pluginApi: api, folderModel: items.folder, thumbFolderModel: items.thumbFolder,
                  thumbCacheFolderPath: Quickshell.env("I5_VIDEO_THUMBS"), getThumbPath: function () { return Quickshell.env("I5_VIDEO_THUMBS") + "/media.bmp"; }});
                phase = mode; return;
              }
              items.folder = component("common/FolderModel.qml", {folder: ""});
              items.functions = component("main/Functions.qml", {pluginApi: api, folderModel: items.folder});
              items.ipc = component("main/IPC.qml", {pluginApi: api, random: function () {}, clear: function () {}, setWallpaper: items.functions.setWallpaper});
              items.tools = component("common/ToolRow.qml", {pluginApi: api, screenName: name});
              items.bar = component("BarWidget.qml", {pluginApi: api, screen: Quickshell.screens[0]});
              items.panel = component("panel/PerScreenPanel.qml", {pluginApi: api, screenName: name, thumbCacheReady: false, folderModel: items.folder});
              if (mode === "mpv-volume") {
                api.pluginSettings.mpvSocket = Quickshell.env("I5_VIDEO_SOCKET");
                items.mpv = component("main/Mpvpaper.qml", {pluginApi: api, screenData: Quickshell.screens[0], screenName: name,
                  screenWidth: Quickshell.screens[0].width, screenHeight: Quickshell.screens[0].height});
                items.functions.setWallpaper(Quickshell.env("I5_VIDEO_MEDIA"), name);
                api.pluginSettings.enabled = true;
                saveNext("mpv-await"); return;
              }
              var screen = Quickshell.screens[0];
              items.mpv = component("main/Mpvpaper.qml", {pluginApi: api, screenData: screen, screenName: name, screenWidth: screen.width, screenHeight: screen.height});
              items.multimedia = component("main/VideoWallpaper.qml", {pluginApi: api, screenData: screen, screenName: name, screenWidth: screen.width, screenHeight: screen.height});
              items.automation = component("main/Automation.qml", {pluginApi: api});
              items.automation.random.connect(function (selected) { if (selected === root.name) root.automationSeen = true; });
              phase = "functions";
              items.functions.setWallpaper("function-choice", name);
            } catch (error) { console.error(String(error)); Qt.exit(2); }
          });
        }
        function drive() {
          if (phase === "startup-service") {
            if (!WallpaperService.isInitialized) return;
            items.main = component("Main.qml", {pluginApi: api}); api.mainInstance = items.main;
            check(!items.main.thumbCacheReady, "historical readiness cannot mark a new generation ready");
            items.actualPanel = component("Panel.qml", {pluginApi: api});
            startupDeadline = Date.now() + 2000; phase = "startup"; return;
          }
          if (phase === "thumbnail-generation" && thumbnailControl.calls === 1) {
            check(!items.thumbnails.thumbCacheReady, "held first generation remains unready");
            items.thumbnails.thumbRegenerate();
            controlProcess.command = ["touch", Quickshell.env("I5_THUMB_CONTROL").replace("thumbnail-control.json", "release-1")];
            controlProcess.running = true; phase = "thumbnail-replacement"; return;
          }
          if (phase === "thumbnail-replacement" && thumbnailControl.calls === 2) {
            check(!items.thumbnails.thumbCacheReady && !items.thumbnails.generationFailed, "obsolete completion cannot acknowledge replacement generation");
            controlProcess.command = ["touch", Quickshell.env("I5_THUMB_CONTROL").replace("thumbnail-control.json", "release-2")];
            controlProcess.running = true; phase = "thumbnails"; return;
          }
          if (phase === "thumbnail-retry" && items.thumbnails.generationFailed) {
            check(!items.thumbnails.thumbCacheReady && receipts === 0, "failed generation retained for explicit retry");
            controlProcess.command = ["cp", "--", Quickshell.env("I5_THUMB_VALID"), Quickshell.env("I5_VIDEO_MEDIA")];
            phase = "thumbnail-retry-copy"; controlProcess.running = true; return;
          }
          if (["thumbnail-generation", "thumbnail-replacement", "thumbnail-retry", "thumbnail-retry-copy"].indexOf(phase) !== -1) return;
          if (phase === "startup") {
            check(api.settingsOwner.store.settingsKeys.every(function (key) { return api.settingsHandle.info([key]).latestInput === "0"; }),
              "actual Main startup creates no preference choices");
            check(record(name)?.currentWallpaper === "legacy-choice", "actual Main startup retains legacy monitor consumer");
            if (Date.now() >= startupDeadline && items.main.thumbCacheReady) {
              check(items.actualPanel.thumbCacheReady, "actual Panel consumes current Main generation readiness");
              pass();
            }
            return;
          }
          if (phase === "inner-availability") {
            if (!WallpaperService.isInitialized || !items.thumbFolder.ready) return;
            check(WallpaperService.getWallpaper(name) === Quickshell.env("I5_VIDEO_IMAGE"), "real initial wallpaper consumer");
            items.inner = component("main/InnerService.qml", {pluginApi: api, screenName: name, thumbCacheReady: true, thumbFolderModel: items.thumbFolder, getThumbPath: function () { return ""; }});
            items.inner.oldWallpapersSaved.connect(function () { root.oldWallpaperSignals++; });
            phase = "inner-saving";
            api.pluginSettings.enabled = true; return;
          }
          if (phase === "inner-saving") {
            if (!lastReceipt) return;
            if (mode === "inner-failure") {
              check(lastReceipt.status === "failed" && oldWallpaperSignals === 0, "failed old-wallpaper save never acknowledges generation");
              check(record(name).noctaliaWallpaper === Quickshell.env("I5_VIDEO_IMAGE"), "failed old-wallpaper work retained");
              pass(); return;
            }
            check(lastReceipt.status === "saved" && oldWallpaperSignals === 1, "old-wallpaper signal follows actual save receipt");
            check(items.inner.noctaliaWallpaper === Quickshell.env("I5_VIDEO_IMAGE"), "actual stored old-wallpaper consumer");
            phase = "inner-other";
            WallpaperService.changeWallpaper(Quickshell.env("I5_VIDEO_OTHER_IMAGE"), name); return;
          }
          if (phase === "inner-other" || phase === "inner-return") return;
          if (phase === "thumbnails") {
            if (!items.thumbnails.thumbCacheReady || !items.thumbFolder.ready) return;
            check(items.thumbFolder.files.indexOf(Quickshell.env("I5_VIDEO_THUMBS") + "/media.bmp") !== -1 && receipts === 0,
              "actual thumbnail output and transient generation readiness without preference save");
            pass(); return;
          }
          if (phase === "thumbnail-failure") {
            if (!items.thumbnails.thumbCacheReady && items.thumbnails.generationFailed !== true) return;
            check(!items.thumbnails.thumbCacheReady && receipts === 0, "failed FFmpeg generation never publishes readiness or saves preferences");
            check(items.thumbnails.generationFailed === true, "generation failure remains observable for retry");
            pass(); return;
          }
          if (phase === "mpv-await") {
            if (!mpvObserve.connected) { mpvObserve.connected = true; return; }
            lastReceipt = null; phase = "mpv-clamp";
            items.ipc.saveMonitorProperty("volume", -0.25, name); return;
          }
          if (phase === "mpv-clamp") {
            if (!mpvClampReceipt) return;
            check(mpvClampReceipt.status === "saved" || mpvClampReceipt.status === "nothing_to_save", "MPV volume normalizer's own save receipt");
            check(record(name).volume === 0 && items.mpv.volume === 0, "actual MPV handler normalizes and saves volume");
            phase = "mpv-readback";
            mpvObserve.write(JSON.stringify({command: ["get_property", "volume"], request_id: 8}) + "\n");
            mpvObserve.flush(); return;
          }
          if (phase === "mpv-readback") {
            if (!mpvVolumeObserved) return;
            items.mpv.deactivateMpvpaper(); phase = "mpv-stopping"; return;
          }
          if (phase === "mpv-stopping") { if (!mpvObserve.connected) pass(); return; }
          if (phase === "automation") {
            if (!automationSeen || !lastReceipt) return;
            check(lastReceipt.status === "saved" || lastReceipt.status === "nothing_to_save", "automation settings receipt");
            pass(); return;
          }
          if (!lastReceipt || ["open", "settings", "timer-failure"].indexOf(phase) !== -1) return;
          check(lastReceipt.status === "saved" || lastReceipt.status === "nothing_to_save", "real save receipt");
          lastReceipt = null;
          if (phase === "functions") {
            check(record(name).currentWallpaper === "function-choice" && record(name).isPlaying, "wallpaper command consumer");
            check(items.panel.currentWallpaper === "function-choice" && items.bar.isPlaying && items.tools.isPlaying, "actual panel, bar and tool consumers");
            check(items.mpv.currentWallpaper === "function-choice" && items.multimedia.currentWallpaper === "function-choice", "both actual backend setting consumers");
            phase = "ipc"; items.ipc.saveMonitorProperty("volume", 0.625, "__proto__");
          } else if (phase === "ipc") {
            check(record("__proto__").volume === 0.625, "IPC opaque complete screen name");
            phase = "tools"; items.tools.toggleMute();
          } else if (phase === "tools") {
            check(items.tools.isMuted && items.bar.isMuted, "tool row owning edit");
            items.bar.saveMonitorProperty("isPlaying", false); saveNext("bar");
          } else if (phase === "bar") {
            check(!items.bar.isPlaying && !items.tools.isPlaying, "bar command consumer");
            items.panel.saveMonitorProperty("currentWallpaper", "panel-choice"); saveNext("panel");
          } else if (phase === "panel") {
            check(items.panel.currentWallpaper === "panel-choice", "per-screen panel command");
            phase = "timer"; items.timer.save("volume", 0.875); items.timer.screenName = "caller-mutated";
          } else if (phase === "timer") {
            check(record(name).volume === 0.875 && record("caller-mutated") === undefined, "timer captured target before caller mutation");
            check(items.timer._pending === null && !items.timer.failed, "timer acknowledged and cleared captured work");
            var editor = api.createSettingsEditor();
            check(editor && editor.ready, "selected native draft");
            var pageApi = pageApiFactory.createObject(root, {base: api, editor: editor, pluginSettings: editor.values, initialSettings: editor.initialValue});
            items.page = component("Settings.qml", {pluginApi: pageApi});
            items.page.currentWallpaper = "settings-choice";
            items.page.saveSettings(); phase = "settings";
            editor.apply(editor.values, function (result) {
              try {
                check(result.status === "saved" && result.refreshState === "current", "Settings actual draft Apply receipt");
                check(record(name).currentWallpaper === "settings-choice" && items.panel.currentWallpaper === "settings-choice", "Settings to runtime consumer");
                phase = "automation";
                // First user publication intentionally shadows the whole legacy
                // source. Select monitor-specific automation explicitly here.
                api.pluginSettings.monitorSpecific = true;
                items.ipc.saveMonitorProperty("automationMode", "random", name);
                items.ipc.saveMonitorProperty("automationTime", 0.05, name);
                items.ipc.saveMonitorProperty("automation", true, name);
              } catch (error) { console.error(String(error)); Qt.exit(2); }
            });
          }
        }
        Component.onCompleted: begin()
        Process {
          id: controlProcess
          onExited: exitCode => {
            root.check(exitCode === 0, "thumbnail control operation");
            if (root.phase === "thumbnail-retry-copy") {
              root.items.thumbnails.thumbRegenerate();
              root.check(!root.items.thumbnails.thumbCacheReady && !root.items.thumbnails.generationFailed, "retry starts a new unready generation");
              root.phase = "thumbnails";
            }
          }
        }
        FileView {
          path: Quickshell.env("I5_THUMB_CONTROL")
          watchChanges: true
          printErrors: false
          onFileChanged: reload()
          onLoaded: root.thumbnailControl = JSON.parse(text())
        }
        Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
        FileView {
          path: Quickshell.env("I5_VIDEO_CACHE_FILE")
          watchChanges: true
          printErrors: false
          onFileChanged: reload()
          onLoaded: {
            if (root.mode !== "inner" || ["inner-other", "inner-return"].indexOf(root.phase) === -1) return;
            try {
              var value = JSON.parse(text()).wallpapers[root.name];
              var slot = Settings.data.colorSchemes.darkMode ? "dark" : "light";
              if (root.phase === "inner-other" && value[slot] === Quickshell.env("I5_VIDEO_OTHER_IMAGE")) {
                root.phase = "inner-return"; root.items.inner.applyOldWallpapers();
              } else if (root.phase === "inner-return" && value[slot] === Quickshell.env("I5_VIDEO_IMAGE")) {
                root.check(WallpaperService.getWallpaper(root.name) === Quickshell.env("I5_VIDEO_IMAGE"), "old-wallpaper effect reaches real consumer and persisted cache");
                root.pass();
              }
            } catch (error) { console.error("I5_VIDEO_RUNTIME_ASSERT: wallpaper effect readback", String(error)); Qt.exit(2); }
          }
        }
        Socket {
          id: mpvObserve
          path: Quickshell.env("I5_VIDEO_SOCKET") + "-" + root.name
          parser: SplitParser {
            onRead: line => {
              try {
                var result = JSON.parse(line);
                if (result.request_id === 8 && result.error === "success" && result.data === 0) root.mpvVolumeObserved = true;
              } catch (error) { console.error("I5_VIDEO_RUNTIME_ASSERT: invalid MPV protocol reply", String(error)); Qt.exit(2); }
            }
          }
        }
        Timer { interval: 20; running: true; repeat: true; onTriggered: { try { root.drive(); } catch (error) { console.error(String(error)); Qt.exit(2); } } }
        Timer { interval: 40000; running: true; onTriggered: { console.error("I5_VIDEO_RUNTIME_ASSERT: watchdog", root.phase); Qt.exit(2); } }
      }
    }
  }
}
