import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string family: Quickshell.env("PHA_INCARNATION_FAMILY")
  readonly property string change: Quickshell.env("PHA_INCARNATION_CHANGE")
  readonly property bool original: Quickshell.env("PHA_INCARNATION_ORIGINAL") === "1"
  property bool started: false
  property string phase: "opening"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var shared: null
  property var selected: null
  property var context: null
  property var next: null
  property string token: ""
  property var refusal: null
  property var placement: family === "global" ? {
                                                  kind: "bar",
                                                  list: "global",
                                                  section: "left",
                                                  index: 0
                                                } : family === "monitor" ? {
    kind: "bar",
    list: "INCARNATION",
    section: "left",
    index: 0
  } : family === "control" ? {
    kind: "controlCenter",
    section: "left",
    index: 0
  } : {
  kind: "desktop",
  screenName: "INCARNATION",
  index: 0
}
FileView {
  id: manifest
  path: Settings.configDir + "plugins/catwalk/manifest.json"
  blockLoading: true
}
function check(ok, label) {
  if (!ok)
    throw new Error("INCARNATION_ASSERT: " + family + "/" + change + "/" + phase + ": " + label);
}
function fail(error) {
  console.error(String(error));
  Qt.exit(2);
}
function rows() {
  if (family === "global")
    return Settings.data.bar.widgets.left;
  if (family === "monitor")
    return Settings.data.bar.screenOverrides[0].widgets.left;
  if (family === "control")
    return Settings.data.controlCenter.shortcuts.left;
  return Settings.data.desktopWidgets.monitorWidgets[0].widgets;
}
function replace(value) {
  if (family === "global")
    Settings.data.bar.widgets.left = value;
  else if (family === "monitor") {
    var monitors = Settings.store.copyValue(Settings.data.bar.screenOverrides);
    monitors[0].widgets.left = value;
    Settings.data.bar.screenOverrides = monitors;
  } else if (family === "control")
    Settings.data.controlCenter.shortcuts.left = value;
  else {
    var desktops = Settings.store.copyValue(Settings.data.desktopWidgets.monitorWidgets);
    desktops[0].widgets = value;
    Settings.data.desktopWidgets.monitorWidgets = desktops;
  }
}
function begin() {
  if (started || !Settings.isLoaded)
    return;
  started = true;
  manifest.waitForJob();
  var descriptor = JSON.parse(manifest.text());
  Registry.installedPlugins = {
    catwalk: descriptor
  };
  Service._openSettingsOwner("catwalk", function (owner) {
    try {
      check(owner, "native owner");
      shared = Service.createPluginAPI("catwalk", descriptor, owner, {}, {}, {});
      Service.loadedPlugins = {
        catwalk: {
          api: shared
        }
      };
      selected = PluginInstances.apiFor("catwalk", placement);
      phase = "ready";
    } catch (error) {
      fail(error);
    }
  });
}
function retired() {
  check(context.current() === false, "old incarnation explicitly false");
  var values = context.settingsView;
  check(Object.isFrozen(values) && Object.keys(values).length === 0, "old incarnation empty immutable read");
}
function drive() {
  check(Date.now() - since < 18000, "finite native operation");
  if (phase === "ready" && selected.settingsReady && shared.settingsReady) {
    context = selected.settingsContext;
    token = selected.runtime.placementToken;
    check(token && context.current() && context === selected.settingsContext, "stable initial native context");
    check(context.settingsView.minimumThreshold === 30, "selected initial values");
    var edited = Settings.store.copyValue(rows());
    edited[0].tag = "member-edited";
    edited[0].instanceSettings.minimumThreshold = 35;
    replace(edited);
    phase = "member";
  } else if (phase === "member" && selected.runtime.values.minimumThreshold === 35) {
    check(context.current() && selected.runtime.placementToken === token, "ordinary override/member edits retain incarnation");
    shared.pluginSettings.hideBackground = false;
    phase = "base-save";
    shared.saveSettings(function (result) {
      try {
        check(result.status !== "failed", "shared native save");
        phase = "base";
      } catch (error) {
        fail(error);
      }
    });
  } else if (phase === "base" && context.settingsView.hideBackground === false) {
    check(context.current() && selected.runtime.placementToken === token, "ordinary base publication retains incarnation");
    var changed = Settings.store.copyValue(rows());
    if (change === "remove")
      changed.shift();
    else if (change === "reorder")
      changed.reverse();
    else if (change === "insert")
      changed.unshift({
                        id: "plugin:catwalk",
                        tag: "inserted",
                        instanceSettings: {
                          minimumThreshold: 50
                        }
                      });
    else if (change === "identity")
      changed[0].id = "plugin:other";
    else
      changed = [];
    replace(changed);
    phase = "mapping-save";
    Settings.store.saveSelected([PluginInstances.address(placement).path], function (result) {
      try {
        check(result.status !== "failed", "owning mapping published");
        phase = "changed";
      } catch (error) {
        fail(error);
      }
    });
  } else if (phase === "changed" && selected.runtime.placementToken !== token) {
    if (original && context.settingsView.minimumThreshold !== 40)
      return;
    console.log("INCARNATION_OBSERVATION " + JSON.stringify({
                                                              family: family,
                                                              change: change,
                                                              before: token,
                                                              after: selected.runtime.placementToken,
                                                              current: context.current(),
                                                              value: context.settingsView.minimumThreshold
                                                            }));
    if (original) {
      check(change === "remove" && context.current() === true && context.settingsView.minimumThreshold === 40, "original follows replacement sibling");
      console.log("INCARNATION_RED: REPRODUCED " + family);
      Qt.exit(0);
      return;
    }
    retired();
    check(!selected.settingsReady && selected.settingsError === "overlay-identity", "API readiness fences incarnation");
    check(!selected.createSettingsEditor(true), "old editor cannot recapture index");
    check(!selected.createSettingsPreview(), "old preview cannot recapture index");
    check(selected.saveSettings(function (result) {
      root.refusal = result;
    }) === false, "old native save admission refuses");
    phase = "refusal";
  } else if (phase === "refusal" && refusal) {
    retired();
    check(refusal.status === "failed" && refusal.error.code === "overlay-identity", "explicit old-save identity failure");
    if (change === "identity" || change === "absent") {
      console.log("INCARNATION: PASS " + family + "/" + change);
      Qt.exit(0);
      return;
    }
    next = PluginInstances.apiFor("catwalk", placement);
    check(next !== selected, "cache creates new incarnation API");
    phase = "replacement";
  } else if (phase === "replacement" && next.settingsReady) {
    retired();
    check(next.settingsContext !== context && next.settingsContext.current(), "new incarnation independent context");
    check(next.settingsContext.settingsView.minimumThreshold === (change === "insert" ? 50 : 40), "new incarnation native values");
    console.log("INCARNATION: PASS " + family + "/" + change);
    Qt.exit(0);
  }
}
Connections {
  target: Settings
  function onSettingsLoaded() {
    root.begin();
  }
}
SettingsBootstrap {}
Timer {
  interval: 40
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
