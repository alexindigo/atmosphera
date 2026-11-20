// P055 selected check client: actual Settings typing, real IO failure/Retry,
// inert check commands and the actual Desktop update list.
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
  property var failedPage: null
  property var failedEditor: null
  readonly property bool cold: Quickshell.env("PHA_ARCH_COLD") === "1"
  readonly property string checkCommand: Quickshell.env("PHA_ARCH_CHECK")
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/arch-updater/manifest.json"
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
      throw new Error("ARCH_SELECTED_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children, object?.resources, object?.contentItem ? [object.contentItem] : null]) {
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
    // Known inherited desktop inputs at construction, as in the Todo witness.
    var context = entry === "desktopWidget" ? {
                                                screen: Quickshell.screens[0],
                                                widgetData: {
                                                  id: "plugin:arch-updater"
                                                },
                                                widgetIndex: 0
                                              } : {};
    var item = entry === "desktopWidget" ? component.createObject(parent, Object.assign({
                                                                                          pluginApi: selected
                                                                                        }, context)) : PluginLoader.createObject("arch-updater", entry, component, parent, selected, context);
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
      "arch-updater": manifest
    };
    Service._openSettingsOwner("arch-updater", function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI("arch-updater", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "arch-updater": {
            api: api
          }
        };
        main = create("main", root, api);
        api.mainInstance = main;
        if (cold) {
          openConsumers();
          return;
        }
        Settings.data.desktopWidgets.monitorWidgets = [
              {
                name: Quickshell.screens[0].name,
                widgets: [
                  {
                    id: "plugin:arch-updater"
                  },
                  {
                    id: "plugin:arch-updater",
                    instanceSettings: {
                      systemCmd: root.checkCommand + " other"
                    }
                  }
                ]
              }
            ];
        Settings.saveSelected([["desktopWidgets", "monitorWidgets"]], function (result) {
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
    var screen = Quickshell.screens[0].name;
    a = PluginInstances.apiFor("arch-updater", {
                                 kind: "desktop",
                                 screenName: screen,
                                 index: 0
                               });
    b = PluginInstances.apiFor("arch-updater", {
                                 kind: "desktop",
                                 screenName: screen,
                                 index: 1
                               });
    phase = "ready";
  }
  function shows(view, name) {
    return find(view, function (item) {
      return item.text === name && item.visible;
    }) !== null;
  }
  function names(client) {
    return client.updates.map(function (row) {
      return row.name;
    }).join(",");
  }
  function siblings() {
    check(names(main) === "alpha-pkg" && !main.refreshing, "shared Main client remains alpha");
    check(names(clientB) === "other-pkg" && shows(desktopB, "other-pkg"), "sibling client/result remains other");
    check(clientA === main.settingsConsumerFor(a.settingsContext) && clientA !== clientB && clientA !== main.settingsConsumer, "stable client per context");
  }
  function drive() {
    if (phase === "ready" && a.settingsReady && b.settingsReady) {
      clientA = main.settingsConsumerFor(a.settingsContext);
      clientB = main.settingsConsumerFor(b.settingsContext);
      desktopA = create("desktopWidget", left, a);
      desktopB = create("desktopWidget", right, b);
      check(desktopA.updater === clientA && desktopB.updater === clientB, "Desktop binds selected client");
      phase = "initial";
    } else if (phase === "initial" && !clientA.refreshing && !clientB.refreshing && names(clientB) === "other-pkg" && names(clientA) === (cold ? "beta-pkg" : "alpha-pkg") && shows(desktopA, cold ? "beta-pkg" : "alpha-pkg")) {
      siblings();
      if (cold) {
        console.log("ARCH_SELECTED: COLD_PASS");
        Qt.exit(0);
        return;
      }
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "selected Settings opens");
      phase = "page";
    } else if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup._editor.dirty && !popup.dirty, "opening submits no intent");
      var field = popup._pageApi.field("systemCmd");
      check(!field.overridden && field.value === root.checkCommand + " alpha", "inherited command presented");
      var control = find(popup.settingsPage, function (item) {
        return item.label === api.tr("settings.general.systemCmd.text") && item.inputItem !== undefined;
      });
      check(control !== null, "actual system command TextInput");
      input = control.inputItem;
      phase = "focus";
    } else if (phase === "focus") {
      input.forceActiveFocus();
      input.selectAll();
      check(input.activeFocus && input.selectionEnd === input.text.length, "actual command focus/selection");
      typing.command = [Quickshell.env("PHA_INPUT_INJECTOR"), "--", root.checkCommand + " beta"];
      typing.running = true;
      phase = "typing";
    } else if (phase === "typing" && !typing.running && input.text === root.checkCommand + " beta") {
      check(names(clientA) === "alpha-pkg" && shows(desktopA, "alpha-pkg"), "typing cannot publish or rerun the check");
      siblings();
      if (stage === 0) {
        check(!popup.requestClose() && popup.discardPending, "dirty Close refuses");
        popup.keepEditing();
        check(popup.confirmDiscard(), "explicit discard");
        phase = "discarded";
      } else {
        failedPage = popup.settingsPage;
        failedEditor = popup._editor;
        permissions.command = ["chmod", "500", Settings.configDir + "settings"];
        phase = "make-unwritable";
        permissions.running = true;
      }
    } else if (phase === "discarded" && !popup.visible) {
      check(names(clientA) === "alpha-pkg", "discard retains old check/results");
      siblings();
      stage = 1;
      check(popup.openInstanceSettings(api.manifest, a, "settings"), "reopen after discard");
      phase = "page";
    } else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && popup.saveFailed, "IO failure not acknowledged");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "failure retains selected page/editor");
      check(names(clientA) === "alpha-pkg" && clientA.systemCmd === root.checkCommand + " alpha", "failed persistence cannot refresh the selected client");
      siblings();
      check(!popup.requestClose() && popup.discardPending, "failed Close refuses");
      popup.keepEditing();
      permissions.command = ["chmod", "700", Settings.configDir + "settings"];
      phase = "make-writable";
      permissions.running = true;
    } else if (phase === "retry" && receipt && !popup.busy) {
      check(receipt.status === "saved" && receipt.refreshState === "current", "same-editor Retry current");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "Retry preserves capture");
      phase = "refreshed";
    } else if (phase === "refreshed" && !clientA.refreshing && names(clientA) === "beta-pkg" && shows(desktopA, "beta-pkg")) {
      check(clientA.systemCmd === root.checkCommand + " beta", "selected client consumes the accepted command");
      siblings();
      check(popup.requestClose(), "Close after save");
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      console.log("ARCH_SELECTED: PASS");
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
    interval: 50000
    running: true
    onTriggered: root.fail("selected Arch watchdog " + phase)
  }
  Component.onCompleted: begin()
}
