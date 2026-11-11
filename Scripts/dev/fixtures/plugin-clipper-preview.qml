import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var screen: Quickshell.screens[0]
  property var api: null
  property var instance: null
  property var sibling: null
  property var main: null
  property var panel: null
  property var siblingPanel: null
  property var sharedPanel: null
  property var manifest: null
  property var controls: []
  property bool started: false
  property string phase: "start"
  property double pasteStarted: 0
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var placement: ({
                                      kind: "bar",
                                      list: "global",
                                      section: "left",
                                      index: 0
                                    })
  readonly property var edits: [["valueTodoIntegration", "enableTodoIntegration", "settings.todo-integration", true], ["valuePincardsEnabled", "pincardsEnabled", "settings.pincards-enabled", false], ["valueNotecardsEnabled", "notecardsEnabled", "settings.notecards-enabled", false], ["valueShowCloseButton", "showCloseButton", "settings.show-close-button",
                                                                                                                                                                                                                                                                                            true], ["valueFullscreenMode", "fullscreenMode", "settings.fullscreen-mode",
                                                                                                                                                                                                                                                                                                    false], ["valueHidePanelBackground", "hidePanelBackground",
                                                                                                                                                                                                                                                                                                             "settings.hide-panel-background", true], ["valueAutoPaste",
                                                                                                                                                                                                                                                                                                                                                       "autoPaste", "settings.auto-paste",
                                                                                                                                                                                                                                                                                                                                                       true], ["valueAutoPasteOnRightClick",
                                                                                                                                                                                                                                                                                                                                                               "autoPasteOnRightClick", "settings.auto-paste-rmb",
                                                                                                                                                                                                                                                                                                                                                               true], ["valueAutoPasteDelay",
                                                                                                                                                                                                                                                                                                                                                                       "autoPasteDelay", "settings.auto-paste-delay",
                                                                                                                                                                                                                                                                                                                                                                       700], ["valuePanelWidth",
                                                                                                                                                                                                                                                                                                                                                                              "panelWidth", "settings.panel-width",
                                                                                                                                                                                                                                                                                                                                                                              1000], ["valuePanelHeight",
                                                                                                                                                                                                                                                                                                                                                                                      "panelHeight", "settings.panel-height",
                                                                                                                                                                                                                                                                                                                                                                                      600]]
  FileView {
    id: input
    path: Quickshell.env("I4_CLIPPER_MANIFEST")
    blockLoading: true
    printErrors: false
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("I4_CLIPPER_PREVIEW_ASSERT: " + phase + " " + label);
  }
  function create(filename, parent, properties) {
    var component = Qt.createComponent("file://" + Registry.getPluginDir("clipper") + "/" + filename);
    check(component.status === Component.Ready, component.errorString());
    var item = component.createObject(parent, properties);
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
    page.todoPluginAvailable = true;
    for (var row of edits) {
      var control = find(page, function (item) {
        return item.label === api.tr(row[2]);
      });
      check(control !== null, "actual control: " + row[1]);
      if (typeof control.toggled === "function")
        control.toggled(row[3]);
      else {
        control.value = row[3];
        if (typeof control.valueModified === "function")
          control.valueModified(row[3]);
        else
          control.moved(row[3]);
      }
      check(page[row[0]] === row[3], "control updates buffer: " + row[1]);
    }
    page.setCardColor("Text", "bg", "custom", false);
    page.setCardColor("Text", "bg", "#123456", true);
    check(page.settingsDirty && popup.dirty, "complete local input tracked");
  }
  function consumers() {
    check(panel.contentPreferredWidth === 1000 * Style.uiScaleRatio && panel.contentPreferredHeight === 600 * Style.uiScaleRatio, "actual selected panel geometry consumes preview");
    check(String(panel.panelBackgroundColor) === "#00000000", "actual selected background consumes preview");
    var close = find(panel, function (item) {
      return item.icon === "x" && typeof item.clicked === "function";
    });
    check(close !== null && close.visible, "selected close button consumes preview instead of shared Main");
    var card = find(panel, function (item) {
      return typeof item.enableTodoIntegration === "boolean" && typeof item.clicked === "function" && item.clipboardId === "1";
    });
    check(card !== null && card.enableTodoIntegration, "functional Todo flag reaches actual card");
    check(siblingPanel.contentPreferredWidth === 900 * Style.uiScaleRatio && sharedPanel.contentPreferredWidth === 1200 * Style.uiScaleRatio, "sibling/shared consumers unchanged");
    return card;
  }
  function register(value) {
    api = Service.createPluginAPI("clipper", manifest, value, {}, {}, {});
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded.clipper = {
      api: api
    };
    Service.loadedPlugins = loaded;
    main = create("Main.qml", scene, {
                    pluginApi: api
                  });
    api.mainInstance = main;
    main.items = [
          {
            id: "1",
            preview: "Fixture clipboard text",
            mime: "text/plain",
            isImage: false
          }
        ];
    main.wtypeAvailable = true;
    api.closePanel = function () {};
    instance = PluginInstances.apiFor("clipper", placement);
    sibling = PluginInstances.apiFor("clipper", {
                                       kind: "bar",
                                       list: "global",
                                       section: "left",
                                       index: 1
                                     });
    sharedPanel = create("Panel.qml", scene, {
                           pluginApi: api,
                           width: 500,
                           height: 500
                         });
    panel = create("Panel.qml", scene, {
                     pluginApi: instance,
                     width: 500,
                     height: 500
                   });
    siblingPanel = create("Panel.qml", scene, {
                            pluginApi: sibling,
                            width: 500,
                            height: 500
                          });
  }
  function start() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    input.waitForJob();
    manifest = JSON.parse(input.text());
    if (verifyOnly) {
      Service._openSettingsOwner("clipper", function (value) {
        try {
          check(value!==null,"cold native owner opens");
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
            id: "plugin:clipper",
            opaque: {
              keep: true
            },
            instanceSettings: {
              panelWidth: 1100
            }
          },
          {
            id: "plugin:clipper",
            instanceSettings: {
              panelWidth: 900
            }
          }
        ];
    Service._openSettingsOwner("clipper",function(owner){try{check(owner!==null,"native owner opens");register(owner);
    Settings.saveResult(function(result){try{check(result.status==="saved","placement seed saved");
        popup.openInstanceSettings(root.manifest, root.instance, "settings");
        root.phase = "preview";
    }catch(error){console.error(String(error));Qt.exit(2);}});
    }catch(error){console.error(String(error));Qt.exit(2);}});
  }
  function drive() {
    if (phase === "preview" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "no constructor preview or preference input");
      edit();
      phase = "observe";
    } else if (phase === "observe") {
      consumers();
      for (var row of edits)
        check(instance.settingsView[row[1]] === row[3], "every existing preview flag retained: " + row[1]);
      check(api.pluginSettings.panelWidth === 1200 && api.pluginSettings.autoPasteDelay === 300 && instance.pluginSettings.panelWidth === 1100 && !api.pluginSettings.autoPaste && !main.showCloseButton, "preview does not mutate live preferences or shared Main");
      var rows = JSON.parse(JSON.stringify(Settings.data.bar.widgets.left));
      rows[0].instanceSettings.panelWidth = 1250;
      Settings.data.bar.widgets.left = rows;
      popup.requestClose();
      check(popup.discardPending, "explicit discard required");
      popup.keepEditing();
      check(popup.visible, "keep preview");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "cancel";
    } else if (phase === "cancel" && !popup.visible && !popup.currentPlugin) {
      if(instance.pluginSettings.panelWidth!==1250)return;
      check(panel.contentPreferredWidth === 1250 * Style.uiScaleRatio && api.pluginSettings.panelWidth === 1200, "cancel reveals current foreign value, no opening snapshot restore");
      popup.openInstanceSettings(manifest, instance, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && popup.settingsPage) {
      edit();
      popup.applySettings();
      phase = "wait";
    } else if (phase === "wait" && !popup.busy) {
      check(!popup.saveFailed && !popup.dirty, "current receipt clears accepted local work");
      if(instance.pluginSettings.panelWidth!==1000)return;
      consumers();
      check(String(consumers().accentColor) === "#123456", "saved color reaches the actual card");
      check(instance.pluginSettings.panelWidth === 1000 && instance.pluginSettings.autoPasteDelay === 700 && api.pluginSettings.panelWidth === 1200, "only selected placement persisted");
      check(instance.pluginSettings.cardColors.Text.opaque === "keep" && instance.pluginSettings.customColors.Text.opaque === "keep" && PluginInstances.entryFor(placement).opaque.keep, "unknown nested and placement fields survive");
      popup.requestClose();
      phase = "settled";
    } else if (phase === "settled" && !popup.visible && !popup.currentPlugin) {
      var card = consumers();
      pasteStarted = Date.now();
      card.rightClicked();
      phase = "paste";
    } else if (phase === "paste") {
      // The driver supplies inert cliphist/wl-copy/wtype commands. Observe the
      // actual Main timer/process endpoint, without typing into another window.
      pasteResult.reload();
      pasteResult.waitForJob();
      if (!pasteResult.text().trim())
        return;
      check(pasteResult.text().trim() === "ctrl-shift-v", "selected auto-paste reaches actual Main process");
      check(Date.now() - pasteStarted >= 600, "selected delay, not shared 300 ms delay");
      console.log("I4_CLIPPER_PREVIEW: SAVED_PASS");
      Qt.exit(0);
    } else if (phase === "restart") {
      if(!instance.settingsReady||!sibling.settingsReady)return;
      consumers();
      rawPreference.reload();rawPreference.waitForJob();
      check(instance.pluginSettings.autoPasteDelay === 700 && JSON.parse(rawPreference.text()).opaque.keep, "saved selected consumer and raw unknown after cold restart");
      check(String(consumers().accentColor) === "#123456", "saved card color after cold restart");
      console.log("I4_CLIPPER_PREVIEW: RESTART_PASS");
      Qt.exit(0);
    }
  }
  FileView {
    id:rawPreference
    path:Settings.configDir+"settings/plugins/clipper.json"
    printErrors:false
  }
  FileView {
    id: pasteResult
    path: Quickshell.env("I4_CLIPPER_PASTE_RESULT")
    printErrors: false
  }
  FloatingWindow {
    visible: true
    implicitWidth: 800
    implicitHeight: 700
    Item {
      id: scene
      anchors.fill: parent
    }
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.start();
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
      console.error("I4_CLIPPER_PREVIEW_ASSERT: watchdog", root.phase);
      Qt.exit(2);
    }
  }
}
