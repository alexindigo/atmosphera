pragma ComponentBehavior: Bound
import DBus 1.0

import QtQuick

Item {
  id: root
  required property string owner
  required property string path
  readonly property var facts: ({
                                  path: path,
                                  ssid: transport.facts.Ssid ? DBusUtils.textFromBytes(transport.facts.Ssid) : "",
                                  Strength: transport.facts.Strength,
                                  Frequency: transport.facts.Frequency,
                                  Bandwidth: transport.facts.Bandwidth,
                                  Flags: transport.facts.Flags,
                                  WpaFlags: transport.facts.WpaFlags,
                                  RsnFlags: transport.facts.RsnFlags
                                })
  signal changed
  signal failed(string message)
  onFactsChanged: changed()
  NmDevice.Interface {
    id: transport
    owner: root.owner
    path: root.path
    iface: "org.freedesktop.NetworkManager.AccessPoint"
    fields: ["Strength", "Ssid", "Frequency", "Bandwidth", "Flags", "WpaFlags", "RsnFlags"]
    onFailed: message => root.failed(message)
  }
  function reconcile() {
    transport.reconcile();
  }
  function retire() {
    transport.retire();
  }
}
