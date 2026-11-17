pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Control
import qs.Services.Locker
import "../../Helpers/OwnedProcess.js" as OwnedProcess
import "../../Helpers/LockerLifecycle.js" as Lifecycle
import "../../Helpers/LockerSettingsInput.js" as SettingsInput

// Sole lock-operation actuator. The adapter serializes exact generation/unit
// effects across shell restarts; it never selects a backend or unlocks Wayland.
Singleton {
  id: root

  readonly property string state: _state
  readonly property bool secure: _secure
  readonly property string holder: _holder
  readonly property var status: ({state: _state, secure: _secure, holder: _holder,
    descriptor: _view?.descriptor || null, units: _view?.units || {}, error: _error})
  readonly property string adapterPath: Quickshell.shellDir + "/Scripts/python/locker-unit.py"
  property string _session: ""
  property string _state: "unlocked"
  property string _holder: ""
  property bool _secure: false
  property bool _busy: false
  property bool _takeover: false
  property bool _initialized: false
  property bool _pendingRequest: false
  property bool _pendingSuspend: false
  property int _pendingSleepWindow: -1
  property string _reason: ""
  property string _error: ""
  property var _view: null
  property var _contractAck: null
  property bool _unlockObserved: false
  property bool _contractFailed: false
  property bool _settingsPending: false
  property string _settingsGeneration: ""

  signal suspendReady
  signal secureChangedForSleep(bool confirmed)

  function quoted(text) { return "'" + String(text).replace(/'/g, "'\\''") + "'"; }

  function snapshot() {
    var handler = HooksService.handlerFor("lockAction");
    var custom = "";
    var options = Settings.data.sessionMenu.powerOptions || [];
    for (var i = 0; i < options.length; i++) {
      if (options[i].action === "lock" && options[i].enabled && options[i].command?.trim()) {
        custom = options[i].command.trim();
        break;
      }
    }
    var external = Settings.data.general.externalLockCommand || "";
    var exclusive = handler && handler.exclusive;
    var legacyExternal = Settings.data.general.lockScreenPlugin === "external" && external !== "";
    var kind = exclusive || custom !== "" || legacyExternal ? "opaque"
      : LockerService.contractAvailable ? "contract" : external !== "" ? "opaque" : "bundled";
    var command = exclusive ? "sh -lc " + quoted(handler.command)
      : custom !== "" ? custom : kind === "bundled" ? "qs -c atmosphera-lockscreen" : external;
    return {adapter: kind, command: command,
      prehook: handler && !handler.exclusive ? "sh -lc " + quoted(handler.command) : "",
      lockHook: HooksService.listenerCommandFor("screenLock", "screenLock"),
      unlockHook: HooksService.listenerCommandFor("screenUnlock", "screenUnlock"),
      suspendAfterSecure: _pendingSuspend, sleepWindow: _pendingSleepWindow === 1, reason: _reason};
  }

  function call(operation, extra, complete) {
    if (_busy)
      return;
    _busy = true;
    var job = {operation: operation, session: _session};
    if (_view?.descriptor)
      job.generation = _view.descriptor.generation;
    Object.assign(job, extra || {});
    OwnedProcess.run(root, ["python3", adapterPath, "manage"], JSON.stringify(job), function (result) {
      _busy = false;
      var reply;
      try { reply = JSON.parse(result.stdout); }
      catch (error) { reply = {ok: false, error: "Locker adapter returned no result: " + result.error}; }
      if (!reply.ok) {
        _error = reply.error;
        Logger.e("LockOwner", operation + ": " + _error);
      } else {
        _error = "";
      }
      if (complete)
        complete(reply);
    });
  }

  function requestLock(reason, suspendAfterSecure) {
    if (Quickshell.env("ATMOSPHERA_LOCKSCREEN") === "1")
      return;
    if (!Settings.data.general.lockScreenEnabled)
      return;
    _pendingRequest = true;
    _pendingSuspend = _pendingSuspend || suspendAfterSecure === true;
    if (reason === "prepare-for-sleep")
      _pendingSleepWindow = 1;
    _reason = reason || "lock";
    init();
    pump();
  }

  function init() {
    if (_initialized || Quickshell.env("ATMOSPHERA_LOCKSCREEN") === "1")
      return;
    _initialized = true;
    pump();
  }

  function observeSleepWindow(active) {
    _pendingSleepWindow = active ? 1 : 0;
    pump();
  }

  // Reserved for a future correlated contract adapter. There is deliberately
  // no new D-Bus method/signal, nor an IPC method accepting unauthenticated ack.
  function acceptContractAck(session, generation, confirmed) {
    if (!_view?.descriptor || session !== _session || generation !== _view.descriptor.generation
        || _view.descriptor.snapshot.adapter !== "contract")
      return false;
    _contractAck = {generation: generation, secure: confirmed === true};
    pump();
    return true;
  }

  function pump() {
    if (!_initialized || _busy)
      return;
    if (_session === "") {
      call("discover", {}, function (reply) {
        if (reply.ok) {
          _session = reply.value.session;
          _takeover = reply.value.takeover;
          LockerService.observeSession(_session);
          Qt.callLater(pump);
        }
      });
      return;
    }
    call("inspect", {}, function (reply) {
      if (!reply.ok)
        return;
      _view = reply.value;
      reconcile();
    });
  }

  function effect(operation, extra) {
    call(operation, extra, function () { Qt.callLater(pump); });
  }

  function reconcile() {
    var d = _view.descriptor;
    if (!d || d.phase === "settled") {
      publish("unlocked", "", false);
      if (_pendingRequest) {
        var config = snapshot();
        call("begin", {snapshot: config, settingsJson: config.adapter === "bundled" ? SettingsInput.capture(Settings.data, Settings.store) : null}, function (reply) {
          if (reply.ok) {
            _pendingRequest = false;
            _pendingSuspend = false;
            _pendingSleepWindow = -1;
            _contractAck = null;
            _unlockObserved = false;
            _contractFailed = false;
            _settingsPending = false;
            _settingsGeneration = reply.value.generation;
            _view = {descriptor: reply.value, units: {}, now: reply.value.requestedAt};
            Qt.callLater(pump);
          }
        });
      }
      return;
    }
    if (_pendingRequest) {
      var suspend = _pendingSuspend;
      _pendingRequest = false;
      _pendingSuspend = false;
      effect("intent", {suspendAfterSecure: suspend});
      return;
    }
    if ((_unlockObserved && !d.sessionUnlockObserved) || (_contractFailed && !d.contractFailed)) {
      effect("note", {sessionUnlockObserved: _unlockObserved, contractFailed: _contractFailed});
      return;
    }
    if (_pendingSleepWindow !== -1) {
      var sleepActive = _pendingSleepWindow === 1;
      _pendingSleepWindow = -1;
      effect("sleep-window", {active: sleepActive});
      return;
    }

    var units = d.units;
    if (d.snapshot.adapter === "bundled" && _settingsGeneration !== d.generation) {
      _settingsGeneration = d.generation;
      _settingsPending = true;
    }
    if (_settingsPending && d.snapshot.adapter === "bundled" && d.phase !== "unlocking") {
      _settingsPending = false;
      call("settings", {settingsJson: SettingsInput.capture(Settings.data, Settings.store)}, function (reply) {
        if (!reply.ok) _settingsPending = true;
        Qt.callLater(pump);
      });
      return;
    }
    var prehookPending = false;
    if (d.phase !== "unlocking" && d.snapshot.prehook) {
      if (!units.prehook) {
        effect("launch", {role: "prehook", command: d.snapshot.prehook});
        return;
      }
      prehookPending = !_view.units.prehook.gone;
      if (prehookPending && _view.now < d.emergencyAt)
        return;
    }
    if (d.phase !== "unlocking" && !d.lockHookStarted) {
      if (d.snapshot.lockHook && !units.lockhook) {
        effect("launch", {role: "lockhook", command: "sh -lc " + quoted(d.snapshot.lockHook) + " lock-hook lock"});
        return;
      }
      effect("note", {lockHookStarted: true});
      return;
    }
    if (d.snapshot.adapter === "contract" && !d.contractRequested && !prehookPending && d.phase !== "unlocking") {
      call("note", {contractRequested: true}, function (reply) {
        if (!reply.ok)
          return;
        var generation = d.generation;
        LockerService.requestContract(function (success) {
          if (!_view?.descriptor || _view.descriptor.generation !== generation)
            return;
          if (!success)
            _contractFailed = true;
        });
      });
      return;
    }

    var view = Object.assign({}, _view, {takeover: _takeover, contractAck: _contractAck,
      realLaunchFailed: d.realLaunchFailed || prehookPending,
      contractFailed: d.contractFailed, sessionUnlockObserved: d.sessionUnlockObserved});
    var next = Lifecycle.decide(view);
    publish(next.state, next.holder, next.confirmed);
    if (next.confirmed && d.suspendPending) {
      call("consume-suspend", {}, function (reply) {
        if (reply.ok && reply.value.pending)
          suspendReady();
      });
      return;
    }
    if (!next.effect)
      return;
    var action = next.effect;
    if (action.kind === "launch") {
      var command = action.role === "real" ? d.snapshot.command : "qs -c atmosphera-emergency-lock";
      call("launch", {role: action.role, command: command, events: action.events || []}, function (reply) {
        if (!reply.ok && action.role === "real")
          effect("note", {realLaunchFailed: true});
        else
          Qt.callLater(pump);
      });
    } else if (action.kind === "cover-probe-events") {
      effect("cover-probe-events", {events: action.events});
    } else if (action.kind === "probe-race") {
      call("probe-race", {}, function (reply) {
        if (reply.ok && reply.value.retained) {
          _unlockObserved = false;
          if (reply.value.first)
            Logger.w("LockOwner", "emergency probe won race against external unlock");
        }
        Qt.callLater(pump);
      });
    } else if (action.kind === "settle") {
      // Protocol authentication has already completed (or an external holder
      // independently unlocked). Clean only exact owned units and hook work.
      if (d.snapshot.unlockHook && !d.unlockHookStarted) {
        if (!units.unlockhook) {
          effect("launch", {role: "unlockhook", command: "sh -lc " + quoted(d.snapshot.unlockHook) + " unlock-hook unlock"});
          return;
        }
        effect("note", {unlockHookStarted: true});
        return;
      }
      for (var role in units) {
        if (!_view.units[role].gone) {
          // The unlock listener gets its bounded completion window; all other
          // generation-scoped work is cancelled as soon as its purpose ends.
          if (role === "unlockhook" && _view.now < units[role].startedAt + 5)
            return;
          effect("stop", {role: role});
          return;
        }
      }
      effect("settle", {});
    } else if (action.kind === "recover") {
      for (var oldRole in units) {
        if (!_view.units[oldRole].gone) {
          effect("stop", {role: oldRole});
          return;
        }
      }
      effect("recover", {});
    } else {
      effect(action.kind, {role: action.role});
    }
  }

  function publish(state, holder, secure) {
    if (_state !== state || _holder !== holder || _secure !== secure)
      Logger.i("LockOwner", state + " holder=" + holder + " secure=" + secure);
    _state = state;
    _holder = holder;
    if (_secure !== secure) {
      _secure = secure;
      secureChangedForSleep(secure);
    }
  }

  Connections {
    target: Settings
    function onEffectiveSettingsChanged(section) { root._settingsPending = true; }
  }

  Connections {
    target: LockerService
    function onSessionUnlocked() {
      if (_view?.descriptor && _view.descriptor.phase !== "settled")
        _unlockObserved = true;
    }
    function onContractAvailableChanged() {
      if (!LockerService.contractAvailable && _view?.descriptor?.snapshot.adapter === "contract")
        _contractFailed = true;
    }
  }

  Timer {
    interval: root._view?.descriptor && root._view.descriptor.phase !== "settled" ? 100 : 1000
    running: root._initialized
    repeat: true
    onTriggered: root.pump()
  }

  IpcHandler {
    target: "lockOwner"
    function status(): string { return JSON.stringify(root.status); }
  }
}
