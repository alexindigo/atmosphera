pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/LockerLifecycle.js" as Lifecycle
import "../../Helpers/LockerSettingsInput.js" as SettingsInput
import "../../Helpers/OwnedProcess.js" as OwnedProcess
import qs.Commons
import qs.Services.Control
import qs.Services.Locker

// Sole lock-operation actuator. The adapter serializes exact generation/unit
// effects across shell restarts; it never selects a backend or unlocks Wayland.
Singleton {
  id: root

  readonly property string state: _state
  readonly property bool secure: _secure
  readonly property string holder: _holder
  readonly property var status: ({
                                   state: _state,
                                   secure: _secure,
                                   holder: _holder,
                                   descriptor: _view?.descriptor || null,
                                   units: _view?.units || {},
                                   error: _error
                                 })
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
  property string _contractIssued: ""
  property string _contractQueried: ""
  property var _contractQuery: null
  property string _contractRejected: ""
  property var _contractFacts: null
  property bool _unlockObserved: false
  property bool _contractFailed: false
  property bool _settingsPending: false
  property string _settingsGeneration: ""
  property string _sleepWindow: ""
  property int _sleepRevision: 0
  property string _suspendReceipt: ""

  signal suspendReady
  signal secureChangedForSleep(bool confirmed)
  signal sleepConfirmed(string window, bool confirmed, bool opaque)

  function quoted(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
  }

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
    var kind = exclusive || custom !== "" || legacyExternal ? "opaque" : LockerService.contractAvailable ? "contract" : external !== "" ? "opaque" : "bundled";
    var command = exclusive ? "sh -lc " + quoted(handler.command) : custom !== "" ? custom : kind === "bundled" ? "qs -c atmosphera-lockscreen" : external;
    return {
      adapter: kind,
      command: command,
      prehook: handler && !handler.exclusive ? "sh -lc " + quoted(handler.command) : "",
      lockHook: HooksService.listenerCommandFor("screenLock", "screenLock"),
      unlockHook: HooksService.listenerCommandFor("screenUnlock", "screenUnlock"),
      suspendAfterSecure: _pendingSuspend,
      sleepWindow: _pendingSleepWindow === 1,
      reason: _reason
    };
  }

  function call(operation, extra, complete) {
    if (_busy)
      return;
    _busy = true;
    var job = {
      operation: operation,
      session: _session
    };
    if (_view?.descriptor)
      job.generation = _view.descriptor.generation;
    Object.assign(job, extra || {});
    OwnedProcess.run(root, ["python3", adapterPath, "manage"], JSON.stringify(job), function (result) {
      _busy = false;
      var reply;
      try {
        reply = JSON.parse(result.stdout);
      } catch (error) {
        reply = {
          ok: false,
          error: "Locker adapter returned no result: " + result.error
        };
      }
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

  function observeSleepWindow(active, window) {
    _sleepWindow = active ? window || "" : "";
    _sleepRevision++;
    // An independent locker may have authenticated since the last query.
    // Each sleep window needs its own owner-bound confirmation.
    if (active)
      _contractQueried = "";
    _pendingSleepWindow = active ? 1 : 0;
    pump();
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
    var sleepRevision = _sleepRevision;
    call("inspect", {}, function (reply) {
      if (!reply.ok)
        return;
      if (sleepRevision !== _sleepRevision) {
        Qt.callLater(pump);
        return;
      }
      _view = reply.value;
      reconcile();
    });
  }

  function effect(operation, extra) {
    call(operation, extra, function (reply) {
      if (reply.ok)
        Qt.callLater(pump);
    });
  }

  // Persist buffered Locker1 facts before any name-loss failure note: a
  // shipped client's Unlocked precedes its name disappearing on exit.
  function persistContract(d) {
    if (d.snapshot.adapter !== "contract" || d.phase === "unlocking")
      return false;
    if (_contractFacts && _contractFacts.generation === d.generation && _contractFacts.events.length > 0) {
      var fact = _contractFacts;
      call("contract-observe", {
             requestId: fact.requestId,
             owner: fact.owner,
             version: fact.version,
             event: fact.events[0]
           }, function (reply) {
             if (reply.ok || reply.error === "contract owner changed" || reply.error === "stale contract request")
               fact.events.shift();
             if (!reply.ok && reply.error === "contract owner changed")
               _contractFailed = true;
             if (reply.ok)
               Qt.callLater(pump);
           });
      return true;
    }
    if (_contractFacts && _contractFacts.generation === d.generation && _contractFacts.events.length === 0) {
      // This inspect follows every accepted persistence receipt. Only now can
      // a restored query count as reconciled, including Secured + Unlocked.
      if (_contractFacts === _contractQuery) {
        _contractQueried = _contractFacts.key;
        _contractQuery = null;
      }
      _contractFacts = null;
    }
    var observed = LockerService.contractObservations[d.contractRequestId]?.[d.contractOwner];
    if (observed && d.contractOwner && d.contractVersion >= 2) {
      var pending = observed.secured && !d.contractSecured ? "secured" : observed.unlocked && d.contractSecured && !d.contractUnlocked ? "unlocked" : "";
      if (pending !== "" && _contractRejected !== d.contractRequestId + ":" + observed.owner + ":" + pending) {
        var rejected = d.contractRequestId + ":" + observed.owner + ":" + pending;
        call("contract-observe", {
               requestId: d.contractRequestId,
               owner: observed.owner,
               event: pending
             }, function (reply) {
               if (!reply.ok && (reply.error === "contract owner changed" || reply.error === "stale contract request")) {
                 // A different owner's claim is refused once and recorded as a
                 // failure of the accepted request, never retried as evidence.
                 _contractRejected = rejected;
                 if (reply.error === "contract owner changed")
                   _contractFailed = true;
               }
               if (reply.ok)
                 Qt.callLater(pump);
             });
        return true;
      }
    }
    return false;
  }

  // Only the submitted request is consumed. New arrivals during an adapter
  // call remain pending; a refused receipt restores the submitted intent.
  function takeRequest() {
    var request = {
      pending: _pendingRequest,
      suspend: _pendingSuspend,
      reason: _reason
    };
    _pendingRequest = false;
    _pendingSuspend = false;
    return request;
  }

  function restoreRequest(request) {
    if (!_pendingRequest)
      _reason = request.reason;
    _pendingRequest = _pendingRequest || request.pending;
    _pendingSuspend = _pendingSuspend || request.suspend;
  }

  function contractKey(d) {
    return d.generation + ":" + d.contractRequestId + ":" + d.contractOwner + ":" + _sleepRevision;
  }

  function pendingContractUnlock(d) {
    var observed = LockerService.contractObservations[d.contractRequestId]?.[d.contractOwner];
    return d.snapshot.adapter === "contract" && !d.contractUnlocked && ((observed?.secured && observed?.unlocked) || (_contractFacts?.generation === d.generation && _contractFacts.events.indexOf("unlocked") !== -1));
  }

  function lifecycleDecision(d, prehookPending) {
    var view = Object.assign({}, _view, {
                               takeover: _takeover,
                               realLaunchFailed: d.realLaunchFailed || (prehookPending && _view.now >= d.emergencyAt),
                               contractFailed: d.contractFailed || _contractFailed,
                               contractPending: d.snapshot.adapter === "contract" && (_contractFacts !== null || (d.contractOwner && d.contractVersion >= 2 && _contractQueried !== contractKey(d))),
                               sessionUnlockObserved: d.sessionUnlockObserved
                             });
    return Lifecycle.decide(view);
  }

  function reconcile() {
    var d = _view.descriptor;
    if (!d || d.phase === "settled") {
      publish("unlocked", "", false);
      if (_suspendReceipt !== "") {
        _suspendReceipt = "";
        requestLock("lock-and-suspend", true);
        return;
      }
      if (_pendingRequest) {
        var config = snapshot();
        var submitted = takeRequest();
        var sleepWindow = _pendingSleepWindow;
        _pendingSleepWindow = -1;
        _settingsPending = false;
        call("begin", {
               snapshot: config,
               settingsJson: config.adapter === "bundled" ? SettingsInput.capture(Settings.data, Settings.store) : null
             }, function (reply) {
               if (reply.ok) {
                 _contractFacts = null;
                 _contractQuery = null;
                 _contractRejected = "";
                 _unlockObserved = false;
                 _contractFailed = false;
                 _settingsGeneration = reply.value.generation;
                 _view = {
                   descriptor: reply.value,
                   units: {},
                   now: reply.value.requestedAt
                 };
               } else {
                 restoreRequest(submitted);
                 if (_pendingSleepWindow === -1)
                   _pendingSleepWindow = sleepWindow;
                 // The existing pump timer owns retries after adapter errors.
                 return;
               }
               Qt.callLater(pump);
             });
      }
      return;
    }
    // Authentication observations must settle before owner-loss recovery can
    // probe. A transient disk refusal retains this barrier, not a second lock.
    if (pendingContractUnlock(d) && persistContract(d))
      return;
    if (_unlockObserved && !d.sessionUnlockObserved) {
      effect("note", {
               sessionUnlockObserved: true
             });
      return;
    }
    var units = d.units;
    var prehookPending = d.phase !== "unlocking" && d.snapshot.prehook && (!units.prehook || !_view.units.prehook.gone);
    var next = lifecycleDecision(d, prehookPending);
    if (publishDecision(d, next))
      return;
    var urgent = next.effect && !(next.effect.role === "real" && (next.effect.kind === "launch" || next.effect.kind === "grant"));
    // Deadlines, holder recovery and teardown never queue behind settings,
    // hooks, intent receipts, notes or a delayed external-service query.
    if (urgent) {
      applyDecision(d, next);
      return;
    }
    if (_pendingRequest && d.phase !== "unlocking") {
      var request = takeRequest();
      // A request while an external lock is unconfirmed probes once (addendum
      // 07): it may follow an unlock this compositor cannot report.
      call("intent", {
             suspendAfterSecure: request.suspend,
             unconfirmed: _state === "engaged-unconfirmed(external)"
           }, function (reply) {
             if (!reply.ok) {
               restoreRequest(request);
               return;
             }
             if (reply.value.phase === "unlocking" || reply.value.phase === "settled")
               restoreRequest(request);
             Qt.callLater(pump);
           });
      return;
    }
    if (persistContract(d))
      return;
    if ((_unlockObserved && !d.sessionUnlockObserved) || (_contractFailed && !d.contractFailed)) {
      effect("note", {
               sessionUnlockObserved: _unlockObserved,
               contractFailed: _contractFailed
             });
      return;
    }
    if (_pendingSleepWindow !== -1) {
      var sleepActive = _pendingSleepWindow === 1;
      var sleepRevision = _sleepRevision;
      _pendingSleepWindow = -1;
      call("sleep-window", {
             active: sleepActive
           }, function (reply) {
             if (!reply.ok) {
               if (_sleepRevision === sleepRevision && _pendingSleepWindow === -1)
                 _pendingSleepWindow = sleepActive ? 1 : 0;
               return;
             }
             Qt.callLater(pump);
           });
      return;
    }

    if (d.snapshot.adapter === "bundled" && _settingsGeneration !== d.generation) {
      _settingsGeneration = d.generation;
      _settingsPending = true;
    }
    if (_settingsPending && d.snapshot.adapter === "bundled" && d.phase !== "unlocking") {
      _settingsPending = false;
      call("settings", {
             settingsJson: SettingsInput.capture(Settings.data, Settings.store)
           }, function (reply) {
             if (!reply.ok) {
               _settingsPending = true;
               return;
             }
             Qt.callLater(pump);
           });
      return;
    }
    if (d.phase !== "unlocking" && d.snapshot.prehook) {
      if (!units.prehook) {
        effect("launch", {
                 role: "prehook",
                 command: d.snapshot.prehook
               });
        return;
      }
      prehookPending = !_view.units.prehook.gone;
      if (prehookPending && _view.now < d.emergencyAt)
        return;
    }
    if (d.phase !== "unlocking" && !d.lockHookStarted) {
      if (d.snapshot.lockHook && !units.lockhook) {
        effect("launch", {
                 role: "lockhook",
                 command: "sh -lc " + quoted(d.snapshot.lockHook) + " lock-hook lock"
               });
        return;
      }
      effect("note", {
               lockHookStarted: true
             });
      return;
    }
    if (d.snapshot.adapter === "contract" && d.phase !== "unlocking" && !prehookPending) {
      if (!d.contractRequested || (!d.contractOwner && _contractIssued !== d.generation)) {
        // A request persisted by a previous shell without its accepted owner
        // is reissued once; LockRequest is idempotent for a known request ID.
        _contractIssued = d.generation;
        call("note", {
               contractRequested: true
             }, function (reply) {
               if (!reply.ok)
                 return;
               var generation = reply.value.generation;
               var requestId = reply.value.contractRequestId;
               var sleepRevision = _sleepRevision;
               LockerService.requestContract(requestId, function (result) {
                 if (_view?.descriptor?.generation !== generation)
                   return;
                 if (!result.ok) {
                   _contractFailed = true;
                 } else {
                   _contractQueried = generation + ":" + requestId + ":" + result.owner + ":" + sleepRevision;
                   _contractFacts = {
                     generation: generation,
                     requestId: requestId,
                     owner: result.owner,
                     version: result.version,
                     events: ["requested"]
                   };
                 }
                 Qt.callLater(pump);
               });
             });
        return;
      }
      if (d.contractOwner && d.contractVersion >= 2 && _contractQueried !== contractKey(d) && !d.contractFailed && !_contractFailed) {
        // After a shell restart, signals may have been missed. Ask the
        // accepting service about this exact request before trusting state.
        // In-flight and durably reconciled are deliberately different states.
        if (next.state !== "reconciling")
          publish("starting", "", false);
        if (_contractQuery && _contractQuery.key === contractKey(d))
          return;
        var queried = {
          key: contractKey(d),
          generation: d.generation,
          requestId: d.contractRequestId,
          owner: d.contractOwner
        };
        _contractQuery = queried;
        LockerService.queryContract(queried.requestId, function (result) {
          if (_contractQuery !== queried || _view?.descriptor?.generation !== queried.generation)
            return;
          queried.events = !result.ok || result.owner !== queried.owner ? ["failed"] : result.state === "secure" ? ["secured"] : result.state === "unlocked" ? ["secured", "unlocked"] : result.state === "pending" && !d.contractSecured ? [] : ["failed"];
          // A failed bounded query withdraws the reconciliation barrier now;
          // recovery must not wait for a retryable failure-note write.
          if (queried.events.indexOf("failed") !== -1)
            _contractFailed = true;
          _contractFacts = queried;
          Qt.callLater(pump);
        });
        return;
      }
    }

    applyDecision(d, next);
  }

  function applyDecision(d, next) {
    var units = d.units;
    if (!next.effect)
      return;
    applyAction(d, units, next.effect);
  }

  function publishDecision(d, next) {
    publish(next.state, next.holder, next.confirmed);
    if (_sleepWindow !== "")
      sleepConfirmed(_sleepWindow, next.confirmed, d.snapshot.adapter !== "bundled");
    if (_suspendReceipt !== "" && next.confirmed) {
      if (_suspendReceipt !== d.generation) {
        _suspendReceipt = "";
        requestLock("lock-and-suspend", true);
      } else {
        // This reconciliation follows the consume receipt. Authentication or
        // owner loss observed in between therefore cannot use the old permit.
        _suspendReceipt = "";
        suspendReady();
      }
      return true;
    }
    if (next.confirmed && d.suspendPending) {
      var generation = d.generation;
      call("consume-suspend", {}, function (reply) {
        if (reply.ok && reply.value.pending)
          _suspendReceipt = generation;
        Qt.callLater(pump);
      });
      return true;
    }
    return false;
  }

  function applyAction(d, units, action) {
    if (action.kind === "launch") {
      var command = action.role === "real" ? d.snapshot.command : "qs -c atmosphera-emergency-lock";
      call("launch", {
             role: action.role,
             command: command,
             events: action.events || []
           }, function (reply) {
             if (!reply.ok && action.role === "real")
               effect("note", {
                        realLaunchFailed: true
                      });
             else if (reply.ok)
               Qt.callLater(pump);
           });
    } else if (action.kind === "note-unlock") {
      effect("note", {
               sessionUnlockObserved: true
             });
    } else if (action.kind === "cover-probe-events") {
      effect("cover-probe-events", {
               events: action.events
             });
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
          effect("launch", {
                   role: "unlockhook",
                   command: "sh -lc " + quoted(d.snapshot.unlockHook) + " unlock-hook unlock"
                 });
          return;
        }
        effect("note", {
                 unlockHookStarted: true
               });
        return;
      }
      for (var role in units) {
        if (!_view.units[role].gone) {
          // The unlock listener gets its bounded completion window; all other
          // generation-scoped work is cancelled as soon as its purpose ends.
          if (role === "unlockhook" && _view.now < units[role].startedAt + 5)
            return;
          effect("stop", {
                   role: role
                 });
          return;
        }
      }
      effect("settle", {});
    } else if (action.kind === "recover") {
      for (var oldRole in units) {
        if (!_view.units[oldRole].gone) {
          effect("stop", {
                   role: oldRole
                 });
          return;
        }
      }
      effect("recover", {});
    } else {
      effect(action.kind, {
               role: action.role
             });
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
    function onEffectiveSettingsChanged(section) {
      root._settingsPending = true;
    }
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
    function onContractOwnerChanged() {
      var d = _view?.descriptor;
      var accepted = d?.contractOwner || _contractFacts?.owner;
      if (d?.snapshot.adapter === "contract" && d.phase !== "settled" && accepted && LockerService.contractOwner !== accepted) {
        _contractFailed = true;
        publish(_state, _holder, false);
        Qt.callLater(pump);
      }
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
    function status(): string {
      return JSON.stringify(root.status);
    }
  }
}
