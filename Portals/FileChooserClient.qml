pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML
import QtQuick
import Quickshell
import "../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons

Singleton {
  id: root
  property string _uniqueName: ""
  property bool _identifying: false
  property int _serial: 0
  property var _operations: []
  readonly property string _frontend: "org.freedesktop.portal.Desktop"
  readonly property string _desktopPath: "/org/freedesktop/portal/desktop"

  function init() { Logger.i("FileChooserClient", "Service started"); }

  function urisToPaths(uris) {
    if (!uris || !uris.length)
      return null;
    var paths = [];
    for (var uri of uris) {
      var converted = PortalPaths.uriToPath(uri);
      if (!converted.ok) {
        Logger.w("FileChooserClient", "Portal returned an unusable URI: " + converted.error);
        return null;
      }
      paths.push(converted.path);
    }
    return paths;
  }

  function busCall(member, signature, args, resolve, reject) {
    SessionBus.asyncCall(new DBusQML.dbusMessage({service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus", iface: "org.freedesktop.DBus", member: member, signature: signature, arguments: args, timeout: 5000}), resolve, reject);
  }

  function identify() {
    if (_identifying || _uniqueName)
      return;
    _identifying = true;
    // The connection API has no unique-name accessor. Briefly claim a private
    // name on this same connection, ask its owner, then release the claim.
    var name = "app.atmosphera.FileChooserClient.p" + Date.now() + "r" + Math.floor(Math.random() * 1000000000);
    var fail = error => {
      Logger.w("FileChooserClient", "Cannot identify portal connection: " + error.message);
      _identifying = false;
      cancelAll();
    };
    busCall("RequestName", "su", [name, 4], result => {
      if (result !== 1) { fail({message: "Private name unavailable"}); return; }
      busCall("GetNameOwner", "s", [name], owner => {
        busCall("ReleaseName", "s", [name], () => {}, () => {});
        _uniqueName = String(owner);
        _identifying = false;
        for (var operation of _operations.slice()) operation.start();
      }, error => { busCall("ReleaseName", "s", [name], () => {}, () => {}); fail(error); });
    }, fail);
  }

  function openPicker(options, onAccepted, onCancelled) {
    var operation = operationFactory.createObject(root, {options: options || {}, acceptedCallback: onAccepted, cancelledCallback: onCancelled, token: "atmosphera_" + Date.now() + "_" + (++_serial)});
    _operations = _operations.concat([operation]);
    Qt.callLater(() => { if (!_operations.includes(operation)) return; if (_uniqueName) operation.start(); else identify(); });
    return operation;
  }

  function cancelAll() {
    for (var operation of _operations.slice()) operation.cancel();
  }

  DBusServiceWatcher {
    connection: SessionBus
    service: root._frontend
    onOwnerChanged: (oldOwner, newOwner) => { if (oldOwner && oldOwner !== newOwner) root.cancelAll(); }
  }
  Connections {
    target: SessionBus
    function onDisconnected() { root._uniqueName = ""; root.cancelAll(); }
  }

  Component {
    id: operationFactory
    Scope {
      id: operation
      required property var options
      required property var acceptedCallback
      required property var cancelledCallback
      required property string token
      property string handle: ""
      property bool settled: false
      property bool called: false

      function settle(paths) {
        if (settled) return;
        settled = true;
        var callback = paths !== null ? acceptedCallback : cancelledCallback;
        root._operations = root._operations.filter(item => item !== operation);
        if (callback) {
          if (paths !== null) callback(paths); else callback();
        }
        // Keep a cancelled in-flight operation alive until its method reply,
        // so it can Close the returned handle even if it differs.
        if (!called) destroy();
      }

      function closeHandle(path) {
        if (path)
          SessionBus.send(new DBusQML.dbusMessage({service: root._frontend, path: path, iface: "org.freedesktop.portal.Request", member: "Close", signature: "", arguments: [], autoStart: false}));
      }
      function cancel() { closeHandle(handle); settle(null); }
      function dispose() { acceptedCallback = null; cancelledCallback = null; cancel(); }

      function start() {
        if (settled || handle) return;
        handle = root._desktopPath + "/request/" + root._uniqueName.slice(1).replace(/\./g, "_") + "/" + token;
        // The watcher is enabled first; a bus round-trip orders its match rule
        // before OpenFile, including a response sent before the method reply.
        Qt.callLater(() => { if (root._operations.includes(operation)) root.busCall("GetId", "", [], () => { if (root._operations.includes(operation)) operation.call(); }, () => { if (root._operations.includes(operation)) operation.cancel(); }); });
      }

      function call() {
        if (settled) return;
        var opts = {handle_token: token};
        if (options.directory) opts.directory = true;
        if (options.multiple) opts.multiple = true;
        if (options.filters && options.filters.length)
          opts.filters = new DBusQML.variant(options.filters.map(pattern => [pattern, [[0, pattern]]]), "a(sa(us))");
        if (options.initialPath) {
          var encoded = PortalPaths.encodeBytePath(options.initialPath);
          if (!encoded.ok) { cancel(); return; }
          opts.current_folder = new DBusQML.variant(encoded.bytes, "ay");
        }
        called = true;
        // Type each variant payload once, letting the map supply its wrapper.
        // Forcing an outer signature would wrap typed dict values again.
        SessionBus.asyncCall(new DBusQML.dbusMessage({service: root._frontend, path: root._desktopPath, iface: "org.freedesktop.portal.FileChooser", member: "OpenFile", arguments: ["", options.title || "", opts], timeout: 30000}), returned => {
          called = false;
          var path = String(returned);
          if (settled) { closeHandle(path); destroy(); }
          else if (path !== handle) { closeHandle(path); settle(null); }
        }, error => {
          called = false;
          Logger.w("FileChooserClient", "OpenFile failed: " + error.message);
          if (settled) destroy(); else settle(null);
        });
      }

      DBusSignalWatcher {
        connection: SessionBus
        service: root._frontend
        path: operation.handle
        iface: "org.freedesktop.portal.Request"
        member: "Response"
        enabled: operation.handle !== "" && !operation.settled
        onReceived: (member, args) => operation.settle(args[0] === 0 && args[1] ? root.urisToPaths(args[1].uris) : null)
      }
    }
  }
}
