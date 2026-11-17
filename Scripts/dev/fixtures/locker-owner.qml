import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Control
import qs.Services.Locker

// Match the production root's directory-before-store construction boundary.
// This fixture owns no compositor lock itself.
ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component { OwnerProof {} }
  }

  component OwnerProof: Scope {
  id: root
  property int otherCompletions: 0
  property int suspendCompletions: 0
  Connections {
    target: LockOwnerService
    function onSuspendReady() { root.suspendCompletions++; }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (Settings.isLoaded) {
        LockOwnerService.init();
        stop();
      }
    }
  }
  IpcHandler {
    target: "lockerProof"
    function ready(): bool { return Settings.isLoaded; }
    function lock(): void { LockOwnerService.requestLock("owner-proof", false); }
    function lockAndSuspend(): void { LockOwnerService.requestLock("owner-proof", true); }
    function overlapHook(): void { HooksService.runHandler("screenOffAction", function () { root.otherCompletions++; }); }
    function lockViaHook(): void { HooksService.runHandler("lockAction", function () { throw new Error("lock escaped owner"); }); }
    function sleepWindow(): void { LockOwnerService.requestLock("prepare-for-sleep", false); }
    function completions(): string { return JSON.stringify({other: root.otherCompletions, suspend: root.suspendCompletions}); }
    function fingerprintPreference(value: bool): void { Settings.data.general.allowPasswordWithFprintd = value; }
    function exit(): void { Qt.quit(); }
  }
  }
}
