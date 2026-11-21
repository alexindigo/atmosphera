import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen as MainScreen
import qs.Modules.Panels.Settings.Tabs.Plugins as PluginTabs
import qs.Services.Control
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string route: Quickshell.env("PHA_SHARED_ROUTE")
  readonly property bool cold: Quickshell.env("PHA_SHARED_ROUTE_COLD") === "1"
  property bool started: false
  property string phase: "startup"
  property string afterProbe: ""
  property string actorNext: ""
  property var api: null
  property var inherited: null
  property var sibling: null
  property var popup: null
  property var receipt: null
  property var failedPage: null
  property var failedEditor: null
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/values-fixture/manifest.json"
    blockLoading: true
    printErrors: false
  }
  CurrentScreenDetector {
    id: screenDetector
  }
  Variants {
    model: root.cold ? [] : Quickshell.screens
    MainScreen.PopupMenuWindow {
      required property var modelData
      shellScreen: modelData
      screen: modelData
    }
  }
  PanelWindow {
    visible: !root.cold && root.route === "installed"
    implicitWidth: 1280
    implicitHeight: 900
    Loader {
      id: tab
      anchors.fill: parent
      active: false
      sourceComponent: PluginTabs.InstalledSubTab {}
    }
  }
  Text {
    id: sharedText
    text: root.api?.settingsView?.label ?? ""
  }
  Text {
    id: inheritedText
    text: root.inherited?.settingsView?.label ?? ""
  }
  Text {
    id: siblingText
    text: root.sibling?.settingsView?.label ?? ""
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("SHARED_ROUTE_ASSERT: " + route + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(item, predicate, seen) {
    if (!item)
      return null;
    seen = seen || [];
    if (seen.indexOf(item) !== -1)
      return null;
    seen.push(item);
    if (predicate(item))
      return item;
    for (var list of [item.data, item.children, item.resources, item.contentItem ? [item.contentItem] : []]) {
      if (!list)
        continue;
      for (var i = 0; i < list.length; i++) {
        var found = find(list[i], predicate, seen);
        if (found)
          return found;
      }
    }
    return null;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "values-fixture": manifest
    };
    Service._openSettingsOwner("values-fixture", function (owner) {
      try {
        check(!!owner, "actual shared native owner");
        api = Service.createPluginAPI("values-fixture", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "values-fixture": {
            api: api,
            manifest: manifest
          }
        };
        inherited = PluginInstances.apiFor("values-fixture", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 0
                                           });
        sibling = PluginInstances.apiFor("values-fixture", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        if (!cold)
          IPCService.init(screenDetector);
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(boundary, next) {
    afterProbe = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_SHARED_ROUTE_PROBE"), boundary];
    disk.running = true;
  }
  function open(next) {
    popup = null;
    receipt = null;
    if (route === "installed") {
      var button = find(tab.item, item => item.tooltipText === I18n.tr("panels.plugins.settings-tooltip") && typeof item.clicked === "function");
      check(!!button && button.enabled, "actual enabled Installed Settings gear");
      button.clicked();
    } else if (route === "bar-service") {
      BarService.openPluginSettings(Quickshell.screens[0], api.manifest);
    } else {
      actorNext = next;
      actor.command = ["qs", "ipc", "-p", Quickshell.shellDir + "/plugin-settings-shared-routes.qml", "call", "plugin", "openSettings", "values-fixture"];
      actor.running = true;
    }
    phase = next;
  }
  function locatePopup() {
    if (route === "installed")
      return find(tab.item, item => typeof item.openInstanceSettings === "function");
    for (var key of Object.keys(PanelService.popupMenuWindows)) {
      var window = PanelService.popupMenuWindows[key];
      if (window.hasDialog && typeof window.popupContentItem?.openInstanceSettings === "function")
        return window.popupContentItem;
    }
    return null;
  }
  function attachPopup() {
    if (!popup) {
      popup = locatePopup();
      if (popup)
        popup.settingsCompleted.connect(function (result) {
          root.receipt = result;
        });
    }
    if (!popup?.opened || !popup.settingsPage)
      return false;
    check(popup._pageApi.scopeKind === "plugin" && popup._pageApi.runtimeContext === api.settingsContext, "explicit route must select the shared plugin context");
    return true;
  }
  function edit(value) {
    popup.settingsPage.labelControl.text = value;
    popup.settingsPage.labelControl.editCommitted();
    check(popup._pageApi.field("label").value === value, "real committed field intent");
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native shared Apply admitted");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && ["saved", "nothing_to_save"].indexOf(receipt.status) !== -1 && receipt.refreshState === "current";
  }
  function current(value) {
    check(siblingText.text === "sibling" && sibling.settingsView.legacy === "placement-content", "overridden sibling/content stay independent");
    return sharedText.text === value && inheritedText.text === value;
  }
  function drive() {
    if (phase === "ready" && inherited.settingsReady && sibling.settingsReady) {
      if (cold) {
        check(current("shared-retry") && !api.settingsPreviewOwner._token && !inherited.settingsPreviewOwner._token, "cold persisted shared and inherited consumers without preview");
        console.log("SHARED_ROUTES: COLD_PASS " + route);
        Qt.exit(0);
        return;
      }
      check(current("shared"), "initial independent runtime consumers");
      tab.active = route === "installed";
      phase = "host";
    } else if (phase === "host" && (route !== "installed" || tab.status === Loader.Ready)) {
      probe("initial", "open-discard");
    } else if (phase === "open-discard") {
      open("discard-page");
    } else if (phase === "discard-page" && attachPopup()) {
      check(!popup.dirty, "opening creates no field intent");
      edit("discarded-shared");
      check(!popup.requestClose() && popup.discardPending, "dirty shared Close refuses");
      popup.keepEditing();
      check(popup.settingsPage.labelField.value === "discarded-shared", "Keep retains input");
      check(popup.confirmDiscard(), "explicit nonpublishing discard");
      probe("discard", "open-edit");
    } else if (phase === "open-edit") {
      open("edit-page");
    } else if (phase === "edit-page" && attachPopup()) {
      edit("shared-edited");
      apply("edited");
    } else if (phase === "edited" && accepted() && current("shared-edited")) {
      probe("edited", "stage-reset");
    } else if (phase === "stage-reset") {
      check(popup.settingsPage.labelField.reset(), "native shared field Reset admitted");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && popup.settingsPage.labelField.pendingIntent === "reset") {
      check(popup.settingsPage.labelField.value === "default" && current("shared-edited"), "Reset exposes lower level without publishing");
      probe("reset_staged", "reset-apply");
    } else if (phase === "reset-apply") {
      apply("reset");
    } else if (phase === "reset" && accepted() && current("default")) {
      probe("reset", "stage-failure");
    } else if (phase === "stage-failure") {
      edit("shared-retry");
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      actorNext = "submit-failure";
      phase = "actor";
      actor.command = ["chmod", "500", Settings.configDir + "settings/plugins"];
      actor.running = true;
    } else if (phase === "submit-failure") {
      apply("failed");
    } else if (phase === "failed" && receipt && !popup.busy) {
      console.log("SHARED_ROUTE_FAILED_STATE " + JSON.stringify({
                                                                  status: receipt.status,
                                                                  refreshState: receipt.refreshState,
                                                                  error: receipt.error,
                                                                  saveFailed: popup.saveFailed,
                                                                  samePage: popup.settingsPage === failedPage,
                                                                  sameEditor: popup._editor === failedEditor,
                                                                  shared: sharedText.text,
                                                                  inherited: inheritedText.text,
                                                                  sibling: siblingText.text
                                                                }));
      check(receipt.status === "failed" && popup.saveFailed, "real IO failure is not acknowledged");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "IO failure retains exact input/editor");
      check(inheritedText.text === "default" && siblingText.text === "sibling", "failed shared publication cannot update inherited placement consumers");
      check(popup.settingsPage.labelField.value === "shared-retry", "failed native desired input remains readable for Retry");
      check(!popup.requestClose() && popup.discardPending, "failed shared Close refuses");
      popup.keepEditing();
      probe("failed", "restore");
    } else if (phase === "restore") {
      actorNext = "retry-apply";
      phase = "actor";
      actor.command = ["chmod", "700", Settings.configDir + "settings/plugins"];
      actor.running = true;
    } else if (phase === "retry-apply") {
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Retry retains exact selected shared owner");
      apply("retry");
    } else if (phase === "retry" && accepted() && current("shared-retry")) {
      probe("retry", "finish");
    } else if (phase === "finish") {
      check(popup.requestClose(), "clean shared Close admitted");
      console.log("SHARED_ROUTES: PASS " + route);
      Qt.exit(0);
    }
  }
  Process {
    id: actor
    stdout: StdioCollector {
      onStreamFinished: {
        if (text)
          console.log(text);
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text)
          console.error(text);
      }
    }
    onExited: code => {
      try {
        root.check(code === 0, "real IPC/permission actor exit");
        if (root.phase === "actor")
          root.phase = root.actorNext;
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Process {
    id: disk
    stdout: StdioCollector {
      onStreamFinished: {
        if (text)
          console.log(text);
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text)
          console.error(text);
      }
    }
    onExited: code => {
      try {
        root.check(code === 0, "independent complete native-document boundary");
        root.phase = root.afterProbe;
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 80
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
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("SHARED_ROUTE_ASSERT: watchdog " + phase)
  }
  Component.onCompleted: begin()
}
