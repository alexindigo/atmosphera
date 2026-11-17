import DBus 1.0
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  property var seen: []
  property bool invalidated: false
  property bool ownedInvalidated: false
  property bool explicitSeen: false
  property bool noIntrospectionSeen: false
  property var automaticEndpoint: automatic
  property var ownedEndpoint: owned
  DBus {
    id: automatic
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.NetworkManager"
    connection: SystemBus
    callTimeout: 3000
    onSignalReceived: function (name, args) {
      if (name !== "PropertiesChanged" || args[0] !== iface)
        return;
      if (args[1].Connectivity !== undefined)
        root.seen = root.seen.concat([
                                       {
                                         payload: args[1].Connectivity,
                                         cache: automatic["connectivity"]
                                       }
                                     ]);
      if ((args[2] || []).indexOf("Connectivity") !== -1) {
        // The library's own re-Get is coalesced with this pending waiter.
        var reply = root.automaticEndpoint.getProperty("Connectivity");
        reply.finished.connect(function () {
          root.invalidated = !reply.isError && reply.value === 2;
        });
      }
    }
  }
  DBusSignalWatcher {
    connection: SystemBus
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.DBus.Properties"
    member: "PropertiesChanged"
    onReceived: function (name, args) {
      if (args[0] !== "org.freedesktop.NetworkManager")
        return;
      root.explicitSeen = true;
      if ((args[2] || []).indexOf("WirelessEnabled") !== -1) {
        var reply = root.ownedEndpoint.getProperty("WirelessEnabled");
        reply.finished.connect(function () {
          root.ownedInvalidated = !reply.isError && reply.value === true;
        });
      }
    }
  }
  DBus {
    id: owned
    connection: SystemBus
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.NetworkManager"
    signalsEnabled: false
    propertiesEnabled: false
    callTimeout: 3000
  }
  DBusSignalWatcher {
    connection: SystemBus
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager/NoIntrospection"
    iface: "org.freedesktop.NetworkManager.Connection.Active"
    member: "StateChanged"
    onReceived: function (name, args) {
      root.noIntrospectionSeen = args[0] === 2;
    }
  }
  IpcHandler {
    target: "nmProtocol"
    function state(): string {
      return JSON.stringify({
                              ready: automatic.status === 2,
                              seen: root.seen,
                              cache: automatic["connectivity"],
                              invalidated: root.invalidated,
                              ownedInvalidated: root.ownedInvalidated,
                              explicitSeen: root.explicitSeen,
                              noIntrospectionSeen: root.noIntrospectionSeen
                            });
    }
    function stop() {
      Qt.quit();
    }
    function disableAutomatic() {
      automatic.signalsEnabled = false;
    }
  }
}
