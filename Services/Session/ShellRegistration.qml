pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import qs.Commons
import qs.Portals

// One election for the shell, its startup side effects and public endpoints.
// Queuing survives crash-restart overlap without replacing a live owner.
Singleton {
  id: root

  readonly property bool elected: _elected
  readonly property bool ipcReady: _elected && _ipcReady
  readonly property bool portalReady: _elected && _portalReady
  readonly property string status: !_elected ? (_lost ? "lost" : "waiting") : (ipcReady && portalReady ? "ready" : "acquired")
  property bool _elected: false
  property bool _lost: false
  property bool _ipcReady: false
  property bool _portalReady: false
  property bool _portalsInitialized: false

  onStatusChanged: Logger.i("ShellRegistration", status)

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
