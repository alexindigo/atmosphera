import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.Bar as BarSettings
import qs.Modules.Panels.Settings.Tabs.Bar as BarTabs
import qs.Modules.Panels.Settings.Tabs.ControlCenter as ControlTabs
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string route: Quickshell.env("PHA_ROUTE")
  readonly property bool cold: Quickshell.env("PHA_ROUTE_COLD") === "1"
  readonly property string coldBoundary: Quickshell.env("PHA_ROUTE_BOUNDARY") || "replacement"
  readonly property bool controlRoute: route.startsWith("control-")
  readonly property string section: route === "control-right" ? "right" : "left"
  readonly property var placement: controlRoute ? {
                                                    kind: "controlCenter",
                                                    section: section,
                                                    index: 0
                                                  } : {
  kind: "bar",
  list: route === "monitor-bar" ? Quickshell.screens[0].name : "global",
  section: "left",
  index: 0
}
property bool started: false
property string phase: "initial"
property string afterProbe: ""
property var api: null
property var selected: null
property var sibling: null
property var manifest: null
property var popup: null
property var sectionEditor: null
property var receipt: null
property var failedPage: null
property var failedEditor: null
FileView {
  id: manifestFile
  path: Settings.configDir + "plugins/values-fixture/manifest.json"
  blockLoading: true
  printErrors: false
}
PanelWindow {
  id: host
  visible: !root.cold
  implicitWidth: 1280
  implicitHeight: 900
  Loader {
    id: tab
    anchors.fill: parent
    active: false
    sourceComponent: root.controlRoute ? controlTab : root.route === "global-bar" ? barTab : monitorTab
  }
}
Component {
  id: barTab
  BarTabs.BarTab {}
}
Component {
  id: controlTab
  ControlTabs.ControlCenterTab {}
}
Component {
  id: monitorTab
  BarSettings.MonitorWidgetsConfig {
    screen: Quickshell.screens[0]
  }
}
Text {
  id: selectedText
  text: root.selected?.settingsView?.label ?? ""
}
Text {
  id: siblingText
  text: root.sibling?.settingsView?.label ?? ""
}
Text {
  id: sharedText
  text: root.api?.settingsView?.label ?? ""
}
function check(ok, message) {
  if (!ok)
    throw new Error("ENTRY_ROUTE_ASSERT: " + phase + " " + message);
}
function fail(error) {
  console.error(String(error) + "\n" + (error.stack || ""));
  Qt.exit(2);
}
function find(object, predicate) {
  if (object && predicate(object))
    return object;
  for (var list of [object?.data, object?.children, object?.resources]) {
    if (!list)
      continue;
    for (var i = 0; i < list.length; i++) {
      var found = find(list[i], predicate);
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
  manifest = JSON.parse(manifestFile.text());
  Registry.installedPlugins = {
    "values-fixture": manifest
  };
  Service._openSettingsOwner("values-fixture", function (owner) {
    try {
      check(!!owner, "native owner");
      api = Service.createPluginAPI("values-fixture", manifest, owner, {}, {}, {});
      Service.loadedPlugins = {
        "values-fixture": {
          api: api
        }
      };
      selected = PluginInstances.apiFor("values-fixture", placement);
      sibling = PluginInstances.apiFor("values-fixture", Object.assign({}, placement, {
                                                                         index: 1
                                                                       }));
      phase = "ready";
    } catch (error) {
      fail(error);
    }
  });
}
function originalLabel() {
  return route === "monitor-bar" ? "monitor" : controlRoute ? route : "global";
}
function open(next) {
  receipt = null;
  // This is the section editor's public gear handler, not a synthetic popup
  // factory or a direct call to the tab's private placement helper.
  sectionEditor.openWidgetSettings(0, sectionEditor.widgetModel[0]);
  phase = next;
}
function edit(label) {
  popup.settingsPage.labelControl.text = label;
  popup.settingsPage.labelControl.editCommitted();
  check(popup._pageApi.field("label").value === label, "actual control stages selected intent");
}
function apply(next) {
  receipt = null;
  check(popup.applySettings(), "native Apply admitted");
  phase = next;
}
function accepted() {
  if (!receipt || popup.busy)
    return false;
  check(["saved", "nothing_to_save"].indexOf(receipt.status) !== -1 && receipt.refreshState === "current" && !popup.saveFailed, "current selected receipt");
  return true;
}
function observe(boundary, next) {
  afterProbe = next;
  phase = "disk-" + boundary;
  disk.command = ["python3", "-B", Quickshell.env("PHA_ROUTE_PROBE"), Settings.configDir, boundary];
  disk.running = true;
}
function replaceSelected() {
  var address = PluginInstances.address(placement);
  var commands = Settings.createRecordListEditor(address.path, address.entry.slice(0, -1));
  check(!!commands, "captured replacement command");
  var admitted = commands.submit([
                                   {
                                     op: "remove",
                                     index: 0
                                   },
                                   {
                                     op: "insert",
                                     index: 0,
                                     value: {
                                       id: "plugin:values-fixture",
                                       tag: "replacement",
                                       instanceSettings: {
                                         label: "replacement"
                                       }
                                     }
                                   }
                                 ], function (result) {
                                   try {
                                     check(result.status === "admitted" && result.refreshState === "current", "same-ID replacement admitted at original owner");
                                     commands.detach();
                                     Settings.saveSelected([address.path], function (saved) {
                                       try {
                                         check(saved.status !== "failed", "replacement persisted");
                                         phase = "replacement";
                                       } catch (error) {
                                         fail(error);
                                       }
                                     });
                                   } catch (error) {
                                     fail(error);
                                   }
                                 });
  check(admitted, "replacement submitted");
  phase = "replacing";
}
function drive() {
  if (phase === "ready" && selected?.settingsReady && sibling?.settingsReady) {
    check(sharedText.text === "shared" && siblingText.text === "sibling-" + originalLabel(), "independent shared/sibling runtime");
    if (cold) {
      var expectedLabel = coldBoundary === "edited" ? "route-edited" : coldBoundary === "whole-reset" ? "shared" : coldBoundary === "retry" ? "route-retry" : "replacement";
      check(selectedText.text === expectedLabel && !selected.settingsPreviewOwner._token, "cold boundary consumer without leaked preview");
      check(selected.settingsView.amount === (coldBoundary === "edited" ? 9 : 7), "cold boundary unrelated configuration");
      check(selected.settingsView.legacy === (coldBoundary === "replacement" ? "shared-content" : "instance-content"), "cold protected content remains at its owner");
      console.log("PLUGIN_SETTINGS_ENTRY_ROUTES: COLD_PASS " + route + " " + coldBoundary);
      Qt.exit(0);
      return;
    }
    check(selectedText.text === originalLabel(), "selected original runtime");
    tab.active = true;
    phase = "tab";
  } else if (phase === "tab" && tab.status === Loader.Ready) {
    sectionEditor = find(tab.item, function (item) {
      return item.sectionId === section && typeof item.openWidgetSettings === "function" && item.widgetModel?.length === 2;
    });
    check(!!sectionEditor, "actual selected section editor");
    popup = find(tab.item, function (item) {
      return typeof item.openInstanceSettings === "function" && typeof item.applySettings === "function";
    });
    check(!!popup, "actual tab-owned generic popup");
    popup.settingsCompleted.connect(function (result) {
      root.receipt = result;
    });
    observe("initial", "open-discard");
  } else if (phase === "open-discard") {
    open("discard-page");
  } else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
    check(popup._pageApi.scopeKind === "instance" && popup._pageApi.runtimeContext === selected.settingsContext, "route captures exact selected instance");
    check(!popup.dirty && popup.settingsPage.labelField.overridden && popup.settingsPage.labelField.value === originalLabel(), "effective field and override metadata");
    edit("route-discard");
    check(!popup.requestClose() && popup.discardPending, "dirty Close refuses");
    popup.keepEditing();
    check(popup.settingsPage.labelField.value === "route-discard", "Keep retains input");
    check(popup.confirmDiscard(), "explicit discard");
    observe("discard", "open-edit");
  } else if (phase === "open-edit" && !popup.visible) {
    open("edit-page");
  } else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
    edit("route-edited");
    apply("edited");
  } else if (phase === "edited" && accepted() && selectedText.text === "route-edited") {
    observe("edited", "stage-field-reset");
  } else if (phase === "stage-field-reset") {
    check(popup.settingsPage.labelField.reset() && popup.settingsPage.labelField.value === "shared", "field Reset inherited presentation");
    apply("field-reset");
  } else if (phase === "field-reset" && accepted() && selectedText.text === "shared") {
    check(selected.settingsView.amount === 9 && !popup.settingsPage.labelField.overridden, "field Reset preserves unrelated override");
    observe("field-reset", "stage-whole-reset");
  } else if (phase === "stage-whole-reset") {
    receipt = null;
    check(popup.resetInstanceSettings(), "configuration Reset admitted");
    phase = "whole-reset";
  } else if (phase === "whole-reset" && accepted() && selected.settingsView.amount === 7 && popup.settingsPage) {
    check(selected.settingsView.legacy === "instance-content" && api.settingsView.legacy === "shared-content", "configuration Reset preserves protected content");
    observe("whole-reset", "stage-failure");
  } else if (phase === "stage-failure") {
    edit("route-retry");
    failedPage = popup.settingsPage;
    failedEditor = popup._editor;
    permissions.command = ["chmod", "500", Settings.configDir + "settings"];
    phase = "deny";
    permissions.running = true;
  } else if (phase === "failed" && receipt && !popup.busy) {
    check(receipt.status === "failed" && popup.saveFailed && popup.settingsPage === failedPage && popup._editor === failedEditor, "real IO failure retains exact page/editor");
    check(!popup.requestClose() && popup.discardPending, "failed Close refuses");
    popup.keepEditing();
    observe("failed", "restore");
  } else if (phase === "restore") {
    permissions.command = ["chmod", "700", Settings.configDir + "settings"];
    phase = "allow";
    permissions.running = true;
  } else if (phase === "retry" && accepted() && selectedText.text === "route-retry") {
    check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Retry keeps captured owner");
    observe("retry", "stage-replacement");
  } else if (phase === "stage-replacement") {
    edit("must-not-retarget");
    replaceSelected();
  } else if (phase === "replacement") {
    receipt = null;
    if (popup.applySettings())
      phase = "stale-receipt";
    else
      phase = "stale-refused";
  } else if (phase === "stale-receipt" && receipt && !popup.busy) {
    check(receipt.status === "failed" || receipt.refreshState !== "current", "stale replacement cannot acknowledge");
    phase = "stale-refused";
  } else if (phase === "stale-refused") {
    check(popup.settingsPage === failedPage && popup.settingsPage.labelField.value === "must-not-retarget", "replacement keeps readable local input");
    observe("replacement", "finish");
  } else if (phase === "finish") {
    check(popup.confirmDiscard(), "explicit stale discard");
    console.log("PLUGIN_SETTINGS_ENTRY_ROUTES: PASS " + route);
    Qt.exit(0);
  }
}
Process {
  id: disk
  stdout: StdioCollector {
    onStreamFinished: console.log(text)
  }
  stderr: StdioCollector {
    onStreamFinished: {
      if (text)
      console.error(text);
    }
  }
  onExited: code => {
    try {
      root.check(code === 0, "independent file boundary");
      root.phase = root.afterProbe;
    } catch (error) {
      root.fail(error);
    }
  }
}
Process {
  id: permissions
  onExited: code => {
    try {
      root.check(code === 0, "permission boundary");
      root.apply(root.phase === "deny" ? "failed" : "retry");
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
  interval: 60
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
Timer {
  interval: 90000
  running: true
  onTriggered: root.fail("ENTRY_ROUTE_ASSERT: watchdog " + root.phase)
}
Component.onCompleted: begin()
}
