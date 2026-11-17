pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

// Public network API and presentation only. All NM facts/commands use NmState.
Singleton {
  id: root
  readonly property bool wifiAvailable: _wifiAvailable
  readonly property bool ethernetAvailable: _ethernetAvailable
  readonly property bool internetConnectivity: _internetConnectivity
  readonly property string networkConnectivity: _networkConnectivity
  readonly property bool wifiEnabled: NmState.manager.WirelessEnabled === true
  readonly property var supportedSecurityTypes: [
    {
      key: "open",
      name: I18n.tr("wifi.panel.security-open")
    },
    {
      key: "wep",
      name: I18n.tr("wifi.panel.security-wep")
    },
    {
      key: "wpa-psk",
      name: I18n.tr("wifi.panel.security-wpa")
    },
    {
      key: "wpa2-psk",
      name: I18n.tr("wifi.panel.security-wpa23")
    },
    {
      key: "sae",
      name: I18n.tr("wifi.panel.security-wpa3")
    },
    {
      key: "wpa-eap",
      name: I18n.tr("wifi.panel.security-wpa-ent")
    },
    {
      key: "wpa2-eap",
      name: I18n.tr("wifi.panel.security-wpa2-ent")
    },
    {
      key: "wpa3-eap",
      name: I18n.tr("wifi.panel.security-wpa3-ent")
    }
  ]
  property bool _wifiAvailable: false
  property bool _ethernetAvailable: false
  property string _networkConnectivity: "unknown"
  property bool _internetConnectivity: false
  property string lastError: ""
  // Compatibility field only. Detail freshness is signal-driven, never TTL-polled.
  property int activeDetailsTtlMs: 10000
  property var ethernetInterfaces: []
  property var activeEthernetDetails: ({})
  property bool ethernetConnected: false
  property string activeEthernetIf: ""
  property bool ethernetDetailsLoading: false
  property double activeEthernetDetailsTimestamp: 0
  property var networks: Object.create(null)
  property var activeWifiDetails: ({})
  property bool wifiConnected: false
  property string activeWifiIf: ""
  property bool wifiDetailsLoading: false
  property double activeWifiDetailsTimestamp: 0
  property bool wifiInit: false
  property bool connecting: false
  property string connectingTo: ""
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""
  property bool scanPending: false
  property bool scanningActive: false
  property var existingProfiles: Object.create(null)
  property var _profileChoices: Object.create(null)
  property var _apPaths: Object.create(null)
  property bool airplaneModeEnabled: false
  property bool airplaneModeToggled: false
  readonly property var _devices: NmState.devices
  property string _connectOperation: ""
  property string _scanOperation: ""
  property string _disconnectOperation: ""
  property string _forgetOperation: ""

  Connections {
    target: NmState
    function onManagerChanged() {
      root._applyConnectivity();
      root._projectWifi();
    }
    function onDevicesChanged() {
      root._recomputeState();
      root._projectWifi();
    }
    function onProfilesChanged() {
      root._projectProfiles();
      root._projectWifi();
    }
    function onAccessPointsChanged() {
      root._projectWifi();
    }
    function onActiveConnectionsChanged() {
      root._projectProfiles();
      root._projectWifi();
    }
  }
  onWifiEnabledChanged: if (wifiInit)
                          wifiDebounce.restart()
  Component.onCompleted: {
    Logger.i("Network", "Service started (NetworkManager events)");
    _applyConnectivity();
    _projectProfiles();
    _recomputeState();
    _projectWifi();
    wifiInitTimer.restart();
  }
  Timer {
    id: wifiInitTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.wifiInit = true;
      if (root.wifiEnabled)
        root.scan();
      if (!root.wifiEnabled && BluetoothService.blocked)
        root.airplaneModeEnabled = true;
    }
  }
  Timer {
    id: wifiDebounce
    interval: 300
    repeat: false
    onTriggered: {
      if (!NmState.available)
        return;
      if (root.airplaneModeToggled) {
        root.airplaneModeToggled = false;
        if (root.wifiEnabled)
          root.scan();
        return;
      }
      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr(root.wifiEnabled ? "common.enabled" : "common.disabled"), root.wifiEnabled ? "wifi" : "wifi-off");
      if (root.wifiEnabled)
        root.scan();
    }
  }
  function setWifiEnabled(enabled) {
    if (!NmState.available)
      return;
    NmState.setWirelessEnabled(enabled, function (result) {
      if (!result.ok) {
        root.lastError = result.error;
        Logger.w("Network", "Set WirelessEnabled failed:", result.error);
        ToastService.showWarning(I18n.tr("common.wifi"), I18n.tr("toast.wifi.toggle-failed", {
                                                                   error: result.error
                                                                 }), "wifi-off");
      }
    });
  }
  function setAirplaneMode(state) {
    Quickshell.execDetached(["rfkill", state ? "block" : "unblock", "all"]);
  }
  function scan() {
    if (!NmState.available || !wifiEnabled)
      return;
    if (scanningActive) {
      scanPending = true;
      return;
    }
    var path = _activeWifiDevicePath();
    if (!path)
      return;
    lastError = "";
    scanningActive = true;
    _scanOperation = NmState.requestScan(path, function (result) {
      if (result.status === "accepted" || result.id !== root._scanOperation)
        return;
      root._scanOperation = "";
      root.scanningActive = false;
      if (!result.ok) {
        root.lastError = result.error;
        Logger.w("Network", "Scan failed:", result.error);
      }
      if (root.scanPending) {
        root.scanPending = false;
        Qt.callLater(root.scan);
      }
    });
  }
  function connect(ssid, password = "", isHidden = false, securityKey = "", identity = "", enterpriseConfig = {}) {
    if (!NmState.available || connecting)
      return;
    // The saved-network password sheet predates the manual-network six-arg
    // API and passes (ssid, password, hidden, identity, enterpriseConfig).
    if (identity && typeof identity === "object") {
      enterpriseConfig = identity;
      identity = securityKey;
      securityKey = "";
    }
    var path = _activeWifiDevicePath();
    if (!path) {
      lastError = "Wireless device unavailable";
      return;
    }
    connecting = true;
    connectingTo = ssid;
    lastError = "";
    var selected = _profileChoices[ssid], ap = _apPaths[ssid] || "/";
    var done = function (result) {
      root._onConnectFinished(result, ssid);
    };
    if (selected)
      _connectOperation = NmState.activate(selected.path, path, ap, done);
    else
      _connectOperation = NmState.activateWifi(ssid, password, isHidden, securityKey || (networks[ssid] ? networks[ssid].security : "") || "wpa-psk", identity, enterpriseConfig, path, ap, done);
  }
  function _onConnectFinished(result, ssid) {
    if (result.status === "accepted" || result.id !== _connectOperation)
      return;
    _connectOperation = "";
    connecting = false;
    connectingTo = "";
    if (result.ok) {
      Logger.i("Network", "Connected to network:", ssid);
      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                ssid: ssid
                                                              }), getIcon(false));
    } else {
      var message = result.error || "";
      Logger.w("Network", "Connect error:", message);
      if (message.indexOf("ecret") !== -1)
        lastError = I18n.tr("toast.wifi.incorrect-password");
      else if (message.indexOf("not found") !== -1 || message.indexOf("No network") !== -1)
        lastError = I18n.tr("toast.wifi.network-not-found");
      else if (message.indexOf("imeout") !== -1 || message.indexOf("timed out") !== -1)
        lastError = I18n.tr("toast.wifi.connection-timeout");
      else
        lastError = I18n.tr("toast.wifi.connection-failed");
      ToastService.showWarning(I18n.tr("common.wifi"), lastError, "wifi-exclamation");
    }
  }
  function _activeWifiDevicePath() {
    var candidates = Object.values(_devices).filter(d => d.ready && d.deviceType === 2);
    candidates.sort((a, b) => a.path.localeCompare(b.path));
    var active = candidates.find(d => d.connected && d.ifname === activeWifiIf) || candidates.find(d => d.connected);
    return active ? active.path : candidates.length ? candidates[0].path : "";
  }
  function disconnect(ssid) {
    if (!NmState.available || disconnectingFrom)
      return;
    var selected = _profileChoices[ssid];
    var paths = Object.keys(NmState.activeConnections).filter(function (path) {
      var active = NmState.activeConnections[path], profile = NmState.profiles[active.Connection];
      return active.State !== 4 && active.Type === "802-11-wireless" && ((selected && active.Uuid === selected.uuid) || (profile && profile.ssid === ssid));
    });
    disconnectingFrom = ssid;
    lastError = "";
    _disconnectOperation = NmState.deactivatePaths(paths, function (result) {
      if (result.status === "accepted" || result.id !== root._disconnectOperation)
        return;
      root._disconnectOperation = "";
      root.disconnectingFrom = "";
      if (result.ok)
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.disconnected", {
                                                                  ssid: ssid
                                                                }), "wifi-off");
      else {
        root.lastError = result.error;
        Logger.w("Network", "Disconnect error:", result.error);
      }
    });
  }
  function forget(ssid) {
    if (!NmState.available || forgettingNetwork)
      return;
    var selected = _profileChoices[ssid];
    if (!selected) {
      lastError = "Saved profile unavailable";
      return;
    }
    forgettingNetwork = ssid;
    lastError = "";
    _forgetOperation = NmState.deleteProfile(selected.path, function (result) {
      if (result.status === "accepted" || result.id !== root._forgetOperation)
        return;
      root._forgetOperation = "";
      root.forgettingNetwork = "";
      if (!result.ok) {
        root.lastError = result.error;
        Logger.w("Network", "Forget error:", result.error);
      }
    });
  }
  function refreshActiveWifiDetails() {
    _refreshDetails(2, activeWifiIf);
  }
  function refreshActiveEthernetDetails() {
    _refreshDetails(1, activeEthernetIf);
  }
  function _refreshDetails(type, ifname) {
    var candidates = Object.values(_devices).filter(d => d.ready && d.deviceType === type && d.connected);
    var selected = candidates.find(d => d.ifname === ifname) || candidates[0];
    if (selected)
      NmState.reconcileDevice(selected.path);
  }
  // Compatibility helper: state is always projected from observed facts.
  function updateNetworkStatus(ssid, connected) {
    _recomputeState();
    _projectWifi();
  }
  function _projectProfiles() {
    var existing = Object.create(null), choices = Object.create(null);
    for (var profile of Object.values(NmState.profiles)) {
      if (profile.ssid || profile.id)
        existing[profile.ssid || profile.id] = true;
      if (profile.type === "802-11-wireless" && profile.ssid) {
        var selected = NmState.profileForSsid(profile.ssid);
        if (selected)
          choices[profile.ssid] = {
            uuid: selected.uuid,
            path: selected.path
          };
      }
    }
    existingProfiles = existing;
    _profileChoices = choices;
  }
  function _projectWifi() {
    var result = Object.create(null), paths = Object.create(null), devicePath = _activeWifiDevicePath(), device = _devices[devicePath];
    if (wifiEnabled && device)
      for (var path of device.accessPoints || []) {
        var ap = NmState.accessPoints[path];
        if (!ap || !ap.ssid)
          continue;
        var candidate = {
          ssid: ap.ssid,
          security: _deriveSecurity(ap.Flags || 0, ap.WpaFlags || 0, ap.RsnFlags || 0),
          signal: ap.Strength || 0,
          connected: device.connected && path === device.activeAccessPoint,
          existing: !!existingProfiles[ap.ssid]
        };
        var old = result[ap.ssid];
        if (!old || (candidate.connected && !old.connected) || (!old.connected && candidate.signal > old.signal)) {
          result[ap.ssid] = candidate;
          paths[ap.ssid] = path;
        }
      }
    // Hidden active APs can omit Ssid. Use the linked profile's stable identity,
    // never the connection's display name as an internal transport key.
    if (wifiEnabled && device && device.connected) {
      var active = NmState.activeConnections[device.activeConnection] || {}, profile = NmState.profiles[active.Connection];
      if (profile && profile.ssid && (!result[profile.ssid] || !result[profile.ssid].connected)) {
        result[profile.ssid] = {
          ssid: profile.ssid,
          security: profile.security || "open",
          signal: Number(device.wifiSignal) || 0,
          connected: true,
          existing: true
        };
        paths[profile.ssid] = device.activeAccessPoint || "/";
      }
    }
    networks = result;
    _apPaths = paths;
  }
  function _nmStateName(state) {
    switch (state) {
    case 100:
      return "connected";
    case 30:
      return "disconnected";
    case 20:
      return "unavailable";
    case 10:
      return "unmanaged";
    case 110:
      return "deactivating";
    case 120:
      return "failed";
    default:
      return state >= 40 && state <= 90 ? "connecting" : "unknown";
    }
  }
  function _applyConnectivity() {
    var value = NmState.manager.Connectivity;
    _networkConnectivity = value === 2 ? "portal" : value === 3 ? "limited" : value === 4 ? "full" : "unknown";
    _internetConnectivity = value === 4;
  }
  function _recomputeState() {
    var ethernet = Object.values(_devices).filter(d => d.ready && d.deviceType === 1);
    var wifi = Object.values(_devices).filter(d => d.ready && d.deviceType === 2);
    ethernet.sort((a, b) => a.connected !== b.connected ? a.connected ? -1 : 1 : a.ifname.localeCompare(b.ifname));
    var activeEth = ethernet.find(d => d.connected && d.ifname === activeEthernetIf) || ethernet.find(d => d.connected);
    var activeWifi = wifi.find(d => d.connected && d.ifname === activeWifiIf) || wifi.find(d => d.connected);
    _ethernetAvailable = ethernet.length > 0;
    _wifiAvailable = wifi.length > 0;
    ethernetInterfaces = ethernet.map(d => ({
      ifname: d.ifname,
      state: _nmStateName(d.nmState),
      connected: d.connected,
      connectionName: d.connectionName
    }));
    ethernetConnected = !!activeEth;
    wifiConnected = !!activeWifi;
    activeEthernetIf = activeEth ? activeEth.ifname : "";
    activeWifiIf = activeWifi ? activeWifi.ifname : "";
    var ethDetails = activeEth ? _detailsFromDevice(activeEth, false) : {}, wifiDetails = activeWifi ? _detailsFromDevice(activeWifi, true) : {};
    if (JSON.stringify(activeEthernetDetails) !== JSON.stringify(ethDetails)) {
      activeEthernetDetails = ethDetails;
      activeEthernetDetailsTimestamp = Date.now();
    }
    if (JSON.stringify(activeWifiDetails) !== JSON.stringify(wifiDetails)) {
      activeWifiDetails = wifiDetails;
      activeWifiDetailsTimestamp = Date.now();
    }
    ethernetDetailsLoading = false;
    wifiDetailsLoading = false;
  }
  function _detailsFromDevice(device, wifi) {
    var details = {
      connectionName: device.connectionName,
      ipv4: device.ipv4,
      gateway4: device.gateway4,
      dns4: device.dns4,
      ipv6: device.ipv6,
      gateway6: device.gateway6,
      dns6: device.dns6,
      hwAddr: device.hwAddr,
      speed: device.speed,
      ifname: device.ifname
    };
    if (wifi)
      Object.assign(details, {
                      rate: device.rate,
                      rateShort: device.rate,
                      band: device.wifiBand,
                      channel: device.wifiChannel,
                      width: device.wifiWidth,
                      signal: device.wifiSignal
                    });
    return details;
  }
  function _deriveSecurity(flags, wpaFlags, rsnFlags) {
    if (!(flags & 1))
      return "open";
    if (!wpaFlags && !rsnFlags)
      return "wep";
    if (rsnFlags & 0x400)
      return "sae";
    if (rsnFlags & 0x2000)
      return "wpa3-eap";
    if (rsnFlags & 0x200)
      return "wpa2-eap";
    if (rsnFlags & 0x100)
      return "wpa2-psk";
    if (wpaFlags & 0x200)
      return "wpa-eap";
    return "wpa-psk";
  }
  function getSignalInfo(signal, isConnected) {
    var icon = isConnected && _networkConnectivity === "limited" ? "wifi-exclamation" : isConnected && (_networkConnectivity === "portal" || _networkConnectivity === "unknown") ? "wifi-question" : "";
    var label = signal >= 80 ? I18n.tr("wifi.signal.excellent") : signal >= 60 ? I18n.tr("wifi.signal.good") : signal >= 35 ? I18n.tr("wifi.signal.fair") : signal >= 15 ? I18n.tr("wifi.signal.poor") : I18n.tr("wifi.signal.weak");
    return {
      icon: icon || (signal >= 80 ? "wifi" : signal >= 60 ? "wifi-3" : signal >= 35 ? "wifi-2" : signal >= 15 ? "wifi-1" : "wifi-0"),
      label: label
    };
  }
  function isSecured(security) {
    return !!security && security !== "--" && security !== "open" && security.trim() !== "";
  }
  function isEnterprise(security) {
    if (!security)
      return false;
    var value = security.toUpperCase();
    return value.indexOf("802.1X") !== -1 || value.indexOf("EAP") !== -1 || value.indexOf("ENTERPRISE") !== -1;
  }
  function getStatusText(showSpeed = false) {
    if (connecting)
      return connectingTo ? I18n.tr("common.connecting") + " " + connectingTo : I18n.tr("common.connecting");
    if (airplaneModeEnabled)
      return I18n.tr("toast.airplane-mode.title");
    if (ethernetConnected) {
      var name = activeEthernetDetails.connectionName || (ethernetInterfaces[0] || {}).connectionName || "", speed = activeEthernetDetails.speed || "";
      return name + (showSpeed && speed ? " - " + speed : "");
    }
    if (wifiEnabled && wifiConnected) {
      var network = Object.values(networks).find(n => n.connected), rate = activeWifiDetails.rateShort || activeWifiDetails.rate || "";
      return (network ? network.ssid : activeWifiDetails.connectionName || "") + (showSpeed && rate ? " - " + rate : "");
    }
    return "";
  }
  function getIcon(forceEthernet = false) {
    if (airplaneModeEnabled && !forceEthernet)
      return "plane";
    if (ethernetConnected || forceEthernet)
      return _networkConnectivity === "full" ? "ethernet" : _networkConnectivity === "limited" ? "ethernet-exclamation" : _networkConnectivity === "unknown" || _networkConnectivity === "portal" ? "ethernet-question" : "ethernet-off";
    if (wifiAvailable || !forceEthernet) {
      if (!wifiEnabled)
        return "wifi-off";
      if (wifiConnected)
        return getSignalInfo(activeWifiDetails.signal || 0, true).icon;
      if (connecting || Object.keys(networks).length > 0)
        return "wifi-question";
    }
    return ethernetAvailable || ethernetConnected ? "ethernet-off" : wifiAvailable ? "wifi-0" : "wifi-off";
  }
}
