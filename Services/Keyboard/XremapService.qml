pragma Singleton
import DBus 1.0
import QtQuick
import Quickshell
import qs.Commons
import "../../Helpers/SystemdJob.js" as SystemdJob

Singleton {
  id: root
  readonly property string unitName: "xremap-atmosphera.service"

  function init(environment, onComplete) {
    var terminal = false;
    function finish(success, error, applicable) {
      if (terminal) return;
      terminal = true;
      if (typeof onComplete === "function") onComplete(success, error || "", applicable);
    }
    if (environment !== "none" && environment !== "macos") {
      finish(false, "Unsupported startup bindings environment", true);
      return;
    }
    SystemdJob.unitState(root, userManager, root.unitName, function (success, state, error, missing) {
      if (missing || (success && environment === "none" && state === "inactive")) {
        Logger.i("XremapService", "Not applicable:", missing ? "unit absent" : "already inactive");
        finish(true, "", false);
        return;
      }
      if (!success) { finish(false, error, true); return; }
      SystemdJob.run(root, userManager, environment === "macos" ? "StartUnit" : "StopUnit", root.unitName, function (completed, failure) {
        if (!completed) { finish(false, failure, true); return; }
        SystemdJob.unitState(root, userManager, root.unitName, function (read, current, readError) {
          var expected = environment === "macos" ? "active" : "inactive";
          finish(read && current === expected, readError || "Startup xremap did not reach " + expected, true);
        });
      });
    });
  }

  DBus {
    id: userManager
    service: "org.freedesktop.systemd1"
    path: "/org/freedesktop/systemd1"
    iface: "org.freedesktop.systemd1.Manager"
    connection: SessionBus
  }
}
