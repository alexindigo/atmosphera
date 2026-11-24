// Real popup/field layout with native selected owners; no publication.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property var manifest: null
  property var api: null
  property var selected: null
  property bool started: false
  property int step: 0
  property string phase: "startup"
  property string label: ""
  readonly property string output: Quickshell.env("PHA_CHROME_OUTPUT")
  FileView {
    id: mf
    path: Settings.configDir + "plugins/review-fixture/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
    }
  }
  Process {
    id: capture
    onExited: code => {
      if (code !== 0)
        root.fail("capture exit " + code);
      else {
        root.step++;
        root.phase = "advance";
      }
    }
  }
  function fail(message) {
    console.error("CHROME_ASSERT: " + message);
    Qt.exit(2);
  }
  function begin() {
    if (started || !Settings.isLoaded || !I18n.isLoaded)
      return;
    started = true;
    mf.waitForJob();
    manifest = JSON.parse(mf.text());
    Registry.installedPlugins = {
      "review-fixture": manifest
    };
    Service._openSettingsOwner("review-fixture", function (owner) {
      if (!owner) {
        root.fail("native owner");
        return;
      }
      root.api = Service.createPluginAPI("review-fixture", root.manifest, owner, {}, {}, {});
      Service.loadedPlugins = {
        "review-fixture": {
          api: root.api
        }
      };
      root.selected = PluginInstances.apiFor("review-fixture", {
                                               kind: "bar",
                                               list: "global",
                                               section: "left",
                                               index: 0
                                             });
      root.phase = "advance";
    });
  }
  function find(item, predicate) {
    if (item && predicate(item))
      return item;
    for (var list of [item?.children, item?.contentChildren])
      if (list)
        for (var i = 0; i < list.length; i++) {
          var result = find(list[i], predicate);
          if (result)
            return result;
        }
    return null;
  }
  function texts(item, found, seen) {
    if (!item || seen.indexOf(item) !== -1)
      return;
    seen.push(item);
    if (item.text !== undefined && item.visible && item.width > 0 && item.height > 0) {
      var p = item.mapToItem(host.contentItem, 0, 0);
      found.push({
                   text: String(item.text),
                   x: p.x,
                   y: p.y,
                   width: item.width,
                   height: item.height,
                   enabled: item.enabled,
                   clipped: item.truncated === true
                 });
    }
    for (var list of [item.children, item.contentChildren])
      if (list)
        for (var i = 0; i < list.length; i++)
          texts(list[i], found, seen);
  }
  function shot(name) {
    label = name;
    phase = "paint";
    paint.restart();
  }
  function advance() {
    if (step === 0) {
      popup.openPluginSettings(manifest);
      phase = "shared";
    } else if (step === 1) {
      popup.confirmDiscard();
      phase = "open-instance";
    } else if (step === 2) {
      popup.settingsPage.edit();
      shot("en-pending");
    } else if (step === 3) {
      popup.settingsPage.resetField();
      shot("en-reset-pending");
    } else if (step === 4) {
      popup.resetButton.clicked();
      shot("en-reset-confirmation");
    } else if (step === 5) {
      popup.resetConfirmation.close();
      popup.settingsPage.rejectInput();
      popup.applySettings();
      if (!popup.saveFailed) {
        fail("rejected field input retains the page and shows failed completion");
        return;
      }
      shot("en-failed");
    } else if (step === 6) {
      popup.confirmDiscard();
      I18n.setLanguage("fr");
      phase = "french-open";
    } else if (step === 7) {
      popup.confirmDiscard();
      phase = "inherited-open";
    } else if (step === 8) {
      popup.confirmDiscard();
      phase = "many-open";
    } else if (step === 9) {
      var scroll = find(popup.contentItem, item => typeof item.applyWheelScroll === "function");
      if (!scroll || !scroll.verticalScrollable) {
        fail("override summary belongs to bounded scroll region");
        return;
      }
      scroll.applyWheelScroll(-100000);
      shot("fr-many-bottom");
    } else if (step === 10) {
      var key = find(popup.contentItem, item => item.text === "hidden23");
      var button = key ? find(key.parent, item => typeof item.clicked === "function") : null;
      if (!button) {
        fail("last hidden field Reset reachable after scroll");
        return;
      }
      button.clicked();
      if (button.enabled) {
        fail("hidden field Reset stages once through real field capability");
        return;
      }
      shot("fr-hidden-reset");
    } else if (step === 11) {
      popup.confirmDiscard();
      console.log("PLUGIN_SETTINGS_CHROME: CAPTURED");
      Qt.exit(0);
    }
  }
  Timer {
    id: paint
    interval: 400
    onTriggered: {
      var rows = [];
      root.texts(popup.contentItem, rows, []);
      if (popup.resetConfirmation.visible)
        root.texts(popup.resetConfirmation.contentItem, rows, []);
      var p = popup.contentItem.mapToItem(host.contentItem, -popup.padding, -popup.padding);
      console.log("CHROME_GEOMETRY " + JSON.stringify({
                                                        label: root.label,
                                                        popup: {
                                                          x: p.x,
                                                          y: p.y,
                                                          width: popup.width,
                                                          height: popup.height,
                                                          maxHeight: popup.maxHeight
                                                        },
                                                        host: {
                                                          width: host.width,
                                                          height: host.height
                                                        },
                                                        texts: rows,
                                                        undisplayed: popup.undisplayedOverrideFields.length
                                                      }));
      capture.command = ["grim", "-o", Quickshell.screens[0].name, root.output + "/" + root.label + ".png"];
      capture.running = true;
    }
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        if (!root.started)
          root.begin();
        else if (root.phase === "advance")
          root.advance();
        else if (root.phase === "shared" && popup.opened && popup.settingsPage)
          root.shot("en-shared");
        else if (root.phase === "open-instance" && !popup.currentPlugin) {
          popup.openInstanceSettings(root.manifest, root.selected);
          root.phase = "instance";
        } else if (root.phase === "instance" && popup.opened && popup.settingsPage)
          root.shot("en-instance");
        else if (root.phase === "french-open" && !popup.currentPlugin && I18n.isLoaded && I18n.langCode === "fr" && Object.keys(I18n.fallbackTranslations).length) {
          popup.openInstanceSettings(root.manifest, root.selected);
          root.phase = "french";
        } else if (root.phase === "french" && popup.opened && popup.settingsPage)
          root.shot("fr-instance");
        else if (root.phase === "inherited-open" && !popup.currentPlugin) {
          root.selected = PluginInstances.apiFor("review-fixture", {
                                                   kind: "bar",
                                                   list: "global",
                                                   section: "left",
                                                   index: 2
                                                 });
          popup.openInstanceSettings(root.manifest, root.selected);
          root.phase = "inherited";
        } else if (root.phase === "inherited" && popup.opened && popup.settingsPage)
          root.shot("fr-inherited");
        else if (root.phase === "many-open" && !popup.currentPlugin) {
          root.selected = PluginInstances.apiFor("review-fixture", {
                                                   kind: "bar",
                                                   list: "global",
                                                   section: "left",
                                                   index: 1
                                                 });
          popup.openInstanceSettings(root.manifest, root.selected);
          root.phase = "many";
        } else if (root.phase === "many" && popup.opened && popup.settingsPage)
          root.shot("fr-many-overrides");
      } catch (error) {
        root.fail(error + "\n" + error.stack);
      }
    }
  }
  Timer {
    interval: 60000
    running: true
    onTriggered: root.fail("watchdog at " + root.phase + "/" + root.step)
  }
}
