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
  property var desktopA: null
  property var desktopB: null
  property var input: null
  property var receipt: null
  property int stableTicks: 0
  readonly property bool cold: Quickshell.env("PHA_CONTRIBUTIONS_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/github-contributions/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: barrier
    path: Quickshell.env("PHA_HOLD_ROOT") + "/entered"
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
      throw new Error("CONTRIBUTIONS_ASSERT: " + message);
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
        var found = find(list[i], predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, parent, selected) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    // Known inherited desktop context is supplied at native construction;
    // the separate production late-context loader matrix remains required.
    var item = entry === "desktopWidget" ? component.createObject(parent, {
                                                                    pluginApi: selected,
                                                                    screen: Quickshell.screens[0],
                                                                    widgetData: {
                                                                      id: "plugin:github-contributions"
                                                                    },
                                                                    widgetIndex: 0
                                                                  }) : PluginLoader.createObject("github-contributions", entry, component, parent, selected, {});
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
      "github-contributions": manifest
    };
    Service._openSettingsOwner("github-contributions", function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI("github-contributions", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "github-contributions": {
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
                id: "plugin:github-contributions"
              },
              {
                id: "plugin:github-contributions",
                instanceSettings: {
                  username: "synthetic-beta",
                  weeksShown: 10
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
    a = PluginInstances.apiFor("github-contributions", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 0
                               });
    b = PluginInstances.apiFor("github-contributions", {
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
    check(main.totalContributions === 7 && main.username === "synthetic-alpha", "shared account remains alpha");
    check(clientB.totalContributions === 29 && desktopB.weeksShown === 10 && desktopB.columns === 10, "sibling graph is independent");
    check(clientA === main.settingsConsumerFor(a.settingsContext) && clientA !== clientB, "stable per-context client");
  }
  function drive() {
    if (phase === "ready" && a.settingsReady && b.settingsReady) {
      clientA = main.settingsConsumerFor(a.settingsContext);
      clientB = main.settingsConsumerFor(b.settingsContext);
      check(clientB.username === "synthetic-beta", "selected account cannot read shared Main");
      desktopA = create("desktopWidget", left, a);
      desktopB = create("desktopWidget", right, b);
      phase = "initial";
    } else if (phase === "initial" && main.hasData && clientB.hasData && (cold ? !clientA.hasData && clientA.errorMessage.length > 0 : clientA.hasData)) {
      siblings();
      if (cold) {
        check(desktopA.slicedDays.length === 0 && !desktopA.hasData, "cold incomplete account has no old graph");
        console.log("CONTRIBUTIONS_SELECTED: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(desktopA.columns === 52 && text(desktopA, "@synthetic-alpha"), "actual initial graph and account");
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "actual selected Settings");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty, "opening emits no intent");
      phase = "focus";
    } else if (phase === "focus") {
      if (stage === 2) {
        input = find(popup.settingsPage, item => item.from === 4 && item.to === 53);
        check(input !== null, "actual week slider");
        input.forceActiveFocus();
        check(input.activeFocus, "actual week slider focus");
        // Qt Quick Slider's supported arrow gesture, independently used by
        // the Catwalk input witness; Home is not a Slider activation contract.
        var keys = [Quickshell.env("PHA_INPUT_INJECTOR")];
        for (var i = 0; i < 48; i++)
          keys.push("-k", "Left");
        actor.command = keys;
      } else {
        var label = api.tr(stage === 3 ? "settings.token.label" : "settings.username.label");
        var control = find(popup.settingsPage, item => item.label === label && item.inputItem !== undefined);
        check(control !== null, "actual text control");
        input = control.inputItem;
        input.forceActiveFocus();
        input.selectAll();
        check(input.activeFocus, "actual native focus");
        actor.command = stage === 4 ? [Quickshell.env("PHA_INPUT_INJECTOR"), "-k", "BackSpace"] : [Quickshell.env("PHA_INPUT_INJECTOR"), "--", stage === 3 ? "synthetic" : "synthetic-beta"];
      }
      actor.running = true;
      phase = "typing";
    } else if (phase === "typing" && !actor.running) {
      var wanted = stage === 2 ? input.value === 4 : input.text === (stage === 4 ? "" : stage === 3 ? "synthetic" : "synthetic-beta");
      if (!wanted)
        return;
      siblings();
      if (stage < 2)
        check(clientA.username === "synthetic-alpha" && desktopA.hasData, "typing does not publish account");
      if (stage === 0) {
        check(!popup.requestClose(), "dirty Close refuses");
        popup.keepEditing();
        check(popup.confirmDiscard(), "explicit discard");
        phase = "discarded";
      } else if (stage === 1) {
        actor.command = ["chmod", "500", Settings.configDir + "settings"];
        actor.running = true;
        phase = "blocked";
      } else {
        receipt = null;
        check(popup.applySettings(), "native field Apply");
        phase = "applied";
      }
    } else if (phase === "discarded" && !popup.visible) {
      check(clientA.username === "synthetic-alpha" && clientA.totalContributions === 7, "discard retains query and graph");
      stage = 1;
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "reopen selected page");
      phase = "page";
    } else if (phase === "blocked" && !actor.running) {
      receipt = null;
      check(popup.applySettings(), "admit real IO failure");
      phase = "failed";
    } else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && clientA.username === "synthetic-alpha" && clientA.totalContributions === 7, "failure cannot refresh query");
      check(!popup.requestClose() && popup.settingsPage !== null, "failure retains page");
      popup.keepEditing();
      actor.command = ["chmod", "700", Settings.configDir + "settings"];
      actor.running = true;
      phase = "retry";
    } else if (phase === "retry" && !actor.running) {
      receipt = null;
      check(popup.applySettings(), "same editor Retry");
      phase = "applied";
    } else if (phase === "applied" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted current receipt");
      siblings();
      if (stage === 4) {
        if (clientA.hasData || !clientA.errorMessage.length)
          return;
        check(!desktopA.hasData && desktopA.slicedDays.length === 0, "cleared account removes old graph");
        actor.command = ["touch", Quickshell.env("PHA_HOLD_ROOT") + "/release"];
        actor.running = true;
        phase = "stable";
        return;
      }
      if (clientA.username !== "synthetic-beta" || !clientA.hasData || clientA.totalContributions !== (stage === 3 ? 31 : 29))
        return;
      check(text(desktopA, "@synthetic-beta"), "actual displayed selected account");
      if (stage >= 2) {
        // Native runtime overlays subscribe separately from the editor receipt.
        // Wait for that actual view, then assert the final graph geometry.
        if (desktopA.weeksShown !== 4)
          return;
        check(desktopA.columns === 4, "actual selected graph extent: " + desktopA.columns);
      }
      if (stage < 3) {
        stage++;
        phase = "focus";
      } else {
        actor.command = ["touch", Quickshell.env("PHA_HOLD_ROOT") + "/hold"];
        actor.running = true;
        phase = "hold-start";
      }
    } else if (phase === "hold-start" && !actor.running) {
      clientA.refresh();
      phase = "held";
    } else if (phase === "held") {
      barrier.reload();
      barrier.waitForJob();
      if (barrier.text().trim() !== "entered")
        return;
      check(clientA.loading, "old account request held");
      stage = 4;
      phase = "focus";
    } else if (phase === "stable" && !actor.running) {
      check(!clientA.hasData && !desktopA.hasData && desktopA.slicedDays.length === 0, "old held response cannot repopulate new account");
      siblings();
      if (++stableTicks < 12)
        return;
      check(popup.requestClose(), "clean Close");
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      check(!desktopA.hasData && !desktopB.hasData && desktopB.slicedDays.length === 0, "retired account clients no longer drive graphs");
      console.log("CONTRIBUTIONS_SELECTED: PASS");
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
    onTriggered: root.fail("Contributions watchdog " + phase + "/" + stage)
  }
  Component.onCompleted: begin()
}
