// P048 selected query owner, actual Settings input and Panel result text.
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
  property int stage: 0
  property var api: null
  property var a: null
  property var b: null
  property var main: null
  property var clientA: null
  property var clientB: null
  property var panelA: null
  property var panelB: null
  property var input: null
  property var receipt: null
  readonly property bool cold: Quickshell.env("PHA_GIT_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/git-companion/manifest.json"
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
      throw new Error("GIT_SELECTED_ASSERT: " + message);
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
    var item = PluginLoader.createObject("git-companion", entry, component, parent, selected, {});
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
      "git-companion": manifest
    };
    Service._openSettingsOwner("git-companion", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI("git-companion", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "git-companion": {
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
                id: "plugin:git-companion"
              },
              {
                id: "plugin:git-companion",
                instanceSettings: {
                  repo: "synthetic/other"
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
    a = PluginInstances.apiFor("git-companion", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 0
                               });
    b = PluginInstances.apiFor("git-companion", {
                                 kind: "bar",
                                 list: "global",
                                 section: "left",
                                 index: 1
                               });
    phase = "ready";
  }
  function row(panel, repo) {
    return find(panel, function (item) {
      return item.text === "result for " + repo;
    }) !== null;
  }
  function siblings() {
    check(main.repo === "synthetic/alpha" && main.issuesList[0].title === "result for synthetic/alpha", "shared query remains alpha");
    check(clientB.repo === "synthetic/other" && row(panelB, "synthetic/other"), "sibling query/result remains other");
    check(clientA === main.settingsConsumerFor(a.settingsContext) && clientA !== clientB, "stable client per context, not per view/config value");
  }
  function drive() {
    if (phase === "ready" && a.settingsReady && b.settingsReady) {
      clientA = main.settingsConsumerFor(a.settingsContext);
      clientB = main.settingsConsumerFor(b.settingsContext);
      check(clientB.repo === "synthetic/other", "selected query context cannot become shared Main configuration");
      panelA = create("panel", left, a);
      panelB = create("panel", right, b);
      phase = "initial";
    } else if (phase === "initial" && row(panelA, cold ? "synthetic/beta" : "synthetic/alpha") && row(panelB, "synthetic/other") && main.issuesCount === 1) {
      siblings();
      if (cold) {
        console.log("GIT_SELECTED: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "selected Settings opens");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty && !popup.dirty, "opening submits no intent");
      var control = find(popup.settingsPage, function (item) {
        return item.label === api.tr("settings.repo.label") && item.inputItem !== undefined;
      });
      check(control !== null, "actual repository TextInput");
      input = control.inputItem;
      phase = "focus";
    } else if (phase === "focus") {
      input.forceActiveFocus();
      input.selectAll();
      check(input.activeFocus && input.selectionEnd === input.text.length, "actual repository focus/selection");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "--", "synthetic/beta"];
      typing.running = true;
      phase = "typing";
    } else if (phase === "typing" && !typing.running && input.text === "synthetic/beta") {
      check(clientA.repo === "synthetic/alpha" && row(panelA, "synthetic/alpha"), "typing cannot publish or change query");
      siblings();
      if (stage === 0) {
        check(!popup.requestClose() && popup.discardPending, "dirty Close refuses");
        popup.keepEditing();
        check(popup.confirmDiscard(), "explicit discard");
        phase = "discarded";
      } else {
        check(popup.applySettings(), "native selected Apply");
        phase = "applied";
      }
    } else if (phase === "discarded" && !popup.visible) {
      check(clientA.repo === "synthetic/alpha" && row(panelA, "synthetic/alpha"), "discard retains old query/results");
      siblings();
      stage = 1;
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "reopen after discard");
      phase = "page";
    } else if (phase === "applied" && receipt && !popup.busy && row(panelA, "synthetic/beta")) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "accepted current Apply");
      siblings();
      check(popup.requestClose(), "Close after save");
      console.log("GIT_SELECTED: PASS");
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
    onTriggered: root.fail("selected Git watchdog " + phase)
  }
  Component.onCompleted: begin()
}
