import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property var api: null
  property var instance: null
  property var sibling: null
  property var main: null
  property var panel: null
  property var siblingPanel: null
  property var sharedPanel: null
  property var manifest: null
  property bool started: false
  property string phase: "start"
  property int parserVersion: 0
  property var lastResult: null
  property int savedNotices: 0
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var placement: ({
                                      kind: "bar",
                                      list: "global",
                                      section: "left",
                                      index: 0
                                    })
  readonly property var colors: [["super", "Super"], ["ctrl", "Ctrl"], ["shift", "Shift"], ["alt", "Alt"], ["xf86", "XF86"], ["print", "Print"], ["numeric", "Numeric"], ["mouse", "Mouse"], ["default", "Default"], ["mod2", "Mod2"], ["mod3", "Mod3"], ["mod5", "Mod5"]]
  FileView {
    id: input
    path: Quickshell.env("I4_KEYBIND_MANIFEST")
    blockLoading: true
    printErrors: false
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("I4_KEYBIND_PREVIEW_ASSERT: " + phase + " " + label);
  }
  function create(filename, properties) {
    var component = Qt.createComponent("file://" + Registry.getPluginDir("keybind-cheatsheet") + "/" + filename);
    check(component.status === Component.Ready, component.errorString());
    var item = component.createObject(scene, properties);
    check(item !== null, filename + " created");
    return item;
  }
  function find(item, predicate) {
    if (predicate(item))
      return item;
    for (var child of item.children || []) {
      var found = find(child, predicate);
      if (found)
        return found;
    }
    return null;
  }
  function edit() {
    var page = popup.settingsPage;
    for (var pair of colors) {
      var row = find(page, function (item) {
        return item.labelText === api.tr("settings.color-" + pair[0]) && typeof item.bgPasted === "function";
      });
      check(row !== null, "actual color row " + pair[0]);
      row.bgPasted("#123456");
      row.textPasted("#abcdef");
      if (row.showLabel)
        row.labelEdited("Custom-" + pair[1]);
    }
    var description = find(page, function (item) {
      return item.labelText === api.tr("settings.color-description") && typeof item.textPasted === "function";
    });
    description.textPasted("#112233");
    page.restoreHidden();
    check(page.editBindOverrides.fixture.desc === "Keep description" && page.editBindOverrides.fixture.opaque.keep && page.editBindOverrides.fixture.hidden === false, "restore hidden masks the inherited flag and preserves other known and unknown members");
    check(page.settingsDirty && popup.dirty, "local records/colors dirty");
  }
  function dirtyFields(page) {
    var result = [];
    for (var child of page.data || []) {
      if (typeof child.project !== "function" || typeof child.differs !== "function")
        continue;
      for (var name of Object.keys(child)) {
        if (!name.startsWith("edit") && !name.startsWith("value"))
          continue;
        if (JSON.stringify(child.project(name)) !== JSON.stringify(page[name]))
          result.push({
                        field: name,
                        initial: child.project(name),
                        local: page[name]
                      });
      }
    }
    return result;
  }
  function consumers() {
    for (var pair of colors) {
      check(instance.settingsView["keyColor" + pair[1]] === "#123456", "all preview backgrounds " + pair[1]);
      check(instance.settingsView["keyText" + pair[1]] === "#abcdef", "all preview text " + pair[1]);
    }
    check(String(panel.keyColorAlt) === "#123456" && panel.keyColorSuperOverride === "#123456", "actual selected panel color consumers");
    check(panel.getKeyLabel("Mod3") === "Custom-Mod3" && panel.descriptionColorOverride === "#112233", "actual selected label/description consumers");
    check(String(sharedPanel.keyColorAlt) === "#ff6b6b" && String(siblingPanel.keyColorAlt) === "#654321", "shared/sibling consumers isolated");
  }
  function register(value) {
    api = Service.createPluginAPI("keybind-cheatsheet", manifest, value, {}, {}, {});
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded["keybind-cheatsheet"] = {
      api: api
    };
    Service.loadedPlugins = loaded;
    main = create("Main.qml", {
                    parserStarted: true,
                    pluginApi: api
                  });
    api.mainInstance = main;
    instance = PluginInstances.apiFor("keybind-cheatsheet", placement);
    sibling = PluginInstances.apiFor("keybind-cheatsheet", {
                                       kind: "bar",
                                       list: "global",
                                       section: "left",
                                       index: 1
                                     });
    panel = create("Panel.qml", {
                     pluginApi: instance
                   });
    siblingPanel = create("Panel.qml", {
                            pluginApi: sibling
                          });
    sharedPanel = create("Panel.qml", {
                           pluginApi: api
                         });
  }
  function start() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    input.waitForJob();
    manifest = JSON.parse(input.text());
    if (verifyOnly) {
      Service.loadPluginSettings("keybind-cheatsheet", function (value) {
        try {
          root.register(value);
          root.phase = "restart";
        } catch (error) {
          console.error(String(error));
          Qt.exit(2);
        }
      });
      return;
    }
    Settings.data.bar.widgets.left = [
          {
            id: "plugin:keybind-cheatsheet",
            opaque: {
              keep: true
            },
            instanceSettings: {
              keyColorAlt: "#334455"
            }
          },
          {
            id: "plugin:keybind-cheatsheet",
            instanceSettings: {
              keyColorAlt: "#654321"
            }
          }
        ];
    register({
               niriConfigPath: Quickshell.env("I4_KEYBIND_CONFIG"),
               bindOverrides: {
                 fixture: {
                   desc: "Keep description",
                   hidden: true,
                   opaque: {
                     keep: true
                   }
                 }
               }
             });
    api.saveSettings(function (result) {
      if (result.status !== "saved")
        Qt.exit(2);
      else {
        popup.openInstanceSettings(root.manifest, root.instance, "settings");
        root.phase = "preview";
      }
    });
  }
  function drive() {
    if (phase === "preview" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "constructor is clean, no label preview input");
      parserVersion = main.cheatsheetDataVersion;
      edit();
      phase = "observe";
    } else if (phase === "observe") {
      consumers();
      check(instance.pluginSettings.keyColorAlt === "#334455" && api.pluginSettings.keyColorAlt === "#FF6B6B", "preview never writes preferences");
      check(main.cheatsheetDataVersion === parserVersion && savedNotices === 0, "staging does not run parser or claim saved");
      var rows = JSON.parse(JSON.stringify(Settings.data.bar.widgets.left));
      rows[0].instanceSettings.keyColorAlt = "#456789";
      Settings.data.bar.widgets.left = rows;
      popup.requestClose();
      check(popup.discardPending, "discard confirmation");
      popup.keepEditing();
      check(popup.visible, "keep editing");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "cancel";
    } else if (phase === "cancel" && !popup.visible && !popup.currentPlugin) {
      check(String(panel.keyColorAlt) === "#456789" && main.cheatsheetDataVersion === parserVersion, "cancel reveals foreign edit without rollback or refresh");
      popup.openInstanceSettings(manifest, instance, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && popup.settingsPage) {
      edit();
      popup.settingsPage.pluginApi.settingsCompleted({
                                                       status: "failed",
                                                       refreshState: "not_refreshed"
                                                     });
      popup.settingsPage.pluginApi.settingsCompleted({
                                                       status: "saved",
                                                       refreshState: "stale"
                                                     });
      check(main.cheatsheetDataVersion === parserVersion && savedNotices === 0, "failure/stale receipts do not refresh or claim saved");
      popup.applySettings();
      phase = "wait";
    } else if (phase === "wait" && !popup.busy) {
      check(!popup.saveFailed && !popup.dirty, "current receipt clears accepted work: " + JSON.stringify(lastResult) + " dirty=" + popup.dirty + " fields=" + JSON.stringify(dirtyFields(popup.settingsPage)));
      check(savedNotices === 1, "one actual saved toast after current receipt");
      consumers();
      check(instance.pluginSettings.bindOverrides.fixture.opaque.keep && !instance.pluginSettings.bindOverrides.fixture.hidden, "selected override edit persisted");
      popup.requestClose();
      phase = "parser";
    } else if (phase === "parser" && !popup.visible && !popup.currentPlugin && main.cheatsheetDataVersion > parserVersion) {
      check(JSON.stringify(sharedPanel.rawCategories).includes("Run: fixture-command"), "acknowledged refresh reaches actual parser and its path-specific output reaches the shared panel");
      api.saveSettings(function (result) {
        check(result.status === "saved" || result.status === "nothing_to_save", "parser cache persisted");
        console.log("I4_KEYBIND_PREVIEW: SAVED_PASS");
        Qt.exit(0);
      });
      phase = "saving-cache";
    } else if (phase === "restart") {
      consumers();
      check(api.pluginSettings.bindOverrides.fixture.hidden && api.pluginSettings.bindOverrides.fixture.opaque.keep, "shared overrides unaffected after restart");
      check(instance.pluginSettings.bindOverrides.fixture.opaque.keep && !instance.pluginSettings.bindOverrides.fixture.hidden, "selected map after restart");
      check(JSON.stringify(sharedPanel.rawCategories).includes("Run: fixture-command"), "actual restarted parser cache consumer");
      console.log("I4_KEYBIND_PREVIEW: RESTART_PASS");
      Qt.exit(0);
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 700
    Item {
      id: scene
      anchors.fill: parent
    }
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
      onSettingsCompleted: result => root.lastResult = result
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.start();
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      if (root.api && title === root.api.tr("settings.saved"))
        root.savedNotices++;
    }
  }
  Component.onCompleted: start()
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Timer {
    interval: 40000
    running: true
    onTriggered: {
      console.error("I4_KEYBIND_PREVIEW_ASSERT: watchdog", root.phase);
      Qt.exit(2);
    }
  }
}
