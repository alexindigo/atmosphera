import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Power

ShellRoot {
  SettingsBootstrap {
    id: bootstrap
  }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      ShellSession {}
    }
  }
  IdleMonitor {
    timeout: 1
    respectInhibitors: false
    onIsIdleChanged: console.log("INPUT_ONLY_IDLE", isIdle)
  }
  IdleMonitor {
    timeout: 1
    onIsIdleChanged: console.log("POLICY_IDLE", isIdle)
  }
  IpcHandler {
    target: "idleRegression"
    function inhibit() {
      IdleInhibitorService.addInhibitor("regression", "Regression");
    }
    function release() {
      IdleInhibitorService.removeInhibitor("regression");
    }
  }
}
