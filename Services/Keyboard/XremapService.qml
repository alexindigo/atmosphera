pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import qs.Commons

// XremapService — gates the xremap user service on the bindings environment.
// xremap is a session-level remapper (systemd USER unit): users control
// their own user manager, so start/stop goes over the SESSION bus
// (org.freedesktop.systemd1 = the user manager there) with no polkit.
// The unit runs with --watch=config, so config redeploys self-apply; we only
// start it for env=macos and stop it otherwise.
Singleton {
  id: root

  readonly property string unitName: "xremap-atmosphera.service"

  function init() {
    _apply();
  }

  function _apply() {
    var env = "none";
    try {
      env = Settings.data.bindings.environment || "none";
    } catch (e) {}

    if (env === "macos") {
      Logger.d("XremapService", "Bindings env macos — starting", root.unitName);
      _callManager("StartUnit", [root.unitName, "replace"]);
    } else {
      Logger.d("XremapService", "Bindings env none — stopping", root.unitName);
      _callManager("StopUnit", [root.unitName, "replace"]);
    }
  }

  // Session bus handle to the systemd USER manager (same well-known name
  // as the system manager, but on the session bus).
  DBus {
    id: userManager
    service: "org.freedesktop.systemd1"
    path: "/org/freedesktop/systemd1"
    iface: "org.freedesktop.systemd1.Manager"
    connection: SessionBus
  }

  function _callManager(method, args) {
    var reply = userManager.call(method, args);
    if (!reply)
      return;
    reply.finished.connect(function () {
      if (reply.isError)
        Logger.w("XremapService", method, "failed:", reply.error.message);
      else
        Logger.d("XremapService", method, "ok");
    });
    if (reply.isFinished) {
      if (reply.isError)
        Logger.w("XremapService", method, "failed:", reply.error.message);
    }
  }

  Connections {
    target: Settings.data.bindings
    function onEnvironmentChanged() {
      root._apply();
    }
  }
}
