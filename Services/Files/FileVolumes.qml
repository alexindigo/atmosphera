pragma Singleton

import DBus 1.0
import QtQuick
import QtQml.Models
import Quickshell
import qs.Commons
import "../../Helpers/PortalPaths.js" as Paths

// UDisks is the authority for discovery and mount state. No /run/media scan,
// shell command, optimistic mount point or privileged application process.
Singleton {
  id: root
  readonly property var volumes: _volumes
  readonly property bool available: manager.serviceAvailable
  readonly property bool busy: _busy !== ""
  readonly property string busyId: _busy
  property string errorText: ""
  property var _volumes: []
  property var _objects: ({})
  property var _watched: []
  property string _busy: ""
  property bool _reading: false
  property bool _again: false
  signal mounted(string id, string path)
  readonly property string _prefix: "org.freedesktop.UDisks2."
  function scheduleRefresh() { changes.restart(); }

  function _path(bytes) {
    var value = Paths.decodeBytePath(bytes);
    return value.ok ? value.path : "";
  }
  function _publish(objects) {
    _objects = objects;
    var rows = [];
    for (var id of Object.keys(objects)) {
      var object = objects[id], block = object[_prefix + "Block"], fs = object[_prefix + "Filesystem"];
      if (!block || !fs || block.HintIgnore) continue;
      var drive = (objects[block.Drive] || {})[_prefix + "Drive"] || {};
      var loop = object[_prefix + "Loop"] !== undefined;
      var mounts = Array.from(fs.MountPoints || []).map(_path).filter(path => path !== "");
      if (mounts.some(path => ["/", "/boot", "/boot/efi", "/efi"].includes(path))) continue;
      rows.push({id: id, name: block.IdLabel || drive.Model || _path(block.PreferredDevice) || id.split("/").pop(),
        path: mounts[0] || "", mounts: mounts, drive: block.Drive || "", mounted: mounts.length > 0,
        ejectable: loop || drive.Ejectable === true || drive.CanPowerOff === true, loop: loop,
        powerOff: !drive.Ejectable && drive.CanPowerOff === true, kind: "volume"});
    }
    _volumes = rows.sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
    var ids = Object.keys(objects).sort();
    if (JSON.stringify(ids) !== JSON.stringify(_watched)) _watched = ids;
  }
  function refresh() {
    if (!available) return;
    if (_reading) { _again = true; return; }
    _reading = true;
    var reply = manager.call("GetManagedObjects", []);
    if (!reply) { _reading = false; return; }
    reply.finished.connect(function() {
      _reading = false;
      if (!reply.isError && available) _publish(reply.value || {});
      if (_again) { _again = false; Qt.callLater(refresh); }
    });
  }
  function _error(message) {
    errorText = I18n.tr("widgets.file-picker.volume-error") + (message ? " " + message : "");
    _busy = "";
    refresh();
  }
  function _call(path, iface, method, done) {
    var proxy = actionFactory.createObject(root, {path: path, iface: _prefix + iface});
    var reply = proxy.call(method, [{}]);
    if (!reply) { proxy.destroy(); _error(""); return; }
    reply.finished.connect(function() {
      if (reply.isError) _error(reply.error.message);
      else done(reply.value);
      proxy.destroy();
    });
  }
  function _begin(id) {
    if (busy || !available) return null;
    var volume = volumes.find(row => row.id === id);
    if (!volume) return null;
    errorText = ""; _busy = id;
    return volume;
  }
  function mount(id) {
    var row = _begin(id);
    if (!row) return;
    if (row.mounted) { _busy = ""; mounted(id, row.path); return; }
    _call(id, "Filesystem", "Mount", function(path) {
      _busy = ""; refresh();
      if (typeof path === "string" && path.startsWith("/")) mounted(id, path);
      else _error("");
    });
  }
  function unmount(id) {
    var row = _begin(id);
    if (!row) return;
    if (!row.mounted) { _busy = ""; return; }
    _call(id, "Filesystem", "Unmount", function() { _busy = ""; refresh(); });
  }
  function eject(id) {
    var row = _begin(id);
    if (!row) return;
    if (!row.ejectable) { _busy = ""; return; }
    var mounted = volumes.filter(v => (row.loop ? v.id === row.id : v.drive === row.drive) && v.mounted);
    function next() {
      if (mounted.length) _call(mounted.shift().id, "Filesystem", "Unmount", next);
      else _call(row.loop ? row.id : row.drive, row.loop ? "Loop" : "Drive", row.loop ? "Delete" : row.powerOff ? "PowerOff" : "Eject", function() { _busy = ""; refresh(); });
    }
    next();
  }
  DBus {
    id: manager
    service: "org.freedesktop.UDisks2"
    path: "/org/freedesktop/UDisks2"
    iface: "org.freedesktop.DBus.ObjectManager"
    connection: SystemBus
    watchServiceStatus: true
  }
  Connections {
    target: manager
    function onStatusChanged() { if (manager.status === 2) root.refresh(); }
    function onServiceAvailableChanged() {
      if (manager.serviceAvailable) Qt.callLater(root.refresh);
      else { root._publish({}); if (root.busy) root._error(""); }
    }
    function onSignalReceived(name, args) {
      if (name === "InterfacesAdded" || name === "InterfacesRemoved") changes.restart();
    }
  }
  Instantiator {
    model: root._watched
    delegate: Scope {
      id: watchedObject
      required property var modelData
      DBus {
        id: watchedProxy
        service: "org.freedesktop.UDisks2"
        path: watchedObject.modelData
        iface: "org.freedesktop.DBus.Properties"
        connection: SystemBus
      }
      Connections {
        target: watchedProxy
        function onSignalReceived(name, args) { if (name === "PropertiesChanged") root.scheduleRefresh(); }
      }
    }
  }
  Timer { id: changes; interval: 100; onTriggered: root.refresh() }
  Component {
    id: actionFactory
    DBus { service: "org.freedesktop.UDisks2"; connection: SystemBus }
  }
}
