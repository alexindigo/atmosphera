// Actual selected page, native owner, Bar/Desktop AQI and held curl endpoint.
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
  property int stage: 0
  property var api: null
  property var a: null
  property var b: null
  property var main: null
  property var clientA: null
  property var clientB: null
  property var desktop: null
  property var bar: null
  property var input: null
  property var receipt: null
  property var retiredWorker: null
  property int stableTicks: 0
  readonly property bool cold: Quickshell.env("PHA_AIR_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/air-quality/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: barrier
    path: Quickshell.env("PHA_HOLD_ROOT") + "/entered"
    watchChanges: true
    printErrors: false
  }
  Process {
    id: actor
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Item {
      id: left
      width: 500
      height: 700
    }
    Item {
      id: right
      x: 550
      width: 500
      height: 700
    }
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
      throw new Error("AIR_SELECTED_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children, object?.resources]) {
      if (!list)
        continue;
      for (var i = 0; i < list.length; i++) {
        var item = find(list[i], predicate);
        if (item)
          return item;
      }
    }
    return null;
  }
  function create(entry, parent, selected) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var context = entry === "desktopWidget" ? {
                                                widgetData: {
                                                  id: "plugin:air-quality",
                                                  scale: 1
                                                },
                                                widgetIndex: 0,
                                                screen: Quickshell.screens[0]
                                              } : {
      screen: Quickshell.screens[0]
    };
    // Supply known inherited desktop inputs at native construction, as in the
    // Todo/Catwalk witnesses. The separate late-context loader matrix is not
    // certified here; do not hide its pre-existing null-context diagnostic.
    var item = entry === "desktopWidget" ? component.createObject(parent, Object.assign({
                                                                                          pluginApi: selected
                                                                                        }, context)) : PluginLoader.createObject("air-quality", entry, component, parent, selected, context);
    check(item !== null, "actual " + entry);
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "air-quality": manifest
    };
    Service._openSettingsOwner("air-quality", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI("air-quality", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "air-quality": {
            api: api
          }
        };
        main = create("main", root, api);
        api.mainInstance = main;
        if (cold) {
          openConsumers();
          return;
        }
        Settings.data.bar.widgets.left = [
              {
                id: "plugin:air-quality"
              },
              {
                id: "plugin:air-quality",
                instanceSettings: {
                  aqiScale: "eu"
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
    a = PluginInstances.apiFor("air-quality", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 0
                               });
    b = PluginInstances.apiFor("air-quality", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 1
                               });
    phase = "ready";
  }
  function text(object, value) {
    return find(object, item => item.text === value) !== null;
  }
  function siblings() {
    check(main.hasData && main.getAqi() === 17, "shared source remains original");
    check(clientB.hasData && clientB.getAqi() === 9 && text(bar, "9"), "sibling scale and rendered AQI remain distinct");
    check(clientA === main.settingsConsumerFor(a.settingsContext) && clientA !== clientB, "one stable client per API");
  }
  function drive() {
    if (phase === "ready" && a.settingsReady && b.settingsReady) {
      clientA = main.settingsConsumerFor(a.settingsContext);
      clientB = main.settingsConsumerFor(b.settingsContext);
      check(clientB.aqiScale === "eu", "selected configuration cannot read shared Main");
      desktop = create("desktopWidget", left, a);
      bar = create("barWidget", right, b);
      phase = "initial";
    } else if (phase === "initial" && main.hasData && clientB.hasData && (cold ? !clientA.hasData && clientA.errorMessage.length > 0 : clientA.hasData)) {
      siblings();
      check(text(desktop, cold ? "--" : "17"), "actual desktop AQI text");
      if (cold) {
        console.log("AIR_SELECTED: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "selected page opens");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty, "construction submits no intent");
      var control = find(popup.settingsPage, item => item.label === api.tr("settings.customLatitude") && item.inputItem !== undefined);
      check(control !== null, "actual latitude input");
      input = control.inputItem;
      phase = "focus";
    } else if (phase === "focus") {
      input.forceActiveFocus();
      input.selectAll();
      check(input.activeFocus && input.selectionEnd === input.text.length, "actual focus and selection");
      actor.command = stage < 2 ? [Quickshell.env("PHA_INPUT_INJECTOR"), "--", "3"] : [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "BackSpace"];
      actor.running = true;
      phase = "typing";
    } else if (phase === "typing" && !actor.running && input.text === (stage < 2 ? "3" : "")) {
      siblings();
      if (stage < 2)
        check(clientA.getAqi() === 17 && text(desktop, "17"), "typing cannot refresh selected query");
      if (stage === 0) {
        check(!popup.requestClose() && popup.discardPending, "dirty Close refuses");
        popup.keepEditing();
        check(popup.confirmDiscard(), "explicit discard");
        phase = "discarded";
      } else if (stage === 1) {
        actor.command = ["chmod", "500", Settings.configDir + "settings"];
        actor.running = true;
        phase = "blocked";
      } else {
        receipt = null;
        check(popup.applySettings(), "clear incomplete latitude Apply");
        phase = "cleared";
      }
    } else if (phase === "discarded" && !popup.visible) {
      check(clientA.getAqi() === 17 && text(desktop, "17"), "discard retains original consumer");
      stage = 1;
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "reopen");
      phase = "page";
    } else if (phase === "blocked" && !actor.running) {
      receipt = null;
      check(popup.applySettings(), "admit actual IO failure");
      phase = "failed";
    } else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed", "actual failed persistence receipt");
      check(clientA.cfg.customLatitude === "1" && clientA.hasData && clientA.getAqi() === 17, "failed receipt cannot refresh or replace admitted selected configuration");
      check(!popup.requestClose() && popup.settingsPage !== null, "failed Close retains page");
      popup.keepEditing();
      siblings();
      actor.command = ["chmod", "700", Settings.configDir + "settings"];
      actor.running = true;
      phase = "retry";
    } else if (phase === "retry" && !actor.running) {
      receipt = null;
      check(popup.applySettings(), "same editor Retry");
      phase = "applied";
    } else if (phase === "applied" && receipt && !popup.busy && clientA.hasData && text(desktop, "151")) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted current Apply");
      siblings();
      actor.command = ["touch", Quickshell.env("PHA_HOLD_ROOT") + "/hold"];
      actor.running = true;
      phase = "hold-start";
    } else if (phase === "hold-start" && !actor.running) {
      retiredWorker = clientA._worker;
      clientA.refresh();
      phase = "held";
    } else if (phase === "held") {
      barrier.reload();
      barrier.waitForJob();
      if (barrier.text().trim() !== "entered")
        return;
      check(clientA.loading, "old location request held");
      stage = 2;
      phase = "focus";
    } else if (phase === "cleared" && receipt && !popup.busy && !clientA.hasData && clientA.errorMessage.length > 0) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "incomplete location accepted as preference");
      check(text(desktop, "--"), "incomplete replacement removes old AQI");
      siblings();
      check(!retiredWorker || !retiredWorker.active, "old worker generation retired");
      actor.command = ["touch", Quickshell.env("PHA_HOLD_ROOT") + "/release"];
      actor.running = true;
      phase = "stable";
    } else if (phase === "stable" && !actor.running) {
      check(!clientA.hasData && text(desktop, "--"), "old held response cannot repopulate replacement");
      siblings();
      if (++stableTicks < 12)
        return;
      check(popup.requestClose(), "clean Close");
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      check(!desktop.hasData && !text(bar, "9"), "retired consumers no longer present data");
      console.log("AIR_SELECTED: PASS");
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
    onTriggered: root.fail("selected Air watchdog " + phase)
  }
  Component.onCompleted: begin()
}
