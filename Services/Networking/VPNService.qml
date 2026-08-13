pragma Singleton

import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property var connections: ({})
  property bool refreshing: false
  property bool connecting: false
  property bool disconnecting: false
  property string connectingUuid: ""
  property string disconnectingUuid: ""
  property string lastError: ""
  property bool refreshPending: false

  readonly property var activeConnections: {
    const result = [];
    const map = connections;
    for (const key in map) {
      const conn = map[key];
      if (conn && conn.active) {
        result.push(conn);
      }
    }
    return result;
  }

  readonly property var inactiveConnections: {
    const result = [];
    const map = connections;
    for (const key in map) {
      const conn = map[key];
      if (conn && !conn.active) {
        result.push(conn);
      }
    }
    return result;
  }

  readonly property bool hasActiveConnection: activeConnections.length > 0

  // Per-profile D-Bus object paths, keyed by UUID
  property var _connPaths: ({})
  // Reverse map: active-connection path → UUID
  property var _acToUuid: ({})

  Timer {
    id: refreshTimer
    interval: 5000
    running: true
    repeat: true
    onTriggered: refresh()
  }

  Timer {
    id: delayedRefreshTimer
    interval: 1000
    repeat: false
    onTriggered: refresh()
  }

  Component.onCompleted: {
    Logger.i("VPN", "Service started (D-Bus)");
    refresh();
  }

  // NetworkManager manager (for ActivateConnection + active-connection list)
  DBus {
    id: nmManager
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.NetworkManager"
    connection: SystemBus
    watchServiceStatus: true
  }

  // Settings service (saved profiles)
  DBus {
    id: nmSettings
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager/Settings"
    iface: "org.freedesktop.NetworkManager.Settings"
    connection: SystemBus
  }

  // Manager Properties iface (for future property reads if needed)
  DBus {
    id: nmManagerProps
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.DBus.Properties"
    connection: SystemBus
  }

  Connections {
    target: nmManager

    function onSignalReceived(name, args) {
      if (name === "PropertiesChanged" || name === "StateChanged") {
        vpnEventDebounce.restart();
      }
    }

    function onStatusChanged() {
      if (nmManager.status === 2) {
        refresh();
      }
    }

    function onServiceAvailableChanged() {
      if (nmManager.serviceAvailable) {
        refresh();
      }
    }
  }

  Timer {
    id: vpnEventDebounce
    interval: 200
    onTriggered: refresh()
  }

  function refresh() {
    if (refreshing) {
      refreshPending = true;
      return;
    }
    refreshing = true;
    lastError = "";
    _loadProfiles();
  }

  function _loadProfiles() {
    var reply = nmSettings.call("ListConnections", []);
    if (!reply) {
      _finishRefresh();
      return;
    }
    reply.finished.connect(function () {
      if (reply.isError) {
        Logger.w("VPN", "ListConnections failed:", reply.error.message);
        _finishRefresh();
        return;
      }
      var paths = reply.value || [];
      var newConns = {};
      var newPaths = {};
      var pending = paths.length;
      if (pending === 0) {
        connections = newConns;
        _connPaths = newPaths;
        _refreshActiveState();
        return;
      }
      var doneOne = function () {
        pending--;
        if (pending <= 0) {
          connections = newConns;
          _connPaths = newPaths;
          _refreshActiveState();
        }
      };
      for (var i = 0; i < paths.length; i++) {
        root._readProfile(paths[i], newConns, newPaths, doneOne);
      }
    });
  }

  function _readProfile(connPath, newConns, newPaths, done) {
    var proxy = profileReadComponent.createObject(root, {
                                                     "path": connPath
                                                   });
    var reply = proxy.call("GetSettings", []);
    if (!reply) {
      proxy.destroy();
      done();
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError && reply.value && typeof reply.value === "object") {
        var s = reply.value;
        var conn = s["connection"] || {};
        var ctype = conn["type"] || "";
        if (ctype === "vpn" || ctype === "wireguard") {
          var uuid = conn["uuid"] || "";
          var name = conn["id"] || "";
          if (uuid) {
            newConns[uuid] = {
              "uuid": uuid,
              "name": name,
              "device": "",
              "active": false
            };
            newPaths[uuid] = connPath;
          }
        }
      }
      proxy.destroy();
      done();
    });
  }

  Component {
    id: profileReadComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Settings.Connection"
      connection: SystemBus
    }
  }

  function _refreshActiveState() {
    var acs = nmManager.activeConnections || [];
    if (acs.length === 0) {
      _markAllInactive();
      _finishRefresh();
      return;
    }
    var map = Object.assign({}, connections);
    var acToUuid = {};
    var pending = acs.length;
    var doneOne = function () {
      pending--;
      if (pending <= 0) {
        _acToUuid = acToUuid;
        connections = map;
        _finishRefresh();
      }
    };
    for (var i = 0; i < acs.length; i++) {
      root._readAcUuid(acs[i], map, acToUuid, doneOne);
    }
  }

  function _readAcUuid(acPath, map, acToUuid, done) {
    var proxy = acUuidComponent.createObject(root, {
                                               "path": acPath
                                             });
    var reply = proxy.getProperty("Uuid");
    if (!reply) {
      proxy.destroy();
      done();
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError && reply.value !== undefined) {
        var u = String(reply.value);
        acToUuid[acPath] = u;
        if (map[u]) {
          map[u] = Object.assign({}, map[u], {
                                   "active": true
                                 });
        }
      }
      proxy.destroy();
      done();
    });
  }

  Component {
    id: acUuidComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Connection.Active"
      connection: SystemBus
    }
  }

  function _markAllInactive() {
    var map = Object.assign({}, connections);
    var changed = false;
    for (var key in map) {
      if (map[key].active) {
        map[key] = Object.assign({}, map[key], {
                                   "active": false
                                 });
        changed = true;
      }
    }
    if (changed) {
      connections = map;
    }
  }

  function _finishRefresh() {
    var pending = refreshPending;
    refreshing = false;
    refreshPending = false;
    if (pending) {
      scheduleRefresh(200);
    }
  }

  function connect(uuid) {
    if (connecting || !uuid) {
      return;
    }
    const connPath = _connPaths[uuid];
    if (!connPath) {
      Logger.w("VPN", "Connect: no profile path for", uuid);
      return;
    }
    connecting = true;
    connectingUuid = uuid;
    lastError = "";

    // Device and AP are "/" for VPNs
    Logger.i("VPN", "Connecting to", connections[uuid] ? connections[uuid].name : uuid, "(D-Bus)");
    var reply = nmManager.call("ActivateConnection", [connPath, "/", "/"]);
    if (!reply) {
      connecting = false;
      connectingUuid = "";
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError) {
        Logger.i("VPN", "Connected to", connections[uuid] ? connections[uuid].name : uuid);
        setConnection(uuid, {
                        "active": true
                      });
        ToastService.showNotice(connections[uuid] ? connections[uuid].name : uuid, I18n.tr("toast.vpn.connected", {
                                                                                               "name": connections[uuid] ? connections[uuid].name : uuid
                                                                                             }), "shield-lock");
      } else {
        var msg = reply.error.message || "";
        Logger.w("VPN", "Connect error:", msg);
        lastError = msg.split("\n")[0].trim();
        ToastService.showWarning(connections[uuid] ? connections[uuid].name : uuid, lastError);
      }
      connecting = false;
      connectingUuid = "";
      scheduleRefresh(1000);
    });
  }

  function disconnect(uuid) {
    if (disconnecting || !uuid) {
      return;
    }
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    disconnecting = true;
    disconnectingUuid = uuid;
    lastError = "";

    // Find the active connection whose UUID matches
    var acPath = "";
    for (var ap in _acToUuid) {
      if (_acToUuid[ap] === uuid) {
        acPath = ap;
        break;
      }
    }
    if (!acPath) {
      Logger.w("VPN", "Disconnect: no active connection for", uuid);
      disconnecting = false;
      disconnectingUuid = "";
      scheduleRefresh(1000);
      return;
    }
    Logger.i("VPN", "Disconnecting from", conn.name, "(D-Bus)");
    var reply = nmManager.call("DeactivateConnection", [acPath]);
    if (!reply) {
      disconnecting = false;
      disconnectingUuid = "";
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError) {
        Logger.i("VPN", "Disconnected from", conn.name);
        setConnection(uuid, {
                        "active": false,
                        "device": ""
                      });
        ToastService.showNotice(conn.name, I18n.tr("toast.vpn.disconnected", {
                                                      "name": conn.name
                                                    }), "shield-off");
      } else {
        var msg = reply.error.message || "";
        Logger.w("VPN", "Disconnect error:", msg);
        lastError = msg.split("\n")[0].trim();
        ToastService.showWarning(conn.name, lastError);
      }
      disconnecting = false;
      disconnectingUuid = "";
      scheduleRefresh(1000);
    });
  }

  function toggle(uuid) {
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    if (conn.active) {
      disconnect(uuid);
    } else {
      connect(uuid);
    }
  }

  function setConnection(uuid, data) {
    if (!uuid) {
      return;
    }
    const map = Object.assign({}, connections);
    if (map[uuid]) {
      map[uuid] = Object.assign({}, map[uuid], data);
      connections = map;
    }
  }

  function scheduleRefresh(interval) {
    delayedRefreshTimer.interval = interval;
    delayedRefreshTimer.restart();
  }
}
