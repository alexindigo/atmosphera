pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

// Compatibility/presentation facade. NmState alone owns daemon state.
Singleton {
  id: root
  property var connections: ({})
  property bool refreshing: NmState.refreshing
  property bool refreshPending: NmState.refreshPending
  property string lastError: ""
  property string _connectUuid: ""
  property string _disconnectUuid: ""
  property string _connectOperation: ""
  property string _disconnectOperation: ""
  readonly property string connectingUuid: _connectUuid || _observedConnectingUuid()
  readonly property string disconnectingUuid: _disconnectUuid || _observedDisconnectingUuid()
  readonly property bool connecting: connectingUuid !== ""
  readonly property bool disconnecting: disconnectingUuid !== ""
  readonly property var activeConnections: Object.values(connections).filter(connection => connection.active)
  readonly property var inactiveConnections: Object.values(connections).filter(connection => !connection.active)
  readonly property bool hasActiveConnection: activeConnections.length > 0

  Connections {
    target: NmState
    function onProfilesChanged() {
      root._project();
    }
    function onActiveConnectionsChanged() {
      root._project();
    }
    function onDevicesChanged() {
      root._project();
    }
  }
  Component.onCompleted: {
    Logger.i("VPN", "Service started (NetworkManager events)");
    _project();
  }
  function _project() {
    var result = {}, active = Object.values(NmState.activeConnections);
    for (var profile of Object.values(NmState.profiles)) {
      if (!profile.uuid || ["vpn", "wireguard"].indexOf(profile.type) === -1)
        continue;
      var instances = active.filter(a => a.Uuid === profile.uuid && a.State === 2);
      var paths = instances.reduce((paths, a) => paths.concat(a.Devices || []), []);
      result[profile.uuid] = {
        uuid: profile.uuid,
        name: profile.id,
        device: paths.map(p => (NmState.devices[p] || {}).ifname || "").filter(name => name).join(", "),
      active: instances.length > 0
    };
  }
  connections = result;
}
  function _observedConnectingUuid() {
    for (var active of Object.values(NmState.activeConnections))
    if ((active.Type === "vpn" || active.Type === "wireguard") && active.State === 1)
    return active.Uuid || "";
    return "";
  }
    function _observedDisconnectingUuid() {
      for (var active of Object.values(NmState.activeConnections))
      if ((active.Type === "vpn" || active.Type === "wireguard") && active.State === 3)
      return active.Uuid || "";
      return "";
    }
      function refresh() {
        NmState.reconcileProfiles();
      }
        Timer {
          id: requestedRefresh
          repeat: false
          onTriggered: root.refresh()
        }
        function scheduleRefresh(interval) {
          requestedRefresh.interval = Math.max(0, interval || 0);
          requestedRefresh.restart();
        }
        function connect(uuid) {
          if (connecting || !uuid)
            return;
          var profile = NmState.profileByUuid(uuid);
          if (!profile) {
            lastError = "Saved profile unavailable";
            return;
          }
          _connectUuid = uuid;
          lastError = "";
          _connectOperation = NmState.activate(profile.path, "/", "/", function (result) {
            if (result.status === "accepted" || result.id !== root._connectOperation)
              return;
            root._connectUuid = "";
            root._connectOperation = "";
            root._notify(uuid, true, result);
          });
        }
        function disconnect(uuid) {
          if (disconnecting || !uuid || !connections[uuid])
            return;
          _disconnectUuid = uuid;
          lastError = "";
          _disconnectOperation = NmState.deactivate(uuid, function (result) {
            if (result.status === "accepted" || result.id !== root._disconnectOperation)
              return;
            root._disconnectUuid = "";
            root._disconnectOperation = "";
            root._notify(uuid, false, result);
          });
        }
        function _notify(uuid, connected, result) {
          var name = connections[uuid] ? connections[uuid].name : uuid;
          if (result.ok) {
            Logger.i("VPN", connected ? "Connected to" : "Disconnected from", name);
            ToastService.showNotice(name, I18n.tr(connected ? "toast.vpn.connected" : "toast.vpn.disconnected", {
                                                    name: name
                                                  }), connected ? "shield-lock" : "shield-off");
          } else {
            lastError = (result.error || "NetworkManager operation failed").split("\n")[0].trim();
            Logger.w("VPN", "Operation failed:", lastError);
            ToastService.showWarning(name, lastError);
          }
        }
        function toggle(uuid) {
          var connection = connections[uuid];
          if (!connection)
            return;
          if (connection.active)
            disconnect(uuid);
          else
            connect(uuid);
        }
        // Legacy callers may request projection, but cannot fabricate daemon-owned
        // active/name/device state through this former optimistic update helper.
        function setConnection(uuid, data) {
          _project();
        }
      }
