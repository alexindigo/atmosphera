pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import DBus 1.0
import qs.Commons

// Lock actuation presence + universal lock state for the out-of-process
// lock screen (no-modes model, 2026-09-30 owner ruling):
//
// - contractAvailable — a persistent class-3 locker (aerial-lock) owns
//   app.atmosphera.Locker; name ownership selects signal invocation
//   (Lock()) over spawning.
// - locked — niri sets the session's logind LockedHint compositor-side
//   for ANY session-lock client (bundled config, swaylock class,
//   contract service, even the in-process fallback), so it is the one
//   state source that covers every locker class. Watched as
//   PropertiesChanged on the seat session's logind object, converged
//   via Get at startup.
Singleton {
  id: root

  readonly property bool contractAvailable: _contractAvailable
  readonly property bool locked: _locked
  // False until the seat session's LockedHint has been read once —
  // consumers degrade to the in-process flag while this is false.
  readonly property bool lockedHintAvailable: _lockedHintAvailable

  property bool _contractAvailable: false
  property bool _locked: false
  property bool _lockedHintAvailable: false

  // --- class-3 contract presence + invocation ---

  DBus {
    id: contract
    service: "app.atmosphera.Locker"
    path: "/app/atmosphera/Locker"
    iface: "app.atmosphera.Locker1"
    connection: SessionBus
    watchServiceStatus: true

    onServiceAvailableChanged: {
      if (serviceAvailable === root._contractAvailable)
        return; // dbusqml fires appear more than once per registration
      root._contractAvailable = serviceAvailable;
      if (serviceAvailable)
        Logger.i("LockerService", "contract locker appeared");
      else
        Logger.w("LockerService", "contract locker disappeared");
    }
  }

  // Class-3 invocation: dispatch Lock(); false when no contract service.
  function lock() {
    if (!root._contractAvailable)
      return false;
    contract.call("Lock", []);
    return true;
  }

  // --- LockedHint watch (universal lock state) ---

  function _setLocked(active) {
    if (root._locked === active)
      return;
    root._locked = active;
    Logger.i("LockerService", active ? "locked" : "unlocked");
  }

  function _convergeLockedHint() {
    var reply = sessionProxy.getProperty("LockedHint");
    if (!reply)
      return;
    var done = function () {
      if (reply.isError || reply.value === undefined)
        return;
      root._lockedHintAvailable = true;
      root._setLocked(reply.value === true);
    };
    reply.finished.connect(done);
    if (reply.isFinished)
      done();
  }

  // The seat0 session id (bare `loginctl show-session` does not resolve
  // the graphical session from a systemd user service — resolve via the
  // session list).
  Process {
    id: seatSessionQuery
    command: ["sh", "-c", "loginctl list-sessions --no-legend | awk '$4==\"seat0\" {print $1; exit}'"]
    running: true
    stdout: StdioCollector {}
    onExited: function (exitCode) {
      var id = (stdout.text || "").trim();
      if (exitCode !== 0 || id === "")
        return;
      var reply = logindManager.call("GetSession", [id]);
      if (!reply)
        return;
      var done = function () {
        if (reply.isError || !reply.values || reply.values.length === 0)
          return;
        sessionProxy.path = String(reply.values[0]);
      };
      reply.finished.connect(done);
      if (reply.isFinished)
        done();
    }
  }

  DBus {
    id: logindManager
    service: "org.freedesktop.login1"
    path: "/org/freedesktop/login1"
    iface: "org.freedesktop.login1.Manager"
    connection: SystemBus
  }

  DBus {
    id: sessionProxy
    service: "org.freedesktop.login1"
    iface: "org.freedesktop.login1.Session"
    connection: SystemBus
    // path is set once the seat session resolves

    onStatusChanged: {
      // Ready = introspected + initial GetAll answered (path set)
      if (status === 2 && path !== "")
        root._convergeLockedHint();
    }

    onPathChanged: {
      if (path !== "" && status === 2)
        root._convergeLockedHint();
    }

    onSignalReceived: function (name, args) {
      if (name !== "PropertiesChanged")
        return;
      // (s interface, a{sv} changed, as invalidated)
      var changed = args && args.length > 1 ? args[1] : null;
      if (changed && changed.LockedHint !== undefined)
        root._setLocked(changed.LockedHint === true);
    }
  }

  function init() {
    Logger.i("LockerService", "Service started");
  }
}
