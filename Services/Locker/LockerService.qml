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
  // Corroborating session state only, never a candidate's secure ack.
  readonly property bool lockedHintAvailable: _lockedHintAvailable

  property bool _contractAvailable: false
  property bool _locked: false
  property bool _lockedHintAvailable: false
  signal sessionUnlocked

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

  // --- Locker1 v2 correlated observation (docs/locker1-contract.md) ---
  // Each owner lifetime has a fixed unique-destination subscription. Requests,
  // replies and signals carry that lifetime, never a mutable name's identity.
  readonly property string contractOwner: _contractOwner
  readonly property var contractObservations: _contractObservations
  property var _contractObservations: ({})
  property string _contractOwner: ""
  property int _contractRevision: 0
  property var _contractSubscription: null
  signal contractObserved(string requestId)

  function _settle(reply, done) {
    if (!reply) {
      done(null);
      return;
    }
    var settled = false;
    var finish = function () {
      if (settled)
        return;
      settled = true;
      done(reply);
    };
    reply.finished.connect(finish);
    if (reply.isFinished)
      finish();
  }

  function _resolveOwner(done) {
    var revision = _contractRevision;
    root._settle(busDaemon.call("GetNameOwner", ["app.atmosphera.Locker"]), function (reply) {
      if (revision !== root._contractRevision) {
        done("", root._contractRevision);
        return;
      }
      var owner = reply && !reply.isError ? String(reply.value || "") : "";
      root._changeOwner(owner);
      done(owner, root._contractRevision);
    });
  }

  function _changeOwner(owner) {
    if (_contractOwner === owner)
      return;
    _contractRevision++;
    if (_contractSubscription) {
      _contractSubscription.enabled = false;
      _contractSubscription.destroy();
      _contractSubscription = null;
    }
    _contractOwner = owner;
    if (owner !== "")
      _contractSubscription = contractSubscription.createObject(root, {owner: owner, revision: _contractRevision});
  }

  function _ownerCall(owner, revision, iface, member, args, signature, done) {
    if (owner !== _contractOwner || revision !== _contractRevision) {
      done(null);
      return;
    }
    var pending = SessionBus.asyncCall({service: owner, path: "/app/atmosphera/Locker",
      iface: iface, member: member, arguments: args, signature: signature, autoStart: false});
    _settle(pending, function (reply) {
      // A daemon round trip also fences a name change whose watcher delivery
      // has not run yet. A->B->A is rejected by the lifetime revision as well.
      root._resolveOwner(function (current, currentRevision) {
        done(current === owner && currentRevision === revision ? reply : null);
      });
    });
  }

  function _observe(owner, revision, requestId, event) {
    if (typeof requestId !== "string" || requestId === "" || owner !== _contractOwner || revision !== _contractRevision)
      return;
    var next = Object.assign({}, root._contractObservations);
    var entry = Object.assign({}, next[requestId] || {});
    // First owner wins per request; a different owner's later claim is kept
    // separately so the adapter can refuse it, never merged into the first.
    if (entry.owner && entry.owner !== owner)
      entry = {owner: owner, ownerChanged: true};
    entry.owner = owner;
    entry[event] = true;
    next[requestId] = entry;
    root._contractObservations = next;
    contractObserved(requestId);
  }

  // Class-3 invocation. A v2 service receives the generation's request ID;
  // older services keep the original Lock(). complete({ok, owner, version}).
  function requestContract(requestId, complete) {
    if (!root._contractAvailable) {
      complete({ok: false});
      return;
    }
    root._resolveOwner(function (owner, revision) {
      if (owner === "") {
        complete({ok: false});
        return;
      }
      root._ownerCall(owner, revision, "org.freedesktop.DBus.Properties", "Get", ["app.atmosphera.Locker1", "Version"], "ss", function (versionReply) {
        if (!versionReply) {
          complete({ok: false});
          return;
        }
        var value = versionReply && !versionReply.isError ? Number(versionReply.value) : 1;
        var version = Number.isInteger(value) && value >= 2 ? value : 1;
        root._ownerCall(owner, revision, "app.atmosphera.Locker1", version >= 2 ? "LockRequest" : "Lock", version >= 2 ? [requestId] : [], version >= 2 ? "s" : "", function (reply) {
          complete({ok: !!reply && !reply.isError, owner: owner, version: version});
        });
      });
    });
  }

  // Restart reconciliation: the service's own view of one request.
  function queryContract(requestId, complete) {
    if (!root._contractAvailable) {
      complete({ok: false});
      return;
    }
    root._resolveOwner(function (owner, revision) {
      if (owner === "") {
        complete({ok: false});
        return;
      }
      root._ownerCall(owner, revision, "app.atmosphera.Locker1", "RequestState", [requestId], "s", function (reply) {
        complete({ok: !!reply && !reply.isError, owner: owner, state: reply && !reply.isError ? String(reply.value) : ""});
      });
    });
  }

  DBus {
    id: busDaemon
    service: "org.freedesktop.DBus"
    path: "/org/freedesktop/DBus"
    iface: "org.freedesktop.DBus"
    connection: SessionBus
    propertiesEnabled: false
    signalsEnabled: false
  }

  DBusServiceWatcher {
    service: "app.atmosphera.Locker"
    onOwnerChanged: (oldOwner, newOwner) => root._changeOwner(newOwner)
  }

  Component {
    id: contractSubscription
    DBusSignalWatcher {
      required property string owner
      required property int revision
      service: owner
      path: "/app/atmosphera/Locker"
      iface: "app.atmosphera.Locker1"
      member: ""
      onReceived: (member, args) => {
        if (member === "Secured" || member === "Unlocked")
          root._observe(owner, revision, args && args.length > 0 ? args[0] : "", member === "Secured" ? "secured" : "unlocked");
      }
    }
  }

  // --- LockedHint watch (universal lock state) ---

  function _setLocked(active) {
    if (root._locked === active)
      return;
    root._locked = active;
    Logger.i("LockerService", active ? "locked" : "unlocked");
    if (!active)
      sessionUnlocked();
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

  // The owner discovers the display-bound graphical session, not SSH/seat0.
  function observeSession(id) {
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
