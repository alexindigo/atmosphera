pragma Singleton

import DBus 1.0
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// TurboService — CPU turbo/boost toggle via the app.atmosphera.HwController
// helper (root, polkit-gated, D-Bus-activated). State is read live from
// sysfs (world-readable); the helper only performs the privileged write.
// Runtime-only: no boot persistence — machine policy owns that.
Singleton {
  id: root

  readonly property string intelNode: "/sys/devices/system/cpu/intel_pstate/no_turbo"
  readonly property string amdNode: "/sys/devices/system/cpu/cpufreq/boost"

  // Sysfs node exists → the platform has a turbo/boost knob
  readonly property bool available: _node !== ""
  // Helper on the bus → flipping is possible (else display-only)
  readonly property bool helperAvailable: hwController.serviceAvailable
  readonly property bool turboEnabled: _turboEnabled

  property string _node: ""
  property bool _turboEnabled: true

  // Detect the sysfs node (Intel pstate no_turbo, else AMD cpufreq boost)
  Process {
    id: nodeProbe
    running: false
    command: ["sh", "-c", "if [ -e " + root.intelNode + " ]; then echo intel; elif [ -e " + root.amdNode + " ]; then echo amd; fi"]
    stdout: StdioCollector {
      onStreamFinished: {
        var kind = text.trim();
        root._node = kind === "intel" ? root.intelNode : (kind === "amd" ? root.amdNode : "");
        if (root._node !== "") {
          nodeReader.path = root._node;
          nodeReader.reload();
        }
      }
    }
  }

  // Live state. watchChanges off — sysfs nodes don't emit inotify events;
  // we reload after our own writes and at startup.
  FileView {
    id: nodeReader
    printErrors: false
    watchChanges: false
    onLoaded: {
      var v = text().trim();
      if (root._node === root.intelNode) {
        root._turboEnabled = (v === "0"); // no_turbo=0 → turbo on
      } else {
        root._turboEnabled = (v === "1"); // boost=1 → boost on
      }
    }
    onLoadFailed: {
      root._turboEnabled = true;
    }
  }

  DBus {
    id: hwController
    service: "app.atmosphera.HwController"
    path: "/app/atmosphera/HwController"
    iface: "app.atmosphera.HwController"
    connection: SystemBus
    watchServiceStatus: true
  }

  function setTurboEnabled(enabled) {
    if (!root.available) {
      return;
    }
    var reply = hwController.call("SetTurbo", [enabled]);
    if (!reply) {
      ToastService.showWarning(I18n.tr("panels.hardware-health.turbo-label"), I18n.tr("panels.hardware-health.turbo-helper-missing"));
      return;
    }
    reply.finished.connect(function () {
      if (reply.isError) {
        Logger.w("Turbo", "SetTurbo failed:", reply.error.message);
        ToastService.showWarning(I18n.tr("panels.hardware-health.turbo-label"), reply.error.message);
      } else {
        Logger.i("Turbo", "SetTurbo", enabled, "ok");
      }
      // Read back from sysfs — the toggle visual follows the truth
      nodeReader.reload();
    });
  }

  Component.onCompleted: nodeProbe.running = true
}
