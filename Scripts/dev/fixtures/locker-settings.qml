import QtQuick
import Quickshell
import Quickshell.Io
import ConfigQml 1.0
import qs.Commons
import "../../../Helpers/LockerSettingsInput.js" as Input

// No Wayland lock, PAM or synthetic secure/unlock event. Exercise the actual
// installed Settings consumer's native write capability and close boundary.
ShellRoot {
  id: root
  property bool checked: false
  property int completions: 0
  property bool waitingForUpdate: false

  function closeReader() {
    Settings.store.save();
    Settings.store.flush();
    Settings.store.close();
  }
  Timer {
    interval: 20
    running: !root.checked
    repeat: true
    onTriggered: {
      if (Quickshell.env("LOCKER_SETTINGS_EXPECT_ERROR") === "1" && Settings.store?.status === ConfigStore.Error) {
        console.log("PASS rejected-settings-generation", Settings.store.error);
        Qt.quit();
        return;
      }
      if (!Settings.isLoaded)
        return;
      if (Quickshell.env("LOCKER_SETTINGS_EXPECT_ERROR") === "1") {
        console.error("FAIL wrong-generation input became ready");
        Qt.exit(4);
        return;
      }
      root.checked = true;
      var rejected = false;
      try { Settings.store.setUser(["general", "compactLockScreen"], !Settings.data.general.compactLockScreen); }
      catch (error) { rejected = true; }
      if (!rejected) {
        console.error("FAIL settings consumer accepted persistent input");
        Qt.exit(1);
        return;
      }
      console.log("READONLY_VALUES", JSON.stringify({compact: Settings.data.general.compactLockScreen,
        defaultFont: Settings.data.ui.fontDefault, home: Settings.data.general.avatarImage}));
      if (Quickshell.env("LOCKER_SETTINGS_CODEC") === "1")
        console.log("INPUT_CODEC", Input.capture(Settings.data, Settings.store));
      if (Quickshell.env("LOCKER_SETTINGS_LIVE") === "1")
        root.waitingForUpdate = true;
      else
        root.closeReader();
    }
  }
  Connections {
    target: Settings.store
    function onSettingValuesChanged(paths) {
      if (root.waitingForUpdate && Settings.data.general.compactLockScreen === false) {
        root.waitingForUpdate = false;
        console.log("PASS live-settings-consumer");
        root.closeReader();
      }
    }
    function onCompleted(result) {
      if (["save", "flush", "close"].indexOf(result.operation) === -1)
        return;
      if (result.status !== "nothing_to_save") {
        console.error("FAIL read-only publication", result.operation, result.status);
        Qt.exit(2);
        return;
      }
      root.completions++;
      if (root.completions === 3) {
        console.log("PASS native-readonly-settings");
        Qt.quit();
      }
    }
  }
  IpcHandler {
    target: "settingsProof"
    function waiting(): bool { return root.waitingForUpdate; }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("READONLY_SETTINGS_TIMEOUT", Settings.store, Settings.store?.status, Settings.store?.error);
      Qt.exit(3);
    }
  }
}
