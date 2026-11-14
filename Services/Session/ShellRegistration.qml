pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Portals

// One election for the shell, its startup side effects and public endpoints.
// Queuing survives crash-restart overlap without replacing a live owner.
Singleton {
  id: root

  readonly property bool elected: _elected && _ownerChecked
  readonly property bool ipcReady: elected && _ipcReady
  readonly property bool portalReady: elected && _portalReady
  readonly property string status: !_elected ? (_lost ? "lost" : "waiting") : (ipcReady && portalReady ? "ready" : "acquired")
  property bool _elected: false
  property bool _lost: false
  property bool _ipcReady: false
  property bool _portalReady: false
  property bool _portalsInitialized: false
  property bool _ownerChecked: false

  onStatusChanged: Logger.i("ShellRegistration", status)

  // The same pidfd supervisor serves explicit handoffs and unsupervised raw
  // spawns. Keep session initialization behind its departed-resource check:
  // Notifications claims its name only once, when its server is constructed.
  Process {
    id: ownerGuard
    command: ["python3", "-B", Quickshell.shellDir + "/Scripts/bash/shell-owner.py", "watch", "--pid", String(Quickshell.processId), "--instance", Quickshell.instanceId]
    running: true
    stderr: SplitParser {
      onRead: data => Logger.w("ShellRegistration", data)
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 10) {
        // Acquisition can race the helper's final responsive-owner reply.
        // An elected successor must finish its resource check, not quit.
        if (root._elected)
          ownerGuard.running = true;
        else
          Qt.quit();
      } else if (exitCode === 0) {
        root._ownerChecked = true;
      } else {
        Logger.e("ShellRegistration", "owner recovery failed; session not initialized");
        Qt.quit();
      }
    }
  }

  DBusAdaptor {
    service: "app.atmosphera.Shell"
    path: "/app/atmosphera/Shell"
    iface: "app.atmosphera.Shell1"
    connection: SessionBus
    queueOnBusy: true

    readonly property bool ipcReady: root.ipcReady
    readonly property bool portalReady: root.portalReady
    readonly property string status: root.status
    readonly property string configPath: Quickshell.shellDir + "/shell.qml"
    readonly property string instanceId: Quickshell.instanceId

    function ping(): string {
      return root.status;
    }

    onNameAcquired: {
      root._lost = false;
      root._elected = true;
    }
    onNameLost: {
      root._lost = true;
      root._elected = false;
      root._ipcReady = false;
    }
  }

  function startPortals() {
    if (root._portalsInitialized)
      return;
    SettingsPortal.init();
    FileChooserPortal.init();
    InhibitPortal.init();
    root._portalsInitialized = true;
  }

  function markIpcReady() {
    root._ipcReady = true;
  }

  Loader {
    active: root.elected && root._portalsInitialized
    sourceComponent: DBusAdaptor {
      service: "org.freedesktop.impl.portal.desktop.atmosphera"
      path: "/app/atmosphera/Portal"
      iface: "app.atmosphera.Portal1"
      connection: SessionBus
      queueOnBusy: true

      function ping(): bool {
        return root.portalReady;
      }

      onNameAcquired: {
        root._portalReady = true;
        Logger.i("ShellRegistration", "portal acquired");
      }
      onNameLost: {
        root._portalReady = false;
        FileChooserPortal.cancelAll();
        InhibitPortal.releaseAll();
        Logger.w("ShellRegistration", "portal lost");
      }
      Component.onDestruction: {
        root._portalReady = false;
        FileChooserPortal.cancelAll();
        InhibitPortal.releaseAll();
      }
      Component.onCompleted: Logger.i("ShellRegistration", "portal waiting")
    }
  }
}
