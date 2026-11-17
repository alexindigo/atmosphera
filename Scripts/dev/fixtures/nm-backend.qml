import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services.Networking

ShellRoot {
  id: root
  property var operations: []
  function result(value) {
    operations = operations.concat([value]);
  }
  IpcHandler {
    target: "nmBackend"
    function state(): string {
      return JSON.stringify({
                              available: NmState.available,
                              epoch: NmState.epoch,
                              manager: NmState.manager,
                              profiles: NmState.profiles,
                              active: NmState.activeConnections,
                              devices: NmState.devices,
                              aps: NmState.accessPoints,
                              ips: NmState.ipConfigs,
                              counts: NmState.recordCounts,
                              refreshing: NmState.refreshing,
                              error: NmState.errorText,
                              operations: root.operations,
                              vpn: VPNService.connections,
                              vpnConnecting: VPNService.connecting,
                              vpnError: VPNService.lastError,
                              network: {
                                networks: NetworkService.networks,
                                profiles: NetworkService.existingProfiles,
                                wifi: NetworkService.activeWifiDetails,
                                ethernet: NetworkService.activeEthernetDetails,
                                wifiConnected: NetworkService.wifiConnected,
                                scanning: NetworkService.scanningActive,
                                connecting: NetworkService.connecting,
                                error: NetworkService.lastError
                              },
                              diagnostics: {
                                sessionCreated: NmState._session !== null,
                                owner: NmState._owner,
                                profilesReading: NmState._profilesReading,
                                refs: Object.values(NmState._devices).map(d => ({
                                  refs: d.references,
                                  type: typeof d.references.ip4,
                                  text: String(d.references.ip4)
                                }))
    }
  });
}
function activate(path: string): string {
  return NmState.activate(path, "/", "/", root.result);
}
function deactivate(uuid: string): string {
  return NmState.deactivate(uuid, root.result);
}
function forget(path: string): string {
  return NmState.deleteProfile(path, root.result);
}
function scan(path: string): string {
  return NmState.requestScan(path, root.result);
}
function reconcile() {
  NmState.reconcileProfiles();
}
function reconcileDevice(path: string) {
  NmState.reconcileDevice(path);
}
function vpnConnect(uuid: string) {
  VPNService.connect(uuid);
}
function vpnDisconnect(uuid: string) {
  VPNService.disconnect(uuid);
}
function wifiConnect(text: string) {
  var a = JSON.parse(text);
  if (a.legacy)
    NetworkService.connect(a.ssid, "synthetic-only", a.hidden, a.identity, a.enterprise);
  else
    NetworkService.connect(a.ssid, "synthetic-only", a.hidden, "wpa2-eap", a.identity, a.enterprise);
}
function stop() {
  Qt.quit();
}
}
}
