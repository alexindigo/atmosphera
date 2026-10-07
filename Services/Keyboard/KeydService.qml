pragma Singleton
import DBus 1.0
import QtQuick
import Quickshell
import qs.Commons
import "../../Helpers/OwnedProcess.js" as OwnedProcess
import "../../Helpers/SystemdJob.js" as SystemdJob

Singleton {
  id: root
  readonly property string layerFile: "/etc/keyd/atmosphera"

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
    var source = Quickshell.shellDir + "/Bindings/environments/macos/keyd/" + (environment === "macos" ? "default.conf" : "atmosphera.stub");
    try {
      OwnedProcess.run(root, ["python3", "-c", "import os,json,sys; print(json.dumps({'present':os.path.lexists(sys.argv[1]),'writable':os.access(sys.argv[1],os.W_OK),'active':os.path.exists('/var/run/keyd.socket')}))", root.layerFile], null, function (probe) {
        if (!probe.success) { finish(false, probe.error, true); return; }
        var capability;
        try { capability = JSON.parse(probe.stdout); }
        catch (error) { finish(false, "Could not inspect managed keyd capability", true); return; }
        if (!capability.present) {
          Logger.i("KeydService", "Not applicable: managed keyd layer absent");
          finish(true, "", false);
          return;
        }
        if (!capability.writable) { finish(false, "Managed keyd layer is not writable", true); return; }
        OwnedProcess.run(root, ["sh", "-c", "awk '/^\\[ids\\]/{skip=1; next} /^\\[/{skip=0} !skip' \"$1\" > \"$2\"", "sh", source, root.layerFile], null, function (written) {
          if (!written.success) { finish(false, "Startup keyd write failed: " + written.error, true); return; }
          if (!capability.active) {
            Logger.i("KeydService", "Managed write settled; reload not applicable: keyd inactive");
            finish(true, "", false);
            return;
          }
          SystemdJob.run(root, systemdBus, "StartUnit", "atmosphera-keyd-reload.service", function (success, error) {
            finish(success, error, true);
          });
        });
      });
    } catch (error) {
      finish(false, "Startup keyd operation failed", true);
    }
  }

  DBus {
    id: systemdBus
    service: "org.freedesktop.systemd1"
    path: "/org/freedesktop/systemd1"
    iface: "org.freedesktop.systemd1.Manager"
    connection: SystemBus
  }
}
