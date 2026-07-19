pragma Singleton

import QtQuick
import Quickshell
import DBus 1.0
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Singleton {
  id: root

  property bool available: false

  DBus {
    id: logind
    service: "org.freedesktop.login1"
    path: "/org/freedesktop/login1"
    iface: "org.freedesktop.login1.Manager"
    connection: SystemBus

    onStatusChanged: {
      if (status === 2) {
        root.available = true;
        Logger.i("LogindService", "logind subscription active");
      } else if (status === 3) {
        root.available = false;
        Logger.w("LogindService", "logind unreachable");
      }
    }

    onSignalReceived: function (name, args) {
      if (name !== "PrepareForSleep")
        return;
      var start = args && args.length > 0 ? args[0] : false;
      if (!start)
        return;
      if (!Settings.data.general.lockOnSuspend)
        return;
      if (PanelService.lockScreen && PanelService.lockScreen.active)
        return;
      Logger.i("LogindService", "PrepareForSleep(true) → locking");
      CompositorService.lock();
    }
  }

  function init() {
    Logger.i("LogindService", "Service started");
  }
}
