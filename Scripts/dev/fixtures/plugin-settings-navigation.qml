// Observe the actual tab-owned generic popup and native input through host
// transition requests. No product page/focus instrumentation or fake writer.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var popup: null
  property var page: null
  property var input: null
  property bool pageDestroyed: false
  readonly property string presentation: Quickshell.env("PHA_NAVIGATION_MODE") || "window"
  readonly property bool windowMode: presentation === "window"
  readonly property bool sharedRoute: Quickshell.env("PHA_NAVIGATION_ROUTE") === "plugins"
  readonly property bool failurePhase: Quickshell.env("PHA_NAVIGATION_FAILURE") === "1"
  property string passKind: "dirty"
  property var completion: null
  readonly property var modelData: Quickshell.screens[0]
  property int operation: 0
  property var observations: []
  property var operations: ["service-tab", "service-search", "service-window-open", "service-close", "local-tab", "local-search", "keyboard-tab", "popup-direct-close"].concat(windowMode ? ["native-window-close", "direct-window-tab"] : ["panel-close", "panel-close-immediately", "panel-replacement", "deferred-panel-replacement", "overlay-replacement"]).concat(sharedRoute ? ["local-subtab", "button-subtab"] : [])
  property var content: null
  property int selectedTabIndex: -1
  readonly property var panel: panelLoader.item?.settingsPanel ?? null
  readonly property var replacement: panelLoader.item?.replacement ?? null
  FileView { id: manifestFile; path: Settings.configDir + "plugins/todo/manifest.json"; blockLoading: true; printErrors: false }
  Process { id: typing; onExited: function(code) { if (code !== 0) root.fail("input actor exit " + code); } }
  Process { id: permissions; onExited: function(code) { if (code !== 0) root.fail("permission actor exit " + code); } }
  function check(ok, message) { if (!ok) throw new Error("NAVIGATION_ASSERT: " + message); }
  function fail(error) { console.error(String(error) + "\n" + (error.stack || "")); Qt.exit(2); }
  function find(item, predicate, seen) {
    if (!item) return null;
    seen = seen || [];
    if (seen.indexOf(item) !== -1) return null;
    seen.push(item);
    if (predicate(item)) return item;
    for (var list of [item.data || item.children || [], item.contentItem ? [item.contentItem] : []]) {
      for (var i = 0; i < list.length; i++) {
        var hit = find(list[i], predicate, seen);
        if (hit) return hit;
      }
    }
    return null;
  }
  function begin() {
    if (started || !Settings.isLoaded || (!windowMode && !panel)) return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {todo: manifest};
    Service._openSettingsOwner("todo", function(owner) {
      try {
        check(!!owner, "native owner");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {todo: {api: api, manifest: manifest}};
        Settings.data.desktopWidgets.enabled = true;
        Settings.data.ui.settingsPanelMode = presentation;
        Settings.data.desktopWidgets.monitorWidgets = [{name: Quickshell.screens[0].name, widgets: [{id: "plugin:todo"}]}];
        Settings.saveSelected([["desktopWidgets"], ["ui", "settingsPanelMode"]], function(result) {
          check(result.status !== "failed", "seed selected placement");
          SettingsPanelService.openToTab(sharedRoute ? SettingsPanel.Tab.Plugins : SettingsPanel.Tab.DesktopWidgets, -1, Quickshell.screens[0]);
          root.phase = "tab";
        });
      } catch(error) { fail(error); }
    });
  }
  function request(name) {
    var entry = {tab: 0, subTab: 0, labelKey: "common.general"};
    if (name === "service-tab") SettingsPanelService.openToTab(SettingsPanel.Tab.General, -1, Quickshell.screens[0]);
    else if (name === "service-search") SettingsPanelService.openToEntry(entry, Quickshell.screens[0]);
    else if (name === "service-window-open") SettingsPanelService.openWindow(SettingsPanel.Tab.General);
    else if (name === "service-close") SettingsPanelService.close(Quickshell.screens[0]);
    else if (name === "local-tab") content.navigateToTab(SettingsPanel.Tab.General, -1);
    else if (name === "local-search") content.navigateToResult(entry);
    else if (name === "keyboard-tab") content.selectNextTab();
    else if (name === "popup-direct-close") popup.close();
    else if (name === "native-window-close") window.contentItem.Window.window.close();
    else if (name === "direct-window-tab") window.navigateTo(SettingsPanel.Tab.General, -1);
    else if (name === "panel-close") panel.close();
    else if (name === "panel-close-immediately") panel.closeImmediately();
    else if (name === "panel-replacement") replacement.open();
    else if (name === "deferred-panel-replacement") {
      replacement.panelBehaviorReady = false;
      replacement.open();
      replacement.panelBehaviorReady = true;
    }
    else if (name === "overlay-replacement") {
      Settings.data.appLauncher.overviewLayer = true;
      PanelService.openLauncher(Quickshell.screens[0]);
      check(!PanelService.overlayLauncherOpen, "overlay cannot replace retained Settings");
    }
    else if (name === "local-subtab") content.setSubTabIndex(1);
    else if (name === "button-subtab") {
      var bar = find(content.activeTabContent, function(item) { return item.objectName === "NTabBar"; });
      check(!!bar, "actual subtab bar");
      var button = find(bar, function(item) { return item.tabIndex === 1 && typeof item.selectTab === "function"; });
      check(!!button && !button.selectTab(1), "actual subtab button admission refuses transition");
      check(bar.currentIndex === 0, "subtab unchanged");
    }
    else check(false, "unknown transition");
  }
  function hostVisible() { return windowMode ? window.visible : !!panel && panel.isPanelOpen && !panel.isClosing && PanelService.openedPanel === panel; }
  function drive() {
    if (phase === "tab" && hostVisible()) {
      var host = windowMode ? window.contentItem : panel;
      content = find(host, function(item) { return typeof item.navigateToResult === "function"; });
      if (!content || !content.activeTabContent) return;
      var tab = content.activeTabContent;
      popup = find(tab, function(item) { return typeof item.openInstanceSettings === "function"; });
      if (!popup) return;
      check(!!popup, "actual Desktop Widgets popup");
      popup.settingsCompleted.connect(function(result) { root.completion = result; });
      if (sharedRoute) popup.openPluginSettings(api.manifest, "settings");
      else tab._openInstanceSettings(api.manifest, "settings", Quickshell.screens[0].name, 0);
      phase = "page";
    } else if (phase === "page" && popup.visible && popup.settingsPage) {
      page = popup.settingsPage;
      selectedTabIndex = content.currentTabIndex;
      page.Component.destruction.connect(function() { root.pageDestroyed = true; });
      var wrapper = find(page, function(item) { return typeof item.commitEdit === "function" && item.inputItem !== undefined; });
      check(!!wrapper, "actual native page input");
      input = wrapper.inputItem;
      phase = "focus";
    } else if (phase === "focus") {
      input.forceActiveFocus(); input.selectAll();
      check(input.activeFocus, "native input focus");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "--", "/pending/navigation"];
      typing.running = true;
      phase = "typing";
    } else if (phase === "typing" && !typing.running && input.text === "/pending/navigation") {
      phase = "request";
    } else if (phase === "request") {
      check(!pageDestroyed && popup.settingsPage === page && hostVisible(), "page alive before transition");
      request(operations[operation]);
      phase = "verify-refusal";
    } else if (phase === "verify-refusal") {
      check(content.currentTabIndex === selectedTabIndex, operations[operation] + " retained navigation owner");
      if (operations[operation] === "deferred-panel-replacement")
        check(!replacement.isPanelVisible, "late replacement cannot show an unowned competing surface");
      check(!pageDestroyed && popup.settingsPage === page && popup.visible && hostVisible(), operations[operation] + " retained actual presentation");
      check(input.text === "/pending/navigation" && popup.dirty && popup.discardPending, operations[operation] + " retained local input and confirmation");
      if (passKind === "dirty")
        check(api.pluginSettings.exportPath !== "/pending/navigation", "no publication on refused unapplied leave");
      observations.push(passKind + ":" + operations[operation]);
      popup.keepEditing();
      if (++operation < operations.length) phase = "request";
      else if (passKind === "dirty" && failurePhase) {
        permissions.command = ["chmod", "500", Settings.configDir + "settings" + (sharedRoute ? "/plugins" : "")];
        permissions.running = true;
        phase = "unwritable";
      } else if (failurePhase) {
        permissions.command = ["chmod", "700", Settings.configDir + "settings" + (sharedRoute ? "/plugins" : "")];
        permissions.running = true;
        phase = "restoring";
      } else {
        check(popup.confirmDiscard(), "unapplied explicit Discard");
        phase = "discarded";
      }
    } else if (phase === "unwritable" && !permissions.running) {
      check(popup.applySettings() && popup.busy, "actual native Apply in flight");
      check(SettingsPanelService.openToTab(SettingsPanel.Tab.General, -1, Quickshell.screens[0]) === false, "busy transition refused");
      popup.close();
      check(popup.settingsPage === page && input.text === "/pending/navigation", "busy same page/input");
      observations.push("busy:service-tab");
      observations.push("busy:popup-direct-close");
      phase = "failed";
    } else if (phase === "failed" && completion && !popup.busy) {
      check(completion.status === "failed" && popup.saveFailed, "actual IO failure retained");
      passKind = "failed"; operation = 0; phase = "request";
    } else if (phase === "restoring" && !permissions.running) {
      check(popup.confirmDiscard(), "explicit Discard");
      phase = "discarded";
    } else if (phase === "discarded" && !popup.visible) {
      SettingsPanelService.openToTab(SettingsPanel.Tab.General, -1, Quickshell.screens[0]);
      phase = "admitted";
    } else if (phase === "admitted" && pageDestroyed) {
      check(content.tabsModel[content.currentTabIndex].id === SettingsPanel.Tab.General, "retry after Discard navigated");
      console.log("NAVIGATION_RESULT " + JSON.stringify({status:"PASS", presentation: presentation, route: sharedRoute ? "plugins" : "desktop", failurePhase: failurePhase, requests: observations, samePageAndInputRetained: true, genuineTyping: true, admittedDiscardNavigation: true}));
      SettingsPanelService.close(Quickshell.screens[0]);
      Qt.exit(0);
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  SettingsPanelWindow { id: window }
  PanelWindow {
    visible: !root.windowMode
    implicitWidth: 1280
    implicitHeight: 1024
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Loader {
      id: panelLoader
      active: !root.windowMode && Settings.isLoaded
      sourceComponent: Item {
        readonly property alias settingsPanel: actualPanel
        readonly property alias replacement: otherPanel
        SettingsPanel { id: actualPanel; objectName: "settingsPanel-" + Quickshell.screens[0].name; screen: Quickshell.screens[0] }
        SmartPanel { id: otherPanel; objectName: "replacement"; screen: Quickshell.screens[0]; panelContent: Rectangle { implicitWidth: 200; implicitHeight: 200 } }
      }
    }
  }
  Timer { interval: 60; running: true; repeat: true; onTriggered: { try { root.begin(); root.drive(); } catch(error) { root.fail(error); } } }
  Timer { interval: 60000; running: true; onTriggered: root.fail("watchdog at " + phase); }
  Component.onCompleted: begin()
}
