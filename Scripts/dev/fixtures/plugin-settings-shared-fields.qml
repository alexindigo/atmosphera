// Plugin-level field handles over the actual shared draft, Catwalk page and
// inheriting instance consumers. Reset reveals the native lower level.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var a: null
  property var b: null
  property var main: null
  property var slider: null
  property var receipt: null
  property var stagedValue: undefined
  readonly property bool cold: Quickshell.env("PHA_SHARED_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/catwalk/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: sharedFile
    path: Settings.configDir + "settings/plugins/catwalk.json"
    blockLoading: true
    printErrors: false
  }
  Process {
    id: typing
    onExited: function (code) {
      if (code !== 0)
        root.fail("keyboard injector failed");
    }
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: function (result) {
        root.receipt = result;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("SHARED_FIELDS_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function stored() {
    sharedFile.reload();
    sharedFile.waitForJob();
    return JSON.parse(sharedFile.text());
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children, object?.resources]) {
      if (!list)
        continue;
      for (var i = 0; i < list.length; i++) {
        var result = find(list[i], predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function fieldChrome(field) {
    return find(popup.settingsPage, function (item) {
      return item.field === field && item.content !== undefined;
    });
  }
  function resetButton(chrome) {
    return find(chrome, function (item) {
      return item.text === I18n.tr("common.reset") && typeof item.clicked === "function";
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      catwalk: manifest
    };
    Service._openSettingsOwner("catwalk", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI("catwalk", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          catwalk: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        main = PluginLoader.createObject("catwalk", "main", component, host.contentItem, api, {});
        api.mainInstance = main;
        if (cold) {
          openConsumers();
          return;
        }
        Settings.data.bar.widgets.left = [
              {
                id: "plugin:catwalk"
              },
              {
                id: "plugin:catwalk",
                instanceSettings: {
                  minimumThreshold: 20
                }
              }
            ];
        Settings.saveSelected([["bar", "widgets", "left"]], function (result) {
          try {
            check(result.status !== "failed", "seed persisted");
            openConsumers();
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  function openConsumers() {
    a = PluginInstances.apiFor("catwalk", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 0
                               });
    b = PluginInstances.apiFor("catwalk", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 1
                               });
    phase = "consumers";
  }
  function open() {
    receipt = null;
    check(popup.openPluginSettings(api.manifest, "settings"), "actual shared page");
  }
  function drive() {
    if (phase === "consumers" && a.settingsReady && b.settingsReady && api.settingsReady) {
      if (cold) {
        check(api.pluginSettings.minimumThreshold === 10, "cold shared lower level after Reset");
        check(a.pluginSettings.minimumThreshold === 10 && b.pluginSettings.minimumThreshold === 20, "cold inheriting/overridden instances");
        check(api.pluginSettings.hideBackground === true, "cold unrelated plugin override retained");
        console.log("SHARED_FIELDS: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(a.pluginSettings.minimumThreshold === 14 && b.pluginSettings.minimumThreshold === 20, "seeded inheritance");
      open();
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup.isInstance && popup._pageApi.scopeKind === "plugin", "plugin scope page");
      check(!popup._editor.dirty && !popup.dirty, "page construction submits no intent");
      var threshold = popup._pageApi.field("minimumThreshold");
      var background = popup._pageApi.field("hideBackground");
      check(threshold.overridden && threshold.value === 14, "stored plugin override presented");
      check(background.overridden && background.value === true, "second stored plugin override presented");
      check(popup._pageApi.contentField("minimumThreshold") === null, "configuration field has no content capability");
      slider = find(popup.settingsPage, function (item) {
        return item.objectName === "settings-range-valueMinimumThreshold";
      });
      check(slider !== null && slider.value === 14, "actual slider shows effective plugin value");
      slider.forceActiveFocus();
      check(slider.activeFocus, "native slider focus");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "Right", "-k", "Right"];
      typing.running = true;
      phase = "keyboard";
    } else if (phase === "keyboard" && !typing.running && slider.value === 16) {
      var field = popup._pageApi.field("minimumThreshold");
      check(field.pendingIntent === "set", "keyboard submits explicit field intent");
      check(api.pluginSettings.minimumThreshold === 14 && a.pluginSettings.minimumThreshold === 14, "no publication before Apply");
      check(popup.applySettings(), "Apply plugin-level value");
      phase = "applied";
    } else if (phase === "applied" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted shared receipt " + JSON.stringify(receipt));
      check(stored().minimumThreshold === 16 && stored().opaque.keep === true, "shared writable file");
      phase = "propagating";
    } else if (phase === "propagating" && a.pluginSettings.minimumThreshold === 16) {
      check(b.pluginSettings.minimumThreshold === 20, "inheriting instance propagates, override stays");
      var applied = popup._pageApi.field("minimumThreshold");
      check(applied.pendingIntent === "" && applied.overridden, "recaptured after accepted Apply");
      var button = resetButton(fieldChrome(applied));
      check(button !== null && button.enabled, "actual field Reset control");
      button.clicked();
      phase = "staging";
    } else if (phase === "staging" && popup._pageApi.field("minimumThreshold").pendingIntent === "reset") {
      check(popup._pageApi.field("minimumThreshold").value === 10, "native lower level presented while staged");
      check(slider.value === 10, "actual control shows native lower level");
      check(api.pluginSettings.minimumThreshold === 16 && stored().minimumThreshold === 16, "staging publishes nothing");
      check(!popup.requestClose() && popup.discardPending, "staged Reset is dirty");
      check(popup.confirmDiscard(), "explicit Discard");
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor) {
      check(api.pluginSettings.minimumThreshold === 16 && stored().minimumThreshold === 16 && a.pluginSettings.minimumThreshold === 16, "Discard leaves stored override");
      open();
      phase = "reopen";
    } else if (phase === "reopen" && popup.opened && popup.settingsPage) {
      var again = popup._pageApi.field("minimumThreshold");
      check(again.overridden && again.value === 16 && !popup.dirty, "reopened shared capture");
      check(again.reset(), "stage plugin field Reset");
      phase = "restaging";
    } else if (phase === "restaging" && popup._pageApi.field("minimumThreshold").pendingIntent === "reset") {
      receipt = null;
      check(popup.applySettings(), "Apply staged Reset");
      phase = "reset-applied";
    } else if (phase === "reset-applied" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted Reset receipt");
      var values = stored();
      check(!("minimumThreshold" in values) && values.hideBackground === true && values.opaque.keep === true, "writable source removal only");
      check(api.pluginSettings.minimumThreshold === 10, "lower level is the effective plugin value");
      phase = "reset-propagating";
    } else if (phase === "reset-propagating" && a.pluginSettings.minimumThreshold === 10) {
      check(b.pluginSettings.minimumThreshold === 20, "lower level reaches inheriting consumer only");
      var after = popup._pageApi.field("minimumThreshold");
      check(!after.overridden && after.pendingIntent === "", "recaptured inherited state");
      check(popup.requestClose(), "clean Close");
      console.log("SHARED_FIELDS: PASS");
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
    interval: 45000
    running: true
    onTriggered: root.fail("shared fields watchdog " + phase)
  }
  Component.onCompleted: begin()
}
