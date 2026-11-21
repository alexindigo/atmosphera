import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

// Actual shared Settings children and runtime Panel callers. Backend/file scans
// are confined to the fixture's empty directory; no media or recorder is run.
ShellRoot {
  id: root
  readonly property string pluginId: Quickshell.env("PHA_CHILD_PLUGIN")
  readonly property string scopeKind: Quickshell.env("PHA_CHILD_SCOPE") || "instance"
  readonly property bool cold: Quickshell.env("PHA_CHILD_COLD") === "1"
  readonly property string screenName: Quickshell.env("PHA_CHILD_SCREEN")
  property bool started: false
  property var api: null
  property var selected: null
  property var manifest: null
  property var receipt: null
  property var runtimeReceipt: null
  property var runtimePanel: null
  property var folderModel: null
  property string phase: "owner"
  property double deadline: Date.now() + 30000
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  QtObject {
    id: actionOwner
    property bool thumbCacheReady: false
    function registerRuntime(runtimeApi) {
      return runtimeApi.settingsContext.current();
    }
    function activatePolicy(context) {
      return context.current();
    }
    function admitRuntime(runtimeApi) {
      return runtimeApi.settingsContext.current() ? runtimeApi : null;
    }
    function setPreference(key, value, runtimeApi) {
      if (!runtimeApi.settingsContext.current())
        return false;
      runtimeApi.pluginSettings[key] = value;
      return runtimeApi.saveSettings();
    }
    function random(screen) {
    }
    function clear(screen) {
    }
  }
  FileView {
    id: reader
    blockLoading: true
    printErrors: false
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) {
      if (pluginId === root.pluginId && (root.phase === "panel" || root.phase === "runtime-save"))
        root.runtimeReceipt = result;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CHILD_WRITER_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function advance(value) {
    phase = value;
    deadline = Date.now() + 20000;
  }
  function find(object, predicate) {
    var visited = [];
    function visit(item) {
      if (!item || visited.indexOf(item) !== -1)
        return null;
      visited.push(item);
      if (predicate(item))
        return item;
      for (var list of [item.data || item.children, item.contentItem ? [item.contentItem] : []]) {
        if (!list)
          continue;
        for (var i = 0; i < list.length; i++) {
          var result = visit(list[i]);
          if (result)
            return result;
        }
      }
      return null;
    }
    return visit(object);
  }
  function openPage() {
    check(scopeKind === "plugin" ? popup.openPluginSettings(manifest) : popup.openInstanceSettings(manifest, selected), "actual page opens");
    advance("page");
  }
  function playing() {
    return pluginId === "video-wallpaper" ? selected.pluginSettings.monitors[screenName].isPlaying : selected.pluginSettings.isPlaying;
  }
  function muted() {
    return pluginId === "video-wallpaper" ? selected.pluginSettings.monitors[screenName].isMuted : selected.pluginSettings.isMuted;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    check(Quickshell.screens.some(screen => screen.name === screenName), "explicit seeded output exists");
    started = true;
    reader.path = Settings.configDir + "plugins/" + pluginId + "/manifest.json";
    reader.waitForJob();
    manifest = JSON.parse(reader.text());
    var manifests = {};
    manifests[pluginId] = manifest;
    Registry.installedPlugins = manifests;
    Service._openSettingsOwner(pluginId, function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        root.api = Service.createPluginAPI(pluginId, manifest, owner, {}, {}, {});
        root.api.mainInstance = actionOwner;
        var loaded = {};
        loaded[pluginId] = {
          api: root.api
        };
        Service.loadedPlugins = loaded;
        root.selected = scopeKind === "plugin" ? root.api : PluginInstances.apiFor(pluginId, {
                                                                                     kind: "bar",
                                                                                     list: "global",
                                                                                     section: "left",
                                                                                     index: 0
                                                                                   });
        advance("runtime");
      } catch (error) {
        root.fail(error);
      }
    });
  }
  function toggleTools(container) {
    var tools = find(container, item => typeof item.togglePlaying === "function" && typeof item.toggleMute === "function");
    check(!!tools, "real ToolRow is loaded");
    var play = find(tools, item => item.icon === (tools.isPlaying ? "media-pause" : "media-play") && typeof item.clicked === "function");
    var mute = find(tools, item => item.icon === (tools.isMuted ? "volume-high" : "volume-mute") && typeof item.clicked === "function");
    check(play && mute, "actual ToolRow buttons");
    play.clicked();
    mute.clicked();
  }
  function makePanel() {
    var directory = "file://" + Settings.configDir + "plugins/" + pluginId + "/";
    var properties = {
      pluginApi: selected
    };
    var path = "Panel.qml";
    if (pluginId === "video-wallpaper") {
      var folder = Qt.createComponent(directory + "common/FolderModel.qml");
      check(folder.status === Component.Ready, folder.errorString());
      folderModel = folder.createObject(root, {
                                          folder: Settings.configDir + "empty"
                                        });
      properties.screenName = screenName;
      properties.thumbCacheReady = false;
      properties.folderModel = folderModel;
      path = "panel/PerScreenPanel.qml";
    }
    var component = Qt.createComponent(directory + path);
    check(component.status === Component.Ready, component.errorString());
    runtimePanel = component.createObject(host.contentItem, properties);
    check(!!runtimePanel, "actual runtime Panel constructed");
    toggleTools(runtimePanel);
    advance("runtime-save");
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        check(Date.now() <= root.deadline, "deadline " + root.phase);
        if (!root.started)
          root.begin();
        if (root.phase === "runtime" && root.selected?.settingsReady) {
          if (root.cold) {
            if (root.pluginId === "screen-recorder") {
              check(root.selected.pluginSettings.videoSource === "portal" && root.selected.pluginSettings.videoCodec === "h264", "cold explicit source/codec consumer");
            } else
              check(root.playing() && root.muted(), "cold runtime Panel toggle consumer");
            console.log("CHILD_WRITERS_COLD: PASS");
            Qt.exit(0);
          } else
            root.openPage();
        } else if (root.phase === "page" && popup.opened && popup.settingsPage) {
          check(!popup._editor.dirty, "page construction creates no intent");
          if (root.pluginId === "screen-recorder") {
            var field = popup.settingsPage.videoSourceField;
            var chrome = root.find(popup.settingsPage, item => item.field === field && item.content !== undefined);
            var reset = root.find(chrome, item => item.text === I18n.tr("common.reset") && typeof item.clicked === "function");
            check(!!reset, "source field Reset control");
            reset.clicked();
            root.advance("reset-projection");
          } else {
            root.toggleTools(popup.settingsPage);
            root.advance("tools-staged");
          }
        } else if (root.phase === "reset-projection") {
          check(popup.settingsPage.videoSourceField.value === "portal", "Reset reveals lower source");
          check(popup.settingsPage.videoCodecField.pendingIntent === "" && popup.settingsPage.videoCodecField.value === "hevc_hdr", "source Reset cannot author untouched codec");
          popup.confirmDiscard();
          root.advance("reopen");
        } else if (root.phase === "reopen" && !popup.visible && !popup._editor) {
          root.openPage();
          root.advance("selection-page");
        } else if (root.phase === "selection-page" && popup.opened && popup.settingsPage) {
          var choice = root.find(popup.settingsPage, item => item.currentKey === "screen" && typeof item.selected === "function");
          check(!!choice, "real source choice control");
          choice.selected("portal");
          root.advance("selection-staged");
        } else if (root.phase === "selection-staged") {
          check(popup.settingsPage.videoSourceField.pendingIntent === "set" && popup.settingsPage.videoCodecField.pendingIntent === "set", "explicit source event owns dependent codec intent");
          check(root.selected.pluginSettings.videoSource === "screen" && root.selected.pluginSettings.videoCodec === "hevc_hdr", "staged source selection cannot affect runtime");
          popup.applySettings();
          root.advance("save");
        } else if (root.phase === "tools-staged") {
          check(root.playing() && root.muted(), "shared child stages without live runtime write");
          popup.applySettings();
          root.advance("save");
        } else if (root.phase === "save" && root.receipt && !popup.busy) {
          check(["saved", "nothing_to_save"].indexOf(root.receipt.status) !== -1 && root.receipt.refreshState === "current", "accepted native receipt");
          root.advance("consumer");
        } else if (root.phase === "consumer") {
          if (root.pluginId === "screen-recorder") {
            if (root.selected.pluginSettings.videoSource !== "portal" || root.selected.pluginSettings.videoCodec !== "h264")
              return;
            popup.requestClose();
            console.log("CHILD_WRITERS: PASS");
            Qt.exit(0);
          } else {
            if (root.playing() || root.muted())
              return;
            popup.requestClose();
            root.advance("panel");
          }
        } else if (root.phase === "panel" && !popup.visible && !popup._editor)
          root.makePanel();
        else if (root.phase === "runtime-save" && root.playing() && root.muted() && root.runtimeReceipt && root.selected._pendingSettingsSaves === 0) {
          check(["saved", "nothing_to_save"].indexOf(root.runtimeReceipt.status) !== -1, "runtime Panel receives actual save completion");
          root.runtimePanel.destroy();
          if (root.folderModel)
            root.folderModel.destroy();
          console.log("CHILD_WRITERS: PASS");
          Qt.exit(0);
        }
      } catch (error) {
        root.fail(error);
      }
    }
  }
}
