import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property var api: null
  property string phase: "start"
  readonly property bool negative: Quickshell.env("I5_CALIBRE_NEGATIVE") === "1"
  function check(ok, label) { if (!ok) throw new Error("I5_CALIBRE_INVALID_ASSERT: " + label); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    Service._openSettingsOwner("calibre-provider", function (owner) {
      try {
        root.check(owner !== null, "actual native Calibre owner opened");
        var manifest = JSON.parse(Quickshell.env("I5_CALIBRE_MANIFEST"));
        root.api = Service.createPluginAPI("calibre-provider", manifest, owner, {}, {}, {});
        var loaded = Object.assign({}, Service.loadedPlugins);
        loaded["calibre-provider"] = {api: root.api};
        Service.loadedPlugins = loaded;
        root.check(root.api.pluginSettings.recentlyOpenedFiles.length === 0, "invalid records are not claimed as admitted numeric IDs");
        popup.openPluginSettings(manifest, "settings");
        root.phase = "page";
      } catch (error) { root.fail(error); }
    });
  }
  function drive() {
    if (phase === "page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup.settingsPage.settingsDirty, "actual page constructor clean");
      check(api.settingsOwner.store.settingsKeys.every(function (key) { return api.settingsHandle.info([key]).latestInput === "0"; }), "constructor created no preference intent");
      popup.requestClose();
      check(!popup.discardPending, "clean Cancel needs no discard");
      phase = "close";
    } else if (phase === "close" && !popup.visible && !popup.currentPlugin) {
      phase = "receipt";
      if (negative) api.pluginSettings.recentlyOpenedFiles = [];
      api.saveSettings(function (result) {
        try {
          console.log("I5_CALIBRE_INVALID_RECEIPT", JSON.stringify(result));
          root.check(result.status !== "saved", "clean source may not replace original invalid raw records");
          root.check(result.status === "nothing_to_save" || result.status === "failed", "truthful terminal clean receipt");
          console.log("I5_CALIBRE_INVALID: PASS"); Qt.exit(0);
        } catch (error) { root.fail(error); }
      });
    }
  }
  FloatingWindow {
    visible: true; implicitWidth: 800; implicitHeight: 650
    NPluginSettingsPopup { id: popup; parent: Overlay.overlay }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 50; repeat: true; running: true; onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } } }
  Timer { interval: 25000; running: true; onTriggered: root.fail("I5_CALIBRE_INVALID_ASSERT: watchdog " + root.phase) }
}
