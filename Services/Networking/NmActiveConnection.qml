pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
  id: root
  required property string owner
  required property string path
  readonly property var facts: Object.assign({
                                               path: path
                                             }, transport.facts)
  signal changed
  signal failed(string message)
  onFactsChanged: changed()
  NmDevice.Interface {
    id: transport
    owner: root.owner
    path: root.path
    iface: "org.freedesktop.NetworkManager.Connection.Active"
    fields: ["Id", "Uuid", "Type", "Connection", "Devices", "State", "Ip4Config", "Ip6Config", "Reason"]
    onEventReceived: function (member, args) {
      if (member === "StateChanged")
        transport.apply({
                          State: args[0],
                          Reason: args[1]
                        });
    }
    onFailed: message => root.failed(message)
  }
  function reconcile() {
    transport.reconcile();
  }
  function retire() {
    transport.retire();
  }
}
