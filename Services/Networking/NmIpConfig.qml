pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  required property string owner
  required property string path
  required property bool ipv6
  readonly property var facts: ({
                                  path: path,
                                  Gateway: transport.facts.Gateway || "",
                                  addresses: (transport.facts.AddressData || []).filter(a => a.address).map(a => a.address),
                                  nameservers: (transport.facts.NameserverData || []).filter(a => a.address).map(a => a.address)
                                })
  signal changed
  signal failed(string message)
  onFactsChanged: changed()
  NmDevice.Interface {
    id: transport
    owner: root.owner
    path: root.path
    iface: "org.freedesktop.NetworkManager.IP" + (root.ipv6 ? "6" : "4") + "Config"
    fields: ["AddressData", "Gateway", "NameserverData"]
    onFailed: message => root.failed(message)
  }
  function reconcile() {
    transport.reconcile();
  }
  function retire() {
    transport.retire();
  }
}
