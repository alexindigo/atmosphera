import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.Panels.Launcher
import qs.Services.UI
import qs.Services.Keyboard
import qs.Services.Compositor

ShellRoot {
  id: root
  property bool alive: true
  property var cachedDuring: []
  property int projections: 0
  property string originalClipboardSelection: ""
  function rows() {
    return subject.item ? subject.item.results.map(item => ({name: item.name,
      id: String(item.clipboardId || item.id || item.windowId || item.autoPasteText || item.name)})) : [];
  }
  Item {
    id: plugin
    property var launcher: null
    property string name: "Async fixture"
    property string supportedLayouts: "list"
    property bool handleSearch: false
    property bool loading: true
    property var records: []
    signal resultsChanged
    onRecordsChanged: resultsChanged()
    onLoadingChanged: resultsChanged()
    function handleCommand(query) { return query.startsWith(">async"); }
    function getResults(query) {
      if (records.length === 0 && loading)
        return [{name: "Loading plugin", icon: "application-x-executable", isImage: false, provider: plugin}];
      return records.map(item => ({id: item, name: item, icon: "application-x-executable", isImage: false, provider: plugin}));
    }
  }
  Item {
    id: legacy
    property var launcher: null
    property string name: "Legacy fixture"
    property string supportedLayouts: "list"
    property bool handleSearch: false
    property var records: []
    function handleCommand(query) { return query.startsWith(">legacy"); }
    function getResults(query) { return records.map(item => ({id: item, name: item, icon: "application-x-executable", isImage: false, provider: legacy})); }
  }
  FloatingWindow {
    id: window
    title: "Data Window Before"
    implicitWidth: 700
    implicitHeight: 600
    Loader {
      id: subject
      anchors.fill: parent
      active: root.alive
      sourceComponent: LauncherCore { isOpen: true; screen: Quickshell.screens[0] }
    }
  }
  Connections {
    target: subject.item
    function onResultsChanged() { root.projections++; }
  }
  Component.onCompleted: {
    ClipboardService.autoWatch = false;
    ClipboardService.stopWatchers();
    LauncherProviderRegistry.pluginProviders = {"plugin:data": true, "plugin:legacy": true};
    LauncherProviderRegistry.providerInstances = {"plugin:data": plugin, "plugin:legacy": legacy};
  }
  IpcHandler {
    target: "providerData"
    function query(value: string): void { subject.item.setSearchText(value); }
    function step(value: string): void {
      switch (value) {
      case "clip-cached":
        subject.item.selectedIndex = 1;
        root.originalClipboardSelection = String(subject.item.results[1].clipboardId);
        ClipboardService.list(100);
        subject.item.updateResults();
        root.cachedDuring = root.rows();
        break;
      case "clip-refresh": ClipboardService.list(100); break;
      case "emoji-data":
        EmojiService.emojis = [{emoji: "😀", name: "cache-marker first", keywords: [], category: "people"},
                               {emoji: "😃", name: "cache-marker second", keywords: [], category: "people"}];
        break;
      case "emoji-refresh":
        EmojiService.loaded = false;
        subject.item.updateResults();
        root.cachedDuring = root.rows();
        break;
      case "emoji-ready": EmojiService.loaded = true; break;
      case "emoji-recent":
        EmojiService.usageCounts = {};
        subject.item.setSearchText(">emoji ");
        break;
      case "emoji-usage": EmojiService.recordUsage("😀"); break;
      case "settings-empty":
        SettingsSearchService.searchIndex = [];
        subject.item.setSearchText(">settings general");
        break;
      case "settings-data":
        SettingsSearchService.searchIndex = [{labelKey: "common.general", tabLabel: "common.general", widget: "NTextInput", tab: "general"}];
        break;
      case "window-title": window.title = "Data Window After"; break;
      case "plugin-data": plugin.records = ["p1", "p2"]; plugin.loading = false; break;
      case "plugin-prepend": subject.item.selectedIndex = 1; plugin.records = ["p0", "p1", "p2"]; break;
      case "plugin-refresh": plugin.loading = true; subject.item.updateResults(); root.cachedDuring = root.rows(); break;
      case "destroy-core": root.alive = false; break;
      case "publish-closed": plugin.records = ["closed-data"]; break;
      case "recreate-core": root.alive = true; break;
      case "legacy-data": legacy.records = ["legacy-ready"]; legacy.launcher.updateResults(); break;
      }
    }
    function state(): string {
      const core = subject.item;
      return JSON.stringify({alive: !!core, ready: core ? core.openReady : false, query: core ? core.searchText : null,
        providers: core ? core.providers.map(provider => provider.name) : [],
        rows: root.rows(), selected: core && core.results[core.selectedIndex] ?
        String(core.results[core.selectedIndex].clipboardId || core.results[core.selectedIndex].id || core.results[core.selectedIndex].name) : null,
        cachedDuring: root.cachedDuring, originalClipboardSelection: root.originalClipboardSelection,
        clipboardReady: ClipboardService.active, clipboardLoading: ClipboardService.loading, clipboardItems: ClipboardService.items.length,
        emojiReady: EmojiService.loaded, settingsReady: SettingsSearchService.searchIndex.length > 0,
        projections: root.projections, pluginAttached: !!core && plugin.launcher === core, pluginDetached: plugin.launcher === null});
    }
    function exitControl(): void { Qt.exit(0); }
  }
}
