//@ pragma Env ATMOSPHERA_LOCKSCREEN=1
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Keyboard
import qs.Services.Media

// Installed beside the actual packaged LockSession; no production file is
// changed. Inspection reads service contracts, not the child's private state.
ShellRoot {
  id: root
  property int spectrumChanges: 0
  property int keyChanges: 0

  // Ensure the enabled visualizer is actually registered before rejection, so
  // terminal cleanup is not a vacuous zero-registration observation.
  Loader {
    active: Settings.isLoaded
    source: Quickshell.shellDir + "/LockSession.qml"
  }

  Connections {
    target: SpectrumService
    function onValuesChanged() {
      root.spectrumChanges++;
    }
  }
  Connections {
    target: LockKeysService
    function onCapsLockChanged() {
      root.keyChanges++;
    }
    function onNumLockChanged() {
      root.keyChanges++;
    }
    function onScrollLockChanged() {
      root.keyChanges++;
    }
  }
  IpcHandler {
    target: "lockerResources"
    function status(): string {
      return JSON.stringify({
                              keysRegistered: LockKeysService._registeredCount,
                              keyPolling: LockKeysService.shouldRun,
                              spectrumRegistered: SpectrumService._registeredCount,
                              spectrumEnabled: SpectrumService._shouldRun,
                              spectrumChanges: root.spectrumChanges,
                              keyChanges: root.keyChanges
                            });
    }
  }
}
