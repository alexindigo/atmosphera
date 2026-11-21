// Actual IPC -> one Main session -> actual Panel -> disk result/callback.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string mode: Quickshell.env("PHA_DMENU_MODE")
  readonly property string caseDir: Quickshell.env("PHA_DMENU_CASE")
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var main: null
  property var panel: null
  property int notices: 0
  property int opens: 0
  property int closes: 0
  property var receipt: null
  property string actorNext: "admitted"
  property string afterDisk: ""
  property string diskBoundary: ""
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/dmenu/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/dmenu/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: resultFile
    path: root.caseDir + "/results/policy"
    printErrors: false
  }
  FileView {
    id: callbackFile
    path: root.caseDir + "/results/callback"
    printErrors: false
  }
  FileView {
    id: noticeFile
    path: root.caseDir + "/results/notice"
    printErrors: false
  }
  Process {
    id: actor
    onExited: code => {
      if (code !== 0)
        root.fail("actual IPC exit " + code);
      else
        root.phase = root.actorNext;
    }
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent native documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices++;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 700
    implicitHeight: 800
    Item {
      id: content
      anchors.fill: parent
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("DMENU_ASSERT: " + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function create(entry) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("dmenu", entry, component, content, api, {});
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function probe(boundary, next) {
    afterDisk = next;
    diskBoundary = boundary;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_DMENU_DISK"), caseDir, Quickshell.env("PHA_DMENU_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function editControls() {
    var position = find(popup.settingsPage, item => item.label === api.tr("settings.panelPosition") && item.selected !== undefined);
    check(position, "actual position combo");
    position.selected("top_right");
    for (var key of ["showMatchCount", "showFooter", "showToastOnSelect"]) {
      var label = key === "showToastOnSelect" ? "showToast" : key;
      var toggle = find(popup.settingsPage, item => item.label === api.tr("settings." + label) && item.toggled !== undefined);
      check(toggle, "actual toggle " + key);
      toggle.toggled(key === "showToastOnSelect");
    }
    var path = find(popup.settingsPage, item => item.label === api.tr("settings.resultFile") && item.editCommitted !== undefined);
    check(path, "actual result file input");
    path.text = caseDir + "/results/policy";
    path.editCommitted();
    var range = find(popup.settingsPage, item => item.objectName === "settings-range-editMaxResults");
    check(range, "actual result limit slider");
    range.value = 50;
    range.moved();
    check(!popup._pageApi.field("customInputPrefix").pendingIntent, "hidden prefix untouched by page");
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      dmenu: manifest
    };
    Service._openSettingsOwner("dmenu", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("dmenu", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          dmenu: {
            api: api
          }
        };
        // Inert screen/panel collaborators; actual plugin IPC, Main and Panel stay unchanged.
        api.withCurrentScreen = callback => callback(Quickshell.screens[0]);
        api.openPanel = screen => {
          root.opens++;
          api.panelOpenScreen = screen;
        };
        api.closePanel = screen => {
          root.closes++;
          api.panelOpenScreen = null;
        };
        main = create("main");
        api.mainInstance = main;
        panel = create("panel");
        phase = mode === "cold" ? "request" : "initial";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (!started || phase === "startup")
      return;
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase === "initial") {
      probe("initial", "discard-open");
    } else if (phase === "discard-open" || phase === "edit-open") {
      var discard = phase === "discard-open";
      check(popup.openPluginSettings(api.manifest, "settings"), "actual plugin-level page opens");
      phase = discard ? "discard-page" : "edit-page";
    } else if ((phase === "discard-page" || phase === "edit-page") && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no field intent");
      editControls();
      if (phase === "discard-page") {
        check(!popup.requestClose(), "dirty Close retains page");
        popup.confirmDiscard();
        phase = "discarded";
      } else {
        receipt = null;
        check(popup.applySettings(), "actual page native Apply");
        phase = "applied";
      }
    } else if (phase === "discarded" && !popup.opened && !popup._editor) {
      probe("discarded", "edit-open");
    } else if (phase === "applied" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "page acknowledges current native Apply");
      check(api.pluginSettings.maxResults === 50 && panel.configuredPosition === "top_right" && !panel.showFooter && !panel.showMatchCount, "actual Panel consumes all applied presentation fields");
      probe("edited", "request");
    } else if (phase === "request") {
      var rows = Array.from({
                              length: 60
                            }, (_, index) => "Alpha" + index);
      var config = {
        items: rows,
        allowCustomInput: true,
        showToastOnSelect: false,
        callbackCmd: "printf '%s' '{}' > '" + caseDir + "/results/callback'"
      };
      actor.command = ["qs", "ipc", "-p", Quickshell.shellDir + "/plugin-settings-dmenu-session.qml", "call", "plugin:dmenu", "showJson", JSON.stringify(config)];
      phase = "ipc";
      actor.running = true;
    } else if (phase === "admitted" && main.state.active) {
      check(panel.filteredItems.length === 50 && panel.filteredItems[0].name === "Alpha0" && main.state.resultFile === caseDir + "/results/policy", "actual IPC captures page-applied limit and path");
      check(find(panel, item => item.text === "Alpha0") && !find(panel, item => item.text === "Alpha50"), "actual IPC row Text displays admitted item and limit");
      check(panel.configuredPosition === "top_right" && !panel.showFooter && !panel.showMatchCount, "actual Panel consumes persisted presentation fields");
      if (mode === "cold") {
        check(main.state.customInputPrefix === "later:" && !main.state.showToastOnSelect, "cold session captures persisted defaults plus explicit request policy");
        console.log("DMENU_SESSION: PASS cold");
        Qt.exit(0);
        return;
      }
      api.pluginSettings.customInputPrefix = "later:";
      api.pluginSettings.showToastOnSelect = true;
      phase = "saving";
      api.saveSettings(result => {
        root.receipt = result;
        root.probe("later", "saved");
      });
    } else if (phase === "saved") {
      check(receipt.status === "saved", "actual later native preferences saved");
      panel.filterText = "typed";
      check(panel.filteredItems.length === 1 && panel.filteredItems[0].isCustomInput, "actual Panel custom row");
      panel.activateItem(0);
      phase = "result";
    } else if (phase === "result") {
      resultFile.reload();
      callbackFile.reload();
      phase = "read";
    } else if (phase === "read") {
      if (!resultFile.loaded || !callbackFile.loaded) {
        phase = "result";
        return;
      }
      check(resultFile.text() === "captured:typed", "selection keeps admitted prefix after later preferences");
      check(callbackFile.text() === "captured:typed", "callback keeps admitted result");
      check(notices === 0, "explicit request toast false survives later shared true");
      check(!main.state.active, "selection ends its admitted session");
      actorNext = "notice-admitted";
      actor.command = ["qs", "ipc", "-p", Quickshell.shellDir + "/plugin-settings-dmenu-session.qml", "call", "plugin:dmenu", "showItems", "Notice", JSON.stringify({
                                                                                                                                                                      resultFile: caseDir + "/results/notice"
                                                                                                                                                                    })];
      phase = "ipc";
      actor.running = true;
    } else if (phase === "notice-admitted" && main.state.active) {
      check(main.state.showToastOnSelect, "new session captures enabled applied toast default");
      panel.activateItem(0);
      check(notices === 1, "actual enabled toast reaches notification consumer");
      noticeFile.reload();
      phase = "notice-result";
    } else if (phase === "notice-result") {
      noticeFile.reload();
      phase = "notice-read";
    } else if (phase === "notice-read" && !noticeFile.loaded) {
      phase = "notice-result";
    } else if (phase === "notice-read") {
      check(noticeFile.text() === "Notice", "positive toast session keeps independent result");
      console.log("DMENU_SESSION: PASS " + mode);
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
    interval: 80
    repeat: true
    running: true
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
