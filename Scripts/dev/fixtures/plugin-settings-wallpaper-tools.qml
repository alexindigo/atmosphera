import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_WALLPAPER_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_WALLPAPER_SCOPE")
  readonly property string choice: Quickshell.env("PHA_WALLPAPER_CHOICE")
  readonly property string mode: Quickshell.env("PHA_WALLPAPER_MODE")
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  readonly property string chosen: Quickshell.env("PHA_WALLPAPER_CHOSEN")
  readonly property string name: Quickshell.env("PHA_WALLPAPER_SCREEN")
  readonly property bool video: plugin === "video-wallpaper"
  readonly property string field: video ? "monitors" : "currentWallpaper"
  property var api: null
  property var target: null
  property var receipt: null
  property bool started: false
  property string phase: "owner"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string next: ""
  property int activations: 0
  property list<string> forbiddenMainCalls: []
  property bool sourceLifetimesSeen: false
  QtObject {
    id: actionOwner
    function activatePolicy(context) {
      root.check(context === root.target.settingsContext, "completion retains selected read-only context");
      ++root.activations;
      return true;
    }
    function random() {
      return root.recordForbiddenMainCall("random");
    }
    function clear() {
      return root.recordForbiddenMainCall("clear");
    }
  }
  function recordForbiddenMainCall(action) {
    // Record the invocation even when the caller catches or ignores its result.
    forbiddenMainCalls.push(action);
    throw new Error("SETTINGS_TOOL_MAIN_DISPATCH: " + action);
  }
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete Settings documents differ");
      else
        root.phase = root.next;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_TOOLS_ASSERT: " + plugin + "/" + scope + "/" + choice + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, seen) {
    if (!object)
      return null;
    seen = seen || new Set();
    if (seen.has(object))
      return null;
    seen.add(object);
    if (predicate(object))
      return object;
    if (object.item) {
      const found = find(object.item, predicate, seen);
      if (found)
        return found;
    }
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (const child of list) {
        const found = find(child, predicate, seen);
        if (found)
          return found;
      }
    }
    return null;
  }
  function probe(boundary, after) {
    next = after;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WALLPAPER_DISK"), base, Quickshell.env("PHA_WALLPAPER_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, translations, translations, {});
        api.mainInstance = actionOwner;
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        target = scope === "shared" ? api : PluginInstances.apiFor(plugin, {
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
  function setFolder(path) {
    const placeholder = api.tr(video ? "settings.general.wallpapers_folder.text_input.placeholder" : "settings.wallpapers_folder.input_placeholder");
    const input = find(popup.settingsPage, item => item.placeholderText === placeholder && item.editCommitted !== undefined);
    check(input, "actual folder control");
    input.text = path;
    input.editCommitted();
    check(popup._pageApi.field("wallpapersFolder").value === path, "folder intent precedes Random");
  }
  function tool(icon) {
    const tools = find(popup.settingsPage, item => typeof item.toggleMute === "function" && typeof item.clear === "function");
    const button = find(tools, item => item.icon === icon && item.clicked !== undefined);
    check(button, "actual scoped ToolRow button");
    button.clicked();
  }
  function stage() {
    if (choice === "random")
      setFolder(base + "/draft-folder");
    tool(choice === "clear" ? "clear-all" : "dice");
    if (choice === "random" && mode === "discard" && !sourceLifetimesSeen) {
      // Both real asynchronous folder models still have queued work. Replace
      // the selected source before either can deliver a choice.
      setFolder(base + "/original-folder");
      phase = "source-replaced";
      return;
    }
    phase = "preview";
    if (choice === "random")
      console.log("WALLPAPER_TOOLS_RANDOM admission " + randomState());
  }
  function randomState() {
    const page = popup.settingsPage;
    const owner = find(page, item => item.randomChoices !== undefined && typeof item.stageRandomWallpaper === "function") || page;
    const model = owner?.randomChoices || find(page, item => item.folder !== undefined && item.status !== undefined && typeof item.get === "function");
    return JSON.stringify({
                            pending: owner?.pendingRandom,
                            resolved: owner?.randomFolderPath,
                            folder: model?.folder,
                            status: model?.status,
                            count: model?.count,
                            sameModel: model === owner?.randomChoices,
                            resolvedUrl: String(Qt.resolvedUrl("file://" + (owner?.pendingRandom?.folder || ""))),
                            field: popup._pageApi?.field("currentWallpaper")?.value,
                            preview: page?.currentWallpaper,
                            chosen: chosen
                          });
  }
  function preview() {
    const value = popup._pageApi.field(field).value;
    return (video ? value[name]?.currentWallpaper : value) === chosen && popup.settingsPage.currentWallpaper === chosen;
  }
  function drive() {
    check(Date.now() - since < 18000, "finite tools phase deadline " + (phase === "preview" ? randomState() : ""));
    if (phase === "ready" && target.settingsReady) {
      check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual selected page opens");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty && !popup.dirty, "page construction submits no intent");
      if (mode === "cold") {
        check(preview(), "cold page displays applied choice");
        probe("applied", "finish");
      } else
        stage();
    } else if (phase === "source-replaced" && Date.now() - since > 300) {
      check(!popup._pageApi.field(field).pendingIntent, "obsolete folder result cannot stage wallpaper intent");
      setFolder(base + "/draft-folder");
      tool("dice");
      tool("clear-all");
      phase = "source-cleared";
    } else if (phase === "source-cleared" && Date.now() - since > 300) {
      const value = popup._pageApi.field(field).value;
      check((video ? value[name]?.currentWallpaper : value) === "", "Clear cancels queued Random choice");
      tool("dice");
      check(!popup.requestClose(), "queued Random cannot bypass dirty Close");
      popup.confirmDiscard();
      phase = "source-retired";
    } else if (phase === "source-retired" && !popup.opened && !popup._editor && Date.now() - since > 300) {
      check(activations === 0, "retired queued Random has no completion action");
      sourceLifetimesSeen = true;
      probe("discarded", "ready");
    } else if (phase === "preview" && preview()) {
      check(popup._pageApi.field(field).pendingIntent && popup.dirty, "button stages the actual selected field");
      check(activations === 0, "staging has no Main completion/action");
      probe("staged", mode === "discard" ? "discard" : "apply");
    } else if (phase === "discard") {
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor) {
      check(activations === 0, "Discard has no Main action");
      probe("discarded", "finish");
    } else if (phase === "apply") {
      receipt = null;
      check(popup.applySettings(), "native Apply");
      phase = "applied";
    } else if (phase === "applied" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "current native publication");
      check(activations === 1, "only accepted Apply notifies the selected Main policy");
      probe("applied", "finish");
    } else if (phase === "finish") {
      check(forbiddenMainCalls.length === 0, "forbidden Main dispatch: " + forbiddenMainCalls.join(", "));
      console.log("WALLPAPER_TOOLS: PASS " + plugin + " " + scope + " " + choice + " " + mode);
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
