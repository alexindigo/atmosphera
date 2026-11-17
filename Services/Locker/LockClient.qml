import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/OwnedProcess.js" as OwnedProcess

// Process-local protocol lifetime, shared by the full and emergency lockers.
// Cancelling a client is never an unlock. Only this client's successful PAM
// completion is allowed to clear the Wayland lock request.
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

  signal settled(string reason)
  signal changed
  signal nativeReported(string event)

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
    if (endpoint.secure)
      reportNative("locked");
    else if (_requested)
      reportNative(_unlockCommitted ? "authenticated-unlock" : "finished");
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
      Qt.callLater(function () { Qt.quit(); });
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

  IpcHandler {
    target: "locker"
    function status(): string { return root.status(); }
    function acquire(session: string, generation: string): bool { return root.acquire(session, generation); }
    function retire(session: string, generation: string): bool { return root.retire(session, generation); }
  }
}
