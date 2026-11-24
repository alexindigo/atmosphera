// Catwalk actual Main/Bar/Desktop consumers with controlled CPU samples.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
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
  property var desktopA: null
  property var desktopA2: null
  property var desktopB: null
  property var barA: null
  property var barB: null
  property var slider: null
  property var receipt: null
  property var failedPage: null
  property var failedEditor: null
  property bool signalBeforeCallback: false
  readonly property bool cold: Quickshell.env("PHA_CATWALK_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/catwalk/manifest.json"
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
  Process {
    id: permissions
    onExited: function (code) {
      if (code !== 0) {
        root.fail("permission fixture failed");
        return;
      }
      root.receipt = null;
      root.check(popup.applySettings(), "Apply after permission boundary");
      root.phase = root.phase === "make-unwritable" ? "failed" : "retry";
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
      throw new Error("CATWALK_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function create(entry, selected) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var context = entry === "desktopWidget" ? {
                                                screen: Quickshell.screens[0],
                                                widgetData: {
                                                  id: "plugin:catwalk"
                                                },
                                                widgetIndex: 0
                                              } : {};
    // Known inherited desktop inputs at construction, as in the Todo witness.
    var item = entry === "desktopWidget" ? component.createObject(host.contentItem, Object.assign({
                                                                                                    pluginApi: selected
                                                                                                  }, context)) : PluginLoader.createObject("catwalk", entry, component, host.contentItem, selected, context);
    check(item !== null, "actual " + entry);
    return item;
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
        main = create("main", api);
        api.mainInstance = main;
        main.cpuUsage = 15;
        if (cold) {
          openConsumers();
          return;
        }
        Settings.data.bar.widgets.left = [
              {
                id: "plugin:catwalk",
                instanceSettings: {
                  minimumThreshold: 14,
                  opaque: {
                    keep: true
                  }
                }
              },
              {
                id: "plugin:catwalk",
                instanceSettings: {
                  minimumThreshold: 20,
                  hideBackground: true
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
  function states(runningA, backgroundA) {
    check(desktopA.isRunning === runningA && desktopA.showBackground === backgroundA && barA.isRunning === runningA, "selected A actual animation/background");
    check(!desktopB.isRunning && !desktopB.showBackground && !barB.isRunning, "sibling B distinct actual animation/background");
    check(desktopA.settingsConsumer === desktopA2.settingsConsumer && desktopA.settingsConsumer === barA.settingsConsumer, "one client per API across views");
    check(desktopA.settingsConsumer !== desktopB.settingsConsumer, "separate instance clients");
  }
  function drive() {
    if (phase === "consumers" && a.settingsReady && b.settingsReady) {
      desktopA = create("desktopWidget", a);
      desktopA2 = create("desktopWidget", a);
      desktopB = create("desktopWidget", b);
      barA = create("barWidget", a);
      barB = create("barWidget", b);
      states(true, true);
      if (cold) {
        check(a.pluginSettings.minimumThreshold === 10 && a.pluginSettings.hideBackground === false, "cold inherited config");
        console.log("CATWALK_SELECTED: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "real selected page");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty && !popup.dirty, "page construction submits no intent");
      check(popup._pageApi.runtimeContext === a.settingsContext, "page/consumer share captured identity");
      slider = find(popup.settingsPage, function (item) {
        return item.objectName === "settings-range-valueMinimumThreshold";
      });
      check(slider !== null, "actual slider");
      phase = "focus";
    } else if (phase === "focus") {
      slider.forceActiveFocus();
      check(slider.activeFocus, "native slider focus");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "Right", "-k", "Right"];
      typing.running = true;
      phase = "keyboard";
    } else if (phase === "keyboard" && !typing.running && slider.value === 16) {
      check(popup._pageApi.field("minimumThreshold").pendingIntent === "set", "keyboard submits explicit field intent");
      states(true, true);
      popup._pageApi.saveSettings(function (result) {
        root.signalBeforeCallback = root.receipt !== null && root.receipt.status === result.status;
      });
      check(popup.applySettings(), "Apply selected threshold");
      phase = "applied";
    } else if (phase === "applied" && receipt && !popup.busy && a.pluginSettings.minimumThreshold === 16) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted selected receipt");
      check(signalBeforeCallback, "completion signal precedes callback");
      states(false, true);
      var toggle = find(popup.settingsPage, function (item) {
        return item.label === api.tr("settings.hideBackground.label") && typeof item.toggled === "function";
      });
      check(toggle !== null, "actual background control");
      toggle.toggled(true);
      states(false, true);
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      permissions.command = ["chmod", "500", Settings.configDir + "settings"];
      phase = "make-unwritable";
      permissions.running = true;
    } else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.saveFailed, "IO failure not acknowledged");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Catwalk failure retains selected page/editor");
      check(!popup.requestClose() && popup.discardPending, "failed Close refuses");
      popup.keepEditing();
      permissions.command = ["chmod", "700", Settings.configDir + "settings"];
      phase = "make-writable";
      permissions.running = true;
    } else if (phase === "retry" && receipt && !popup.busy && a.pluginSettings.hideBackground) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "same-editor Retry current");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Catwalk Retry preserves capture");
      states(false, false);
      receipt = null;
      check(popup.resetInstanceSettings(), "configuration Reset");
      phase = "reset";
    } else if (phase === "reset" && receipt && !popup.busy && a.pluginSettings.minimumThreshold === 10) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted Reset");
      states(true, true);
      check(popup.requestClose(), "close accepted");
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      check(!desktopA.isRunning && !desktopB.isRunning, "retired clients no longer drive animation");
      console.log("CATWALK_SELECTED: PASS");
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
    onTriggered: root.fail("selected Catwalk watchdog " + phase)
  }
  Component.onCompleted: begin()
}
