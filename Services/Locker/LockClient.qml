import QtQuick
import Quickshell
import Quickshell.Io
import DBus 1.0
import "../../Helpers/OwnedProcess.js" as OwnedProcess

// Process-local protocol lifetime, shared by the full and emergency lockers.
// Cancelling a client is never an unlock. Only this client's successful PAM
// completion is allowed to clear the Wayland lock request. A standalone client
// also serves app.atmosphera.Locker1 v2 (docs/locker1-contract.md) when that
// name is free; managed clients never claim it and nobody's name is replaced.
Scope {
  id: root
  required property var endpoint
  required property var auth
  required property bool prepared
  readonly property string session: Quickshell.env("ATMOSPHERA_LOCK_SESSION")
  readonly property string generation: Quickshell.env("ATMOSPHERA_LOCK_GENERATION")
  readonly property string role: Quickshell.env("ATMOSPHERA_LOCK_ROLE") || "real"
  readonly property string adapter: Quickshell.env("ATMOSPHERA_LOCK_ADAPTER")
  readonly property bool terminal: _terminal
  readonly property bool requested: _requested
  property bool _terminal: false
  property bool _requested: false
  property bool _authenticated: false
  property bool _retiring: false
  property bool _granted: false
  property bool _syncPending: false
  property bool _syncDirty: false
  property bool _authPending: false
  property string _settlement: ""
  property var _reportInfo: null
  property int _reportSequence: 0
  property bool _reportEverSecure: false
  property bool _reportSaved: false
  property bool _unlockCommitted: false
  readonly property string reportHelper: adapter || Quickshell.shellDir + "/Scripts/python/locker-unit.py"
  readonly property string nativeEvent: _nativeEvent
  property string _nativeEvent: ""

  property var _contractRequests: ({})
  property bool _contractOwned: false
  property bool _contractNotified: false

  signal settled(string reason)
  signal changed
  signal nativeReported(string event)

  function contractError(name, message) {
    return {dbusError: true, name: "app.atmosphera.Locker1.Error." + name, message: message};
  }

  function contractState(requestId) {
    return _contractRequests[requestId] || "unknown";
  }

  // Lock() and LockRequest(id) join this process's own lock; it is already
  // acquiring for itself, so there is nothing else to start.
  function contractRequest(requestId) {
    if (requestId !== null && !/^[A-Za-z0-9._:-]{1,128}$/.test(requestId))
      throw contractError("InvalidRequest", "request ID must be 1-128 characters of [A-Za-z0-9._:-]");
    if (_terminal || _retiring || _authenticated)
      throw contractError("Ended", "this lock is ending; start a new locker");
    if (requestId === null || requestId in _contractRequests)
      return;
    var next = Object.assign({}, _contractRequests);
    next[requestId] = endpoint.secure ? "secure" : "pending";
    _contractRequests = next;
    if (next[requestId] === "secure")
      Qt.callLater(function () { root.emitContract("secured", requestId); });
  }

  function emitContract(kind, requestId) {
    if (!_contractOwned || !contractEndpoint.item)
      return;
    _contractNotified = true;
    if (kind === "secured")
      contractEndpoint.item.adaptor.secured(requestId);
    else
      contractEndpoint.item.adaptor.unlocked(requestId);
  }

  // Native outcomes only: locked from the compositor, unlocked after this
  // client's own successful PAM and protocol unlock request.
  function notifyContract(event) {
    var next = Object.assign({}, _contractRequests);
    var emitted = [];
    for (var requestId in next) {
      var state = next[requestId];
      if (event === "locked" && state === "pending") {
        next[requestId] = "secure";
        emitted.push(["secured", requestId]);
      } else if (event === "authenticated-unlock" && state === "secure") {
        next[requestId] = "unlocked";
        emitted.push(["unlocked", requestId]);
      } else if (event === "finished" && (state === "pending" || state === "secure")) {
        next[requestId] = "failed";
      }
    }
    _contractRequests = next;
    for (var i = 0; i < emitted.length; i++)
      emitContract(emitted[i][0], emitted[i][1]);
  }

  function quitStandalone() {
    // No owner reads a standalone report; retire it with the process. A bus
    // round trip after the last signal proves the daemon received it before
    // this connection closes. The timer bounds both steps.
    contractFlushLimit.running = true;
    var path = _reportInfo ? nativeReport.path : "";
    OwnedProcess.run(root, ["python3", reportHelper, "retire-report", path], "", function () {
      if (!_contractNotified || !contractEndpoint.item) {
        Qt.quit();
        return;
      }
      var reply = contractEndpoint.item.flush.call("GetId", []);
      if (!reply) {
        Qt.quit();
        return;
      }
      reply.finished.connect(function () { Qt.quit(); });
      if (reply.isFinished)
        Qt.quit();
    });
  }

  function configureReport(info) {
    if (_reportInfo || !info || !info.path || !info.token || !info.identity)
      return;
    nativeReport.path = info.path;
    _reportInfo = info;
  }

  function prepareStandaloneReport() {
    OwnedProcess.run(root, ["python3", reportHelper, "prepare-report"], "", function (result) {
      var reply;
      try { reply = JSON.parse(result.stdout); }
      catch (error) { reply = {ok: false}; }
      if (!reply.ok) {
        finish("report-unavailable");
        return;
      }
      configureReport(reply.value);
      if (prepared)
        acquire(session, generation);
    });
  }

  function reportNative(event) {
    if (!_reportInfo)
      return false;
    if (event === "locked")
      _reportEverSecure = true;
    var report = Object.assign({}, _reportInfo, {event: event, sequence: ++_reportSequence,
      everSecure: _reportEverSecure});
    delete report.path;
    _reportSaved = false;
    nativeReport.setText(JSON.stringify(report));
    if (_reportSaved) {
      _nativeEvent = event;
      nativeReported(event);
    }
    return _reportSaved;
  }

  function observeNative() {
    // Quickshell forwards this signal before deleting native lock surfaces.
    // Complete the atomic synchronous report before returning to that stack.
    var event = endpoint.secure ? "locked" : _requested ? (_unlockCommitted ? "authenticated-unlock" : "finished") : "";
    if (event !== "") {
      reportNative(event);
      notifyContract(event);
    }
    observe();
  }

  FileView {
    id: nativeReport
    preload: false
    blockWrites: true
    atomicWrites: true
    onSaved: root._reportSaved = true
  }

  function matches(sessionId, token) {
    return sessionId === session && token === generation && !_terminal && !_retiring;
  }

  function acquire(sessionId, token) {
    if (!matches(sessionId, token) || !prepared || !_reportInfo || _authenticated || (adapter !== "" && !_granted))
      return false;
    if (_requested)
      return endpoint.locked;
    _requested = true;
    endpoint.locked = true;
    changed();
    // Refusal can already have settled locked=false before a connection runs.
    Qt.callLater(evaluate);
    return true;
  }

  function finish(reason) {
    if (_terminal)
      return;
    _terminal = true;
    _settlement = reason;
    auth.retire();
    settled(reason);
    changed();
    // No endpoint mutation: secure cancellation/handover is fail-closed.
    if (adapter === "")
      Qt.callLater(quitStandalone);
  }

  function retire(sessionId, token) {
    if (!matches(sessionId, token) || _authenticated)
      return false;
    _retiring = true;
    finish("retired");
    return true;
  }

  function evaluate() {
    if (_terminal || !_requested)
      return;
    changed();
    if (!endpoint.locked)
      finish(_authenticated ? "authenticated-unlock" : "finished");
  }

  function observe() {
    changed();
    // In 0.3.2, finished emits secureStateChanged before native teardown
    // clears locked. A lockStateChanged notification is not guaranteed for
    // that final value. Inspect after the native signal stack unwinds.
    Qt.callLater(evaluate);
  }

  function authenticate() {
    if (_terminal || _retiring || _authenticated || !endpoint.secure || !endpoint.locked)
      return;
    _authenticated = true;
    // Authentication and retirement are serialized on this QML event loop.
    // Once retirement wins, a queued PAM success is ignored, not transferred.
    auth.retire();
    changed();
    if (adapter !== "")
      fenceAuthentication();
    else
      completeAuthentication();
  }

  function completeAuthentication() {
    if (!_authenticated || _terminal || _retiring)
      return;
    if (endpoint.secure && endpoint.locked) {
      _unlockCommitted = true;
      endpoint.locked = false;
    }
    evaluate();
  }

  function callAdapter(operation, extra, complete) {
    var job = {operation: operation, session: session, generation: generation,
      role: role, pid: Quickshell.processId};
    Object.assign(job, extra || {});
    OwnedProcess.run(root, ["python3", adapter, "manage"], JSON.stringify(job), function (result) {
      var reply;
      try { reply = JSON.parse(result.stdout); }
      catch (error) { reply = {ok: false, error: "Locker adapter did not return a result"}; }
      complete(reply);
    });
  }

  function fenceAuthentication() {
    if (_authPending || !_authenticated || _terminal || _retiring)
      return;
    _authPending = true;
    callAdapter("authenticated", {}, function (reply) {
      _authPending = false;
      if (_terminal || _retiring)
        return;
      if (reply.ok && reply.value.unlock)
        completeAuthentication();
      else if (reply.ok && reply.value.retire)
        finish("authentication-revoked");
      // A failed stop/identity barrier never authorizes unlock. The timer
      // retries the same private successful-PAM transaction, not PAM itself.
    });
  }

  function synchronize() {
    if (adapter === "")
      return;
    _syncDirty = true;
    if (_syncPending)
      return;
    _syncDirty = false;
    _syncPending = true;
    var snapshot = JSON.parse(status());
    callAdapter("client", {status: snapshot}, function (reply) {
      _syncPending = false;
      if (snapshot.terminal) {
        Qt.quit();
        return;
      }
      if (reply.ok && reply.value.generation === generation) {
        configureReport(reply.value.report);
        _granted = reply.value.grant;
        if (reply.value.retire)
          retire(session, generation);
        else if (reply.value.externalUnlocked && !_requested)
          finish("retired");
        else if (_granted && prepared && !_requested)
          acquire(session, generation);
      } else if (reply.error === "stale locker generation") {
        finish("stale-generation");
      }
      if (_syncDirty)
        Qt.callLater(synchronize);
    });
  }

  function status() {
    return JSON.stringify({session: session, generation: generation, role: role,
      ready: prepared, requested: _requested, locked: endpoint.locked,
      secure: endpoint.secure, terminal: _terminal,
      authenticated: _authenticated, retiring: _retiring, settlement: _settlement});
  }

  onChanged: synchronize()

  Timer {
    interval: root.endpoint.secure ? 500 : 100
    running: root.adapter !== "" && !root.terminal
    repeat: true
    onTriggered: {
      root.synchronize();
      if (root._authenticated)
        root.fenceAuthentication();
    }
  }

  Connections {
    target: root.endpoint
    function onLockStateChanged() { root.observe(); }
    function onSecureStateChanged() { root.observeNative(); }
  }
  Connections {
    target: root.auth
    function onUnlocked() { root.authenticate(); }
  }

  onPreparedChanged: {
    changed();
    if (prepared && generation === "" && _reportInfo)
      acquire(session, generation);
  }
  Component.onCompleted: {
    if (adapter === "")
      prepareStandaloneReport();
    synchronize();
  }

  Loader {
    id: contractEndpoint
    active: root.adapter === ""
    sourceComponent: Scope {
      property alias adaptor: contractAdaptor
      property alias flush: contractFlush

      DBusAdaptor {
        id: contractAdaptor
        // Unflagged claim: never queued, never replacing an independent owner.
        service: "app.atmosphera.Locker"
        path: "/app/atmosphera/Locker"
        iface: "app.atmosphera.Locker1"
        connection: SessionBus

        readonly property int version: 2

        // dbusqml relays QML signals through a QVariant slot; typed string
        // parameters would not connect. The value is still sent as "s".
        signal secured(var requestId)
        signal unlocked(var requestId)

        function lock() {
          root.contractRequest(null);
        }
        function lockRequest(requestId: string) {
          root.contractRequest(requestId);
        }
        function requestState(requestId: string): string {
          return root.contractState(requestId);
        }

        onNameAcquired: root._contractOwned = true
        onNameLost: root._contractOwned = false
      }

      DBus {
        id: contractFlush
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"
        connection: SessionBus
        propertiesEnabled: false
        signalsEnabled: false
      }
    }
  }

  Timer {
    id: contractFlushLimit
    interval: 2000
    onTriggered: Qt.quit()
  }

  IpcHandler {
    target: "locker"
    function status(): string { return root.status(); }
    function acquire(session: string, generation: string): bool { return root.acquire(session, generation); }
    function retire(session: string, generation: string): bool { return root.retire(session, generation); }
  }
}
