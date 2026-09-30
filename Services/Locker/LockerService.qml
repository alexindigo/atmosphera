pragma Singleton

import QtQuick
import Quickshell
import DBus 1.0
import qs.Commons

// Client + state mirror for the contract locker (app.atmosphera.Locker,
// interface app.atmosphera.Locker1). The locker is a per-lock standalone
// process the shell spawns detached on demand (swaylock model) — a
// systemd user service is a valid optional deployment, never required —
// and it owns the ext_session_lock_v1 object while engaged; name
// ownership is its liveness signal. While
// Settings.data.general.lockScreenMode === "service" the shell never
// creates a session lock of its own outside the in-process fallback —
// CompositorService routes lock actuation through lock() here.
Singleton {
  id: root

  // Name owned on the session bus.
  readonly property bool available: _available
  // Mirrors the locker's Active property + ActiveChanged signal.
  // False while unavailable (lock state then unknown).
  readonly property bool locked: _locked

  property bool _available: false
  property bool _locked: false

  DBus {
    id: locker
    service: "app.atmosphera.Locker"
    path: "/app/atmosphera/Locker"
    iface: "app.atmosphera.Locker1"
    connection: SessionBus
    watchServiceStatus: true

    onStatusChanged: {
      // Ready = introspected and signal matches in place — the earliest
      // moment Get("Active") and ActiveChanged delivery both work. Read
      // convergence here (not on bare appear) so a locker that restarted
      // while holding the lock is mirrored correctly.
      if (status === 2)
        root._readActive();
    }

    onServiceAvailableChanged: {
      if (serviceAvailable === root._available)
        return; // dbusqml fires appear more than once per registration
      if (serviceAvailable) {
        root._available = true;
        Logger.i("LockerService", "locker appeared");
      } else {
        root._available = false;
        root._setLocked(false);
        Logger.w("LockerService", "locker disappeared");
      }
    }

    onSignalReceived: function (name, args) {
      if (name !== "ActiveChanged")
        return;
      root._setLocked(args && args.length > 0 ? args[0] === true : false);
    }
  }

  function _setLocked(active) {
    if (root._locked === active)
      return;
    root._locked = active;
    Logger.i("LockerService", active ? "locker active" : "locker released");
  }

  // Converge on the locker's current state after (re-)appear — covers
  // the shell restarting while the locker holds the session lock.
  function _readActive() {
    var reply = locker.getProperty("Active");
    if (!reply)
      return;
    var done = function () {
      if (reply.isError || reply.value === undefined)
        return;
      root._setLocked(reply.value === true);
    };
    reply.finished.connect(done);
    if (reply.isFinished)
      done();
  }

  // Dispatch Lock(); returns false when the locker is absent so the
  // caller can fall back to the in-process lock screen (plan B.6).
  function lock() {
    if (!root._available)
      return false;
    locker.call("Lock", []);
    return true;
  }

  function init() {
    Logger.i("LockerService", "Service started");
  }
}
