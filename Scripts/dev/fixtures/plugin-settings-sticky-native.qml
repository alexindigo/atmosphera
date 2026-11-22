import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_STICKY_CASE")
  readonly property string scope: Quickshell.env("PHA_STICKY_SCOPE")
  readonly property string mode: Quickshell.env("PHA_STICKY_MODE")
  property var api: null
  property var instance: null
  property var main: null
  property var panel: null
  property var receipt: null
  property bool started: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/sticky-notes/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/sticky-notes/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: marker
    path: root.base + "/marker"
  }
  Process {
    id: capture
    onExited: code => {
      try {
        check(code === 0, "full guest screenshot");
        check(popup.requestClose(), "capture is nonediting");
        finish();
      } catch (error) {
        fail(error);
      }
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 900
    Item {
      id: content
      width: 1200
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("STICKY_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
      if (!list || typeof list.length !== "number")
        continue;
      for (let i = 0; i < list.length; i++) {
        const found = find(list[i], predicate, seen);
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
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "sticky-notes": descriptor
    };
    Service._openSettingsOwner("sticky-notes", owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI("sticky-notes", descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          "sticky-notes": {
            api: api
          }
        };
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject("sticky-notes", "main", component, content, api, {});
        check(main, "actual Main");
        api.mainInstance = main;
        instance = PluginInstances.apiFor("sticky-notes", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, instance, "settings"), "actual page");
    phase = after;
  }
  function tokenControl() {
    return find(popup.settingsPage, item => item.placeholderText === api.tr("settings.githubToken.placeholder"));
  }
  function edit(value) {
    const control = tokenControl();
    check(control, "actual token control");
    control.text = value;
    control.editCommitted();
  }
  function accepted() {
    return receipt && !popup.busy && (receipt.status === "saved" || receipt.status === "nothing_to_save") && receipt.refreshState === "current";
  }
  function resetField(key) {
    const field = popup._pageApi.field(key);
    const chrome = find(popup.settingsPage, item => item.field === field);
    const button = find(chrome, item => item.text === I18n.tr("common.reset"));
    check(button && button.enabled, "actual shared field Reset button");
    button.clicked();
  }
  function finish() {
    console.log("STICKY_CONSUMER " + JSON.stringify({
                                                      notes: main.loadStoredNotes(),
                                                      message: main.lastSyncMessage,
                                                      ok: main.lastSyncOk
                                                    }));
    main.destroy();
    main = null;
    phase = "joined";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite phase");
    if (phase === "runtime" && instance.settingsReady) {
      const component = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
      check(component.status === Component.Ready, component.errorString());
      panel = PluginLoader.createObject("sticky-notes", "panel", component, content, instance, {});
      check(panel && panel._lastLoadedJson.indexOf("shared-note") !== -1, "actual Panel reads common notes, not placement content");
      check(find(panel, item => typeof item.text === "string" && item.text.indexOf("shared-note") !== -1), "actual rendered note child");
      if (mode === "cold")
        finish();
      else if (["replace", "target-replace", "destroy", "original-replace", "busy"].indexOf(mode) !== -1) {
        const notes = main.loadStoredNotes();
        main.syncNotesToGist(notes, false);
        notes[0].content = "unadmitted-later-content";
        phase = "held";
      } else if (["create", "find", "failure", "missing"].indexOf(mode) !== -1) {
        main.manualSync();
        phase = "direct";
      } else
        open("page");
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "opening nonpublishing");
      check(tokenControl(), "actual token input");
      if (mode === "capture") {
        phase = "capture-ready";
      } else if (mode === "reset") {
        if (scope === "instance")
          check(popup.resetInstanceSettings(), "whole instance configuration Reset");
        else {
          resetField("githubToken");
        }
        phase = scope === "instance" ? "reset" : "reset-token-staged";
      } else if (mode === "original") {
        check(scope === "instance" && tokenControl().enabled, "original exposes ineffective independent credentials");
        edit("selected-token");
        popup.settingsPage.requestSync();
        check(popup.applySettings(), "original selected Apply");
        phase = "sync";
      } else if (scope === "instance") {
        check(!tokenControl().enabled, "shared credential cannot be offered as an independent instance choice");
        edit("rejected-token");
        check(!popup._pageApi.field("githubToken").pendingIntent, "disabled handler refuses instance token intent");
        check(find(popup.settingsPage, item => typeof item.text === "string" && item.text.indexOf("shared notes") !== -1), "truthful shared resource description");
        popup.settingsPage.requestSync();
        check(popup.applySettings(), "accepted instance completion gates explicit shared action");
        phase = "sync";
      } else {
        edit("discarded-token");
        check(!popup.requestClose(), "dirty Close refuses");
        popup.confirmDiscard();
        phase = "discarded";
      }
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      open("edit");
    else if (phase === "edit" && popup.opened && popup.settingsPage) {
      check(api.pluginSettings.githubToken === "shared-token", "Discard preserves live credentials");
      edit("edited-token");
      const toggle = find(popup.settingsPage, item => item.label === api.tr("settings.syncEnabled.label") && typeof item.toggled === "function");
      check(toggle, "actual shared automatic-sync toggle");
      toggle.toggled(true);
      popup.settingsPage.requestSync();
      check(popup.applySettings(), "shared native Apply");
      phase = "sync";
    } else if (phase === "sync" && accepted() && !main.syncInProgress && main.lastSyncAt > 0) {
      check(main.lastSyncOk, "actual Gist update completes");
      console.log(mode === "original" ? "STICKY_ORIGINAL: REPRODUCED" : "STICKY_NATIVE: PASS " + scope);
      check(popup.requestClose(), "clean Close");
      finish();
    } else if (phase === "held") {
      marker.reload();
      marker.waitForJob();
      if (marker.text().trim() !== "held")
        return;
      check(main.syncInProgress, "actual request held");
      if (mode === "destroy") {
        main.destroy();
        main = null;
      } else if (mode === "busy")
        main.manualSync();
      else {
        if (mode === "target-replace")
          api.pluginSettings.githubGistId = "replacement-gist";
        else
          api.pluginSettings.githubToken = "replacement-token";
        api.saveSettings(result => {
          check(result.status === "saved", "replacement publication");
        });
      }
      marker.setText("release");
      phase = "released";
    } else if (phase === "released" && Date.now() - since > 700) {
      if (main) {
        check(!main.syncInProgress && (["original-replace", "busy"].indexOf(mode) !== -1 ? main.lastSyncOk : !main.lastSyncOk), "retired sync settles without late success (original reproduces late success)");
        main.destroy();
        main = null;
      }
      console.log("STICKY_LIFETIME: PASS " + mode);
      phase = "joined";
    } else if (phase === "direct" && !main.syncInProgress && main.lastSyncAt > 0) {
      check(main.lastSyncOk === (mode === "create" || mode === "find"), "actual shared operation outcome");
      console.log("STICKY_OPERATION: PASS " + mode);
      finish();
    } else if (phase === "reset" && accepted()) {
      check(main.lastSyncAt === 0, "configuration Reset is not a content/sync action");
      console.log("STICKY_RESET: PASS " + scope);
      finish();
    } else if (phase === "reset-token-staged" && !popup._editor.busy && popup._pageApi.field("githubToken").pendingIntent === "reset") {
      resetField("syncEnabled");
      phase = "reset-toggle-staged";
    } else if (phase === "reset-toggle-staged" && !popup._editor.busy && popup._pageApi.field("syncEnabled").pendingIntent === "reset") {
      receipt = null;
      check(popup.applySettings(), "shared Reset Apply");
      phase = "reset";
    } else if (phase === "capture-ready" && popup.visible && popup.height > 0 && Date.now() - since > 400) {
      capture.command = ["grim", "-o", Quickshell.screens[0].name, Quickshell.env("PHA_STICKY_CAPTURE")];
      phase = "capturing";
      capture.running = true;
    } else if (phase === "joined" && Date.now() - since > 300) {
      driver.stop();
      console.log("STICKY: PASS " + scope + " " + mode);
      Qt.exit(0);
    }
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 40
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
