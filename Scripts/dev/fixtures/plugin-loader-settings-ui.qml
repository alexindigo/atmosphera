// Instance settings UI probe (L08). Runs as the qs entry of a disposable shell
// copy made by plugin-loader-regression.py --case settings-ui. It starts the
// plugin system the way shell.qml does (Registry.init, then Service.init once
// the sources are loaded), waits for the fx-instance instance api at the bar
// placement of entry index 1, and hosts NPluginSettingsPopup in a FloatingWindow
// so the popup is a real, visible dialog.
//
// Output (stdout, one line per step: SETTINGS_UI|<STEP>|<json>):
//   OPENED         instance popup open; the page shows the instance value
//   SAVED          the page saved "U" through the instance api
//   CONFIRM_OPENED confirmation open; saved override and unsaved page edits retained
//   CANCELLED      confirmation closed; same page and unsaved edits retained
//   CONFIRM_REOPENED confirmation open again, before the destructive action
//   RESET          Reset confirmed; the instance follows the plugin again
//   PLUGIN_OPENED  plugin-level popup open (no instance api, no reset button)
//   PLUGIN_SAVED   the page saved "Q" through the plugin api
//   DONE           exit 0
//   FAIL|<reason>  exit 2
//
// Env:
//   SETTINGS_UI_KEY      plugin key of the fx-instance fixture (set by the runner)
//   SETTINGS_UI_HOLD_MS  pause after each popup/confirmation opens, for screenshots (default 0)

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: probe

  readonly property string pluginKey: Quickshell.env("SETTINGS_UI_KEY") || ""
  readonly property int holdMs: parseInt(Quickshell.env("SETTINGS_UI_HOLD_MS") || "0", 10) || 0
  // Entry index 1 of the runner's bar right section (the entry with overrides).
  readonly property var placement: ({
                                      "kind": "bar",
                                      "list": "global",
                                      "section": "right",
                                      "index": 1
                                    })
  readonly property int waitLimitMs: 60000

  property var api: null
  property var manifest: null
  property var instancePage: null
  property string phase: "sources"
  property real phaseAt: Date.now()

  Component.onCompleted: Registry.init()

  function setPhase(name) {
    probe.phase = name;
    probe.phaseAt = Date.now();
  }

  function elapsed() {
    return Date.now() - probe.phaseAt;
  }

  function emit(step, data) {
    console.log("SETTINGS_UI|" + step + "|" + JSON.stringify(data));
  }

  function fail(reason) {
    console.log("SETTINGS_UI|FAIL|" + JSON.stringify(reason));
    Qt.exit(2);
  }

  function effectiveLabel() {
    return probe.api ? probe.api.pluginSettings.label : null;
  }

  function pageReady() {
    return popup.opened && popup.settingsPage !== null && popup.settingsPage !== undefined;
  }

  function confirmation() {
    return popup["resetConfirmation"] || null;
  }

  function confirmationVisible() {
    return !!probe.confirmation()?.visible;
  }

  function buttonWithText(item, text) {
    if (item.text === text && typeof item.clicked === "function")
      return item;
    var children = item.children || [];
    for (var i = 0; i < children.length; i++) {
      var button = probe.buttonWithText(children[i], text);
      if (button)
        return button;
    }
    return null;
  }

  function pressConfirmationButton(key) {
    var dialog = probe.confirmation();
    var button = dialog ? probe.buttonWithText(dialog.contentItem, I18n.tr(key)) : null;
    if (!button) {
      probe.fail("confirmation button missing: " + key);
      return;
    }
    button.clicked();
  }

  function drive() {
    var page = popup.settingsPage;
    switch (probe.phase) {
    case "sources":
      if (Registry.getEnabledSources().length > 0) {
        Service.init();
        probe.setPhase("instance-api");
      } else if (probe.elapsed() > probe.waitLimitMs) {
        probe.fail("sources never loaded");
      }
      break;
    case "instance-api":
      probe.api = PluginInstances.apiFor(probe.pluginKey, probe.placement);
      if (probe.api) {
        probe.manifest = Registry.getPluginManifest(probe.pluginKey);
        probe.setPhase("open-instance");
      } else if (probe.elapsed() > probe.waitLimitMs) {
        probe.fail("instance api never available for " + probe.pluginKey);
      }
      break;
    case "open-instance":
      popup.openInstanceSettings(probe.manifest, probe.api, "settings");
      probe.setPhase("wait-instance-open");
      break;
    case "wait-instance-open":
      if (probe.pageReady()) {
        probe.emit("OPENED", {
                     "instance": popup.isInstance,
                     "label": page.labelText,
                     "effective": probe.effectiveLabel(),
                     "resetVisible": popup.resetButton.visible
                   });
        probe.setPhase("hold-instance");
      } else if (probe.elapsed() > probe.waitLimitMs) {
        probe.fail("instance popup never opened");
      }
      break;
    case "hold-instance":
      if (probe.elapsed() >= probe.holdMs)
        probe.setPhase("save-instance");
      break;
    case "save-instance":
      page.labelText = "U";
      page.saveSettings();
      probe.setPhase("settle-instance-save");
      break;
    case "settle-instance-save":
      if (probe.elapsed() >= 1500) {
        probe.emit("SAVED", {
                     "page": page.labelText,
                     "effective": probe.effectiveLabel()
                   });
        probe.setPhase("reset-instance");
      }
      break;
    case "reset-instance":
      probe.instancePage = page;
      page.labelText = "unsaved";
      popup.resetButton.clicked();
      probe.setPhase("wait-confirmation");
      break;
    case "wait-confirmation":
      if (probe.elapsed() >= 1500) {
        probe.emit("CONFIRM_OPENED", {
                     "visible": probe.confirmationVisible(),
                     "page": popup.settingsPage.labelText,
                     "effective": probe.effectiveLabel(),
                     "samePage": popup.settingsPage === probe.instancePage
                   });
        if (!probe.confirmationVisible()) {
          probe.fail("reset confirmation did not open");
          return;
        }
        probe.setPhase("hold-confirmation");
      }
      break;
    case "hold-confirmation":
      if (probe.elapsed() >= Math.max(1500, probe.holdMs)) {
        probe.pressConfirmationButton("common.cancel");
        probe.setPhase("wait-cancel");
      }
      break;
    case "wait-cancel":
      if (probe.elapsed() >= 1500) {
        probe.emit("CANCELLED", {
                     "visible": probe.confirmationVisible(),
                     "page": page.labelText,
                     "effective": probe.effectiveLabel(),
                     "samePage": page === probe.instancePage
                   });
        probe.setPhase("hold-cancelled");
      }
      break;
    case "hold-cancelled":
      if (probe.elapsed() >= 1500) {
        popup.resetButton.clicked();
        probe.setPhase("wait-confirmation-again");
      }
      break;
    case "wait-confirmation-again":
      if (probe.elapsed() >= 1500) {
        probe.emit("CONFIRM_REOPENED", {
                     "visible": probe.confirmationVisible(),
                     "page": page.labelText,
                     "effective": probe.effectiveLabel()
                   });
        probe.setPhase("hold-confirmation-again");
      }
      break;
    case "hold-confirmation-again":
      if (probe.elapsed() >= Math.max(1500, probe.holdMs)) {
        probe.pressConfirmationButton("common.reset");
        probe.setPhase("settle-reset");
      }
      break;
    case "settle-reset":
      if (probe.elapsed() >= 1500) {
        probe.emit("RESET", {
                     "page": popup.settingsPage.labelText,
                     "effective": probe.effectiveLabel(),
                     "instance": popup.isInstance,
                     "confirmationVisible": probe.confirmationVisible()
                   });
        probe.setPhase("close-instance");
      }
      break;
    case "close-instance":
      popup.close();
      probe.setPhase("settle-close");
      break;
    case "settle-close":
      if (probe.elapsed() >= 500)
        probe.setPhase("open-plugin");
      break;
    case "open-plugin":
      popup.openPluginSettings(probe.manifest, "settings");
      probe.setPhase("wait-plugin-open");
      break;
    case "wait-plugin-open":
      if (probe.pageReady()) {
        probe.emit("PLUGIN_OPENED", {
                     "instance": popup.isInstance,
                     "label": page.labelText,
                     "resetVisible": popup.resetButton.visible,
                     "confirmationVisible": probe.confirmationVisible()
                   });
        probe.setPhase("hold-plugin");
      } else if (probe.elapsed() > probe.waitLimitMs) {
        probe.fail("plugin popup never opened");
      }
      break;
    case "hold-plugin":
      if (probe.elapsed() >= probe.holdMs)
        probe.setPhase("save-plugin");
      break;
    case "save-plugin":
      page.labelText = "Q";
      page.saveSettings();
      probe.setPhase("settle-plugin-save");
      break;
    case "settle-plugin-save":
      if (probe.elapsed() >= 1500) {
        probe.emit("PLUGIN_SAVED", {
                     "page": page.labelText,
                     "effective": probe.effectiveLabel()
                   });
        probe.setPhase("done");
      }
      break;
    case "done":
      console.log("SETTINGS_UI|DONE|{}");
      Qt.exit(0);
      break;
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: probe.drive()
  }

  FloatingWindow {
    id: host

    title: "settings-ui-probe"
    visible: true
    implicitWidth: 760
    implicitHeight: 640

    NPluginSettingsPopup {
      id: popup

      parent: Overlay.overlay
      showToastOnSave: false
    }
  }
}
