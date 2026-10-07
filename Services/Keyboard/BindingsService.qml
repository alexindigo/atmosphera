pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import "../../Helpers/OwnedProcess.js" as OwnedProcess

// One FIFO owner. Request identity is not a supersession generation; every
// choice runs, and a failed head remains ahead of all subsequently queued work.
Singleton {
  id: root

  property string _state: "WaitingStartup"
  property string _error: ""
  property string _latestChoice: "none"
  property string _phase: ""
  property int _serial: 0
  property int _revision: 0
  property var _queue: []
  property var _records: ({})
  property var _startupRunner: null
  property string _startupId: ""
  property var _startupObservers: []
  property bool _initialized: false
  property bool _notifying: false
  property var _deferredStart: null

  readonly property string state: root._state
  readonly property bool isApplying: root._state === "Running"
  readonly property string lastError: root._error
  readonly property string requestedEnvironment: root._latestChoice
  readonly property int queueCount: { void root._revision; return root._queue.length; }
  readonly property string headEnvironment: { void root._revision; return root._queue.length ? root._queue[0].environment : ""; }
  readonly property string headRequestId: { void root._revision; return root._queue.length ? root._queue[0].id : ""; }
  readonly property var status: {
    void root._revision;
    return { "state": root._state, "queueCount": root._queue.length,
      "waitingCount": Math.max(0, root._queue.length - 1), "headRequestId": root.headRequestId,
      "headEnvironment": root.headEnvironment, "requestedEnvironment": root._latestChoice,
      "stage": root._phase, "error": root._error };
  }

  signal requestFinished(string requestId, int attemptId, string environment, bool success, string error)
  signal stageChanged(string requestId, int attemptId, string stage, string environment)

  function _changed() {
    root._revision++;
    Settings.setBindingsUnresolved(root._queue.length > 0 || !root._initialized);
  }

  function _record(environment, callback, options, kind) {
    var id = "bindings-" + (++root._serial);
    var record = { "id": id, "environment": String(environment), "kind": kind || "environment",
      "context": options && options.context ? String(options.context) : "",
      "work": options && options.work ? JSON.parse(JSON.stringify(options.work)) : null,
      "prepare": options && typeof options.prepare === "function" ? options.prepare : null,
      "attemptId": 0, "status": "Waiting", "error": "", "callback": callback,
      "attemptEnded": false, "handoff": "" };
    root._records[id] = record;
    return record;
  }

  function init(startupRunner, onComplete) {
    if (root._initialized)
      return;
    root._initialized = true;
    root._startupRunner = startupRunner;
    Settings.beginManagedBindings();
    var environment = Settings.data.bindings.environment || "none";
    if (root._serial === 0)
      root._latestChoice = environment;
    var startup = root._record(environment, onComplete, null, "startup");
    root._startupId = startup.id;
    root._queue.unshift(startup);
    root._state = "Idle";
    root._changed();
    root._pump();
  }

  function observeStartup(complete) {
    var startup = root._records[root._startupId];
    if (!startup || (startup.status !== "Succeeded" && startup.status !== "Stopped")) {
      root._startupObservers.push(complete);
      return;
    }
    root._notify(complete, startup.status === "Succeeded", startup.error, startup, startup.attemptId);
  }

  function requestEnvironment(environment, onComplete, options) {
    var record = root._record(environment, onComplete, options);
    root._latestChoice = record.environment;
    root._queue.push(record);
    root._changed();
    root._pump();
    return record.id;
  }

  function applyCurrentEnvironment(onComplete) {
    return root.requestEnvironment(Settings.data.bindings.environment || "none", onComplete);
  }

  function requestStatus(identity) {
    void root._revision;
    var record = root._records[identity];
    return record ? { "id": record.id, "environment": record.environment, "context": record.context,
      "work": record.work ? JSON.parse(JSON.stringify(record.work)) : null,
      "status": record.status, "attemptId": record.attemptId, "error": record.error,
      "handoff": record.handoff } : null;
  }

  function latestRequestForContext(context) {
    var identity = "";
    for (var id in root._records) {
      if (root._records[id].context === context)
        identity = id;
    }
    return identity;
  }

  function _notify(callback, success, error, record, attempt) {
    if (typeof callback !== "function")
      return;
    try { callback(success, error, record.id, attempt); }
    catch (exception) { Logger.e("Bindings", "Completion callback failed for request", record.id); }
  }

  function retryHead(onComplete) {
    if (root._state !== "Stopped" || root._queue.length === 0) {
      if (typeof onComplete === "function") {
        try { onComplete(false, "No stopped head is available for Retry", "", 0); }
        catch (exception) { Logger.e("Bindings", "Rejected Retry callback failed"); }
      }
      return "";
    }
    var record = root._queue[0];
    record.callback = onComplete;
    record.status = "Waiting";
    record.error = "";
    root._error = "";
    root._state = "Idle";
    root._changed();
    root._pump();
    return record.id;
  }

  function _pump() {
    if (!root._initialized || root._notifying || root._state !== "Idle" || root._queue.length === 0)
      return;
    var record = root._queue[0];
    record.attemptId++;
    record.attemptEnded = false;
    record.status = "Running";
    root._state = "Running";
    root._changed();
    var attempt = record.attemptId;
    if (record.kind === "startup") {
      root._stage(record, attempt, "startup");
      try {
        if (typeof root._startupRunner !== "function") {
          root._settle(record, attempt, false, "Startup owner unavailable");
          return;
        }
        root._startupRunner(record.environment, function (success, error) {
          root._settle(record, attempt, success, error || "");
        });
      } catch (exception) {
        root._settle(record, attempt, false, "Startup operation failed");
      }
      return;
    }
    if (record.environment !== "macos" && record.environment !== "none") {
      root._settle(record, attempt, false, "Unsupported bindings environment");
      return;
    }
    if (record.prepare) {
      root._stage(record, attempt, "setup-save");
      var prepared = false;
      try {
        record.prepare(record.work, function (success, error) {
          if (prepared || !root._current(record, attempt))
            return;
          prepared = true;
          if (success) root._save(record, attempt);
          else root._settle(record, attempt, false, error || "Captured setup save failed");
        }, record.id);
      } catch (exception) {
        root._settle(record, attempt, false, "Captured setup preparation failed");
      }
    } else {
      root._save(record, attempt);
    }
  }

  function _current(record, attempt) {
    return root._state === "Running" && root._queue[0] === record
        && record.attemptId === attempt && !record.attemptEnded;
  }

  function _stage(record, attempt, phase) {
    root._phase = phase;
    root._changed();
    root.stageChanged(record.id, attempt, phase, record.environment);
  }

  function _save(record, attempt) {
    if (!root._current(record, attempt))
      return;
    root._stage(record, attempt, "save");
    try {
      Settings.saveBindingsEnvironment(record.environment, function (success, error) {
        if (!root._current(record, attempt)) return;
        if (!success) root._settle(record, attempt, false, error);
        else root._deploy(record, attempt);
      }, record.id);
    } catch (exception) {
      root._settle(record, attempt, false, "Managed bindings save failed");
    }
  }

  function _deploy(record, attempt) {
    root._stage(record, attempt, "deploy");
    try {
      OwnedProcess.run(root, ["env", "ATMOSPHERA_SETTINGS_FILE=" + Settings.settingsFile,
        "ATMOSPHERA_SHELL_DIR=" + Quickshell.shellDir, Quickshell.shellDir + "/Scripts/bash/atmosphera",
        "bindings", "apply", "--environment", record.environment], null, function (result) {
        if (!root._current(record, attempt)) return;
        if (!result.success) {
          root._settle(record, attempt, false, "Bindings deployment failed: " + result.error);
          return;
        }
        root._stage(record, attempt, "generate-handoff");
        try {
          NiriSessionInit.regenerate(record.environment, function (success, error, applicable) {
            if (!root._current(record, attempt)) return;
            record.handoff = success ? (applicable === false ? "NotApplicable" : "Accepted") : "Unknown";
            root._settle(record, attempt, success, error || "");
          });
        } catch (exception) {
          root._settle(record, attempt, false, "Session generation/handoff failed");
        }
      });
    } catch (exception) {
      root._settle(record, attempt, false, "Deployment child failed");
    }
  }

  function _settle(record, attempt, success, error) {
    if (!root._current(record, attempt))
      return;
    var terminal = { "id": record.id, "attemptId": attempt, "environment": record.environment,
      "success": success === true, "error": success ? "" : (error || "Bindings request failed") };
    // Property/status listeners can explicitly Retry before requestFinished.
    // Guard pumping before any observable settlement and detach the old tuple.
    root._notifying = true;
    try {
    record.attemptEnded = true;
    var callback = record.callback;
    record.callback = null;
    var startupCallbacks = record.kind === "startup" ? root._startupObservers.slice() : [];
    if (record.kind === "startup") root._startupObservers = [];
    record.error = terminal.error;
    record.status = success ? "Succeeded" : "Stopped";
    if (success) {
      root._queue.shift();
      root._state = "Idle";
      root._error = "";
      if (record.kind !== "startup") {
        Logger.i("Bindings", record.handoff === "Accepted" ? "Saved/deployed; niri accepted handoff:" : "Saved/deployed; niri handoff not applicable:", record.id, record.environment);
      }
    } else {
      root._error = terminal.error;
      root._state = "Stopped";
      Logger.e("Bindings", "Queue stopped at request", terminal.id, terminal.error);
      ToastService.showError("Bindings queue stopped", terminal.error);
    }
    root._phase = success ? "" : root._phase;
    root._changed();
      root.requestFinished(terminal.id, terminal.attemptId, terminal.environment, terminal.success, terminal.error);
      root._notify(callback, terminal.success, terminal.error, terminal, terminal.attemptId);
      for (var si = 0; si < startupCallbacks.length; si++)
        root._notify(startupCallbacks[si], terminal.success, terminal.error, terminal, terminal.attemptId);
    } finally {
      root._notifying = false;
    }
    root._pump(); // Stopped is never advanced by this path.
  }

  Connections {
    target: Settings
    function onBindingsEnvironmentRequested(environment) {
      root.requestEnvironment(environment);
    }
  }
}
