// Full-shell keyboard focus observer for the shell-wide NToggle change.
// Opens production surfaces through the shell's own IPC routes, sends real
// Wayland keys through the task injector, and records value-free focus facts.
// Never presses Return/Enter on the lock preview, so no PAM attempt is made.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root
  required property bool sessionReady
  property int step: 0
  property int ticks: 0
  property var trace: []
  property var facts: ({})
  readonly property string injector: Quickshell.env("PHA_INPUT_INJECTOR")
  readonly property string entry: Quickshell.env("PHA_ENTRY")
  readonly property var screen: Quickshell.screens[0]

  function describe(item) {
    if (!item)
      return "none";
    var type = String(item).split("(")[0].replace(/_QMLTYPE_\d+/g, "").replace(/_QML_\d+/g, "");
    if (typeof item.activate === "function" && typeof item.toggled === "function" && item.checked !== undefined)
      type = "NToggle";
    return type;
  }
  function panelFocus(panel) {
    var item = panel && panel.contentItem ? panel.contentItem : panel;
    return item ? describe(item.Window.activeFocusItem) : "no-panel";
  }
  function settingsHost() {
    return Settings.data.ui.settingsPanelMode === "window" ? SettingsPanelService.settingsWindow : PanelService.getPanel("settingsPanel", screen);
  }
  function findContent(item) {
    if (!item)
      return null;
    if (typeof item.selectNextTab === "function" && item.searchText !== undefined && item.activeTabContent !== undefined)
      return item;
    for (var child of item.children || []) {
      var found = findContent(child);
      if (found)
        return found;
    }
    return null;
  }
  function settingsContent() {
    var panel = settingsHost();
    return panel && panel._settingsContent ? panel._settingsContent : findContent(panel ? panel.contentItem : null);
  }
  function settingsOpen() {
    var host = settingsHost();
    return host && (Settings.data.ui.settingsPanelMode === "window" ? host.visible : host.isPanelOpen);
  }
  function lockData() {
    var loader = PanelService.lockScreen;
    if (!loader || !loader.active || !loader.item)
      return null;
    var context = null;
    for (var child of loader.item.data)
      if (child && child.passwordText !== undefined && typeof child.tryUnlock === "function")
        context = child;
    return context;
  }
  function lockFocus() {
    var loader = PanelService.lockScreen;
    if (!loader || !loader.item)
      return "no-lock";
    var described = "none";
    function walk(object) {
      if (!object)
        return;
      if (object.contentItem && object.contentItem.Window && object.contentItem.Window.activeFocusItem)
        described = describe(object.contentItem.Window.activeFocusItem);
      for (var nested of object.data || [])
        walk(nested);
      for (var instance of object.instances || [])
        walk(instance);
    }
    walk(loader.item);
    return described;
  }
  function record(name, value) {
    trace.push(name + "=" + JSON.stringify(value));
    console.log("FOCUS_TRACE " + name + " " + JSON.stringify(value));
  }
  function fail(message) {
    console.error("FOCUS_ASSERT: " + message + " at step " + step + " trace " + JSON.stringify(trace));
    Qt.exit(2);
  }
  function check(condition, message) {
    if (!condition)
      fail(message);
    return condition;
  }
  function ipc(args) {
    command.command = ["qs", "ipc", "-p", entry, "call"].concat(args);
    command.running = true;
  }
  function key(args) {
    keys.command = [injector].concat(args);
    keys.running = true;
  }
  // Each step either starts one action or waits for its observable outcome.
  readonly property var steps: [function () {
    if (!sessionReady || !settingsHost() || ++ticks < 40)
      return false;
    check(Settings.data.ui.settingsPanelMode === Quickshell.env("PHA_SETTINGS_MODE"), "authored Settings mode admitted without fallback");
    record("settings.mode", Settings.data.ui.settingsPanelMode);
    ipc(["settings", "open"]);
    return true;
  }, function () {
    var content = settingsContent();
    if (!content || !settingsOpen() || ++ticks < 15)
      return false;
    facts.settingsTab = content.currentTabIndex;
    record("settings.initialFocus", panelFocus(settingsHost()));
    key(["-k", "Tab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var content = settingsContent();
    record("settings.afterTab", panelFocus(settingsHost()));
    check(content.currentTabIndex === facts.settingsTab + 1, "Settings Tab still selects the next tab");
    check(panelFocus(settingsHost()) !== "NToggle", "Settings Tab does not move focus onto a toggle");
    key(["-M", "shift", "-k", "Tab", "-m", "shift"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    record("settings.afterBacktab", panelFocus(settingsHost()));
    check(settingsContent().currentTabIndex === facts.settingsTab, "Settings Backtab returns to the previous tab");
    key(["--", "zz"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var content = settingsContent();
    record("settings.searchText", content.searchText);
    check(content.searchText === "zz", "Settings search field keeps keyboard text input");
    facts.searchTab = content.currentTabIndex;
    key(["-k", "Tab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var content = settingsContent();
    record("settings.searchAfterTab", panelFocus(settingsHost()));
    check(content.searchText === "zz", "Tab does not clear Settings search");
    check(panelFocus(settingsHost()) !== "NToggle", "Tab from search does not land on a toggle");
    ipc(["settings", "toggle"]);
    return true;
  }, function () {
    if (settingsOpen() || ++ticks < 5)
      return false;
    ipc(["launcher", "toggle"]);
    return true;
  }, function () {
    if (!PanelService.isLauncherOpen(screen) || ++ticks < 15)
      return false;
    var panel = PanelService.getPanel("launcherPanel", screen);
    record("launcher.initialFocus", panelFocus(panel));
    key(["--", "ab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    check(PanelService.getLauncherSearchText(screen) === "ab", "launcher search receives text");
    facts.launcherFocus = panelFocus(PanelService.getPanel("launcherPanel", screen));
    key(["-k", "Tab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var focus = panelFocus(PanelService.getPanel("launcherPanel", screen));
    record("launcher.afterTab", focus);
    check(PanelService.isLauncherOpen(screen), "launcher stays open after Tab");
    check(PanelService.getLauncherSearchText(screen) === "ab", "launcher search text kept after Tab");
    check(focus === facts.launcherFocus, "launcher keeps its search focus after Tab");
    ipc(["launcher", "toggle"]);
    return true;
  }, function () {
    if (PanelService.isLauncherOpen(screen) || ++ticks < 5)
      return false;
    ipc(["controlCenter", "toggle"]);
    return true;
  }, function () {
    var panel = PanelService.getPanel("controlCenterPanel", screen);
    if (!panel || !panel.isPanelOpen || ++ticks < 15)
      return false;
    facts.tabs = 0;
    record("controlCenter.initialFocus", panelFocus(panel));
    key(["-k", "Tab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var panel = PanelService.getPanel("controlCenterPanel", screen);
    var focus = panelFocus(panel);
    record("controlCenter.tab" + (++facts.tabs), focus);
    check(panel.isPanelOpen, "control center stays open across Tab");
    check(focus !== "NToggle", "control center Tab chain contains no toggle");
    if (facts.tabs < 4) {
      key(["-k", "Tab"]);
      ticks = 0;
      return false;
    }
    ipc(["controlCenter", "toggle"]);
    return true;
  }, function () {
    var panel = PanelService.getPanel("controlCenterPanel", screen);
    if ((panel && panel.isPanelOpen) || ++ticks < 5)
      return false;
    ipc(["lockScreen", "preview"]);
    return true;
  }, function () {
    var context = lockData();
    if (!context || ++ticks < 20)
      return false;
    record("lock.initialFocus", lockFocus());
    facts.lockFocus = lockFocus();
    facts.tabs = 0;
    key(["-k", "Tab"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var focus = lockFocus();
    record("lock.tab" + (++facts.tabs), focus);
    check(focus === facts.lockFocus, "lock password field keeps focus across Tab");
    if (facts.tabs < 3) {
      key(["-k", "Tab"]);
      ticks = 0;
      return false;
    }
    key(["--", "abc"]);
    return true;
  }, function () {
    if (++ticks < 8)
      return false;
    var context = lockData();
    record("lock.passwordLength", context.passwordText.length);
    check(context.passwordText === "abc", "locked keyboard input reaches only the password field");
    check(lockFocus() === facts.lockFocus, "lock focus unchanged after typing");
    key(["-k", "Escape"]);
    return true;
  }, function () {
    var loader = PanelService.lockScreen;
    if ((loader && loader.active) || ++ticks < 5)
      return false;
    console.log("FOCUS_RESULT " + JSON.stringify(trace));
    Qt.exit(0);
    return true;
  }]
  Process {
    id: command
    onExited: exitCode => {
      if (exitCode !== 0)
        root.fail("IPC call failed: " + JSON.stringify(command.command.slice(4)));
    }
  }
  Process {
    id: keys
    onExited: exitCode => {
      if (exitCode !== 0)
        root.fail("key injection failed");
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (command.running || keys.running || root.step >= root.steps.length)
        return;
      if (root.steps[root.step]()) {
        root.step++;
        root.ticks = 0;
      }
    }
  }
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("watchdog")
  }
}
