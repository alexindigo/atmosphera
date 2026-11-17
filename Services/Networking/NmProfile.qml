pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "NmSsid.js" as Ssid

Scope {
  id: root
  required property string owner
  required property string path
  property bool live: true
  property bool reading: false
  property bool dirtyAgain: false
  property int revision: 0
  property bool ready: false
  property string errorText: ""
  property var facts: ({})
  signal changed
  signal removed
  onFactsChanged: changed()
  NmDevice.Interface {
    id: transport
    owner: root.owner
    path: root.path
    iface: "org.freedesktop.NetworkManager.Settings.Connection"
    autoSeed: false
    onEventReceived: function (member, args) {
      if (member === "Updated") {
        root.revision++;
        root.reconcile();
      } else if (member === "Removed")
        root.removed();
    }
  }
  Component.onCompleted: Qt.callLater(reconcile)
  function reconcile() {
    if (!live)
      return;
    if (reading) {
      dirtyAgain = true;
      return;
    }
    reading = true;
    var started = revision;
    transport.invoke("GetSettings", [], function (result) {
      if (!root || !root.live)
        return;
      root.reading = false;
      if (started === root.revision) {
        if (!result.ok) {
          root.facts = ({});
          root.ready = false;
          root.errorText = result.error;
        } else {
          // Never retain the settings reply or secrets. Every profile type is
          // watched: a type/SSID/security edit can change either facade.
          var settings = result.value || {}, connection = settings.connection || {};
          var wifi = settings["802-11-wireless"] || {}, security = settings["802-11-wireless-security"] || {};
          root.facts = {
            path: root.path,
            uuid: connection.uuid || "",
            id: connection.id || "",
            type: connection.type || "",
            ssid: root.decodeSsid(wifi.ssid),
            security: security["key-mgmt"] || "",
            hidden: wifi.hidden === true
          };
          root.ready = true;
          root.errorText = "";
        }
      }
      if (root.dirtyAgain) {
        root.dirtyAgain = false;
        root.reconcile();
      }
      root.changed();
    });
  }
  function deleteProfile(done) {
    transport.invoke("Delete", [], done);
  }
  function retire() {
    live = false;
    transport.retire();
    facts = ({});
  }
  function decodeSsid(bytes) {
    return Ssid.decode(bytes);
  }
}
