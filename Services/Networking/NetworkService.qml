pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root
  // Shared core (read-only) properties
  readonly property bool wifiAvailable: _wifiAvailable
  readonly property bool ethernetAvailable: _ethernetAvailable
  readonly property bool internetConnectivity: _internetConnectivity
  readonly property string networkConnectivity: _networkConnectivity

  // Supported Wi-Fi security types
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

  // Core properties
  property bool _wifiAvailable: false
  property bool _ethernetAvailable: false
  property string _networkConnectivity: "unknown"
  property bool _internetConnectivity: false
  property string lastError: ""
  property int activeDetailsTtlMs: 10000

  // Ethernet properties
  property var ethernetInterfaces: ([])
  property var activeEthernetDetails: ({})
  property bool ethernetConnected: false
  property string activeEthernetIf: ""
  property bool ethernetDetailsLoading: false
  property double activeEthernetDetailsTimestamp: 0

  // Wi-Fi properties
  // Wifi radio state — read reactively from the NM manager's
  // WirelessEnabled property (reactive bindings via dbusqml), written via
  // D-Bus Properties.Set. No Quickshell.Networking, no nmcli.
  readonly property bool wifiEnabled: nmManager.wirelessEnabled === true
  property var networks: ({})
  property var activeWifiDetails: ({})
  property bool wifiConnected: false
  property string activeWifiIf: ""
  property bool wifiDetailsLoading: false
  property double activeWifiDetailsTimestamp: 0
  property bool wifiInit: false

  // Wi-Fi adapter/connection properties
  property bool connecting: false
  property string connectingTo: ""
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""
  property bool scanPending: false
  property bool scanningActive: false
  property var existingProfiles: ({})
  property var _apPaths: ({})

  // Airplane mode status
  property bool airplaneModeEnabled: false
  property bool airplaneModeToggled: false

  Connections {
    target: root
    function onWifiEnabledChanged() {
      if (!root.wifiInit) {
        return;
      }
      wifiDebounce.restart();
    }
  }

  // Start the initial sync once NetworkManager is on the bus
  Connections {
    target: nmManager
    function onStatusChanged() {
      if (nmManager.status === 2) {
        // Ready: initial device sync + connectivity read
        root._syncDevices();
        root._applyConnectivity();
        root._refreshProfiles(null);
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Network", "Service started");
    wifiInitTimer.restart();

    // If the manager proxy is already ready (fast bus), sync now
    if (nmManager.status === 2) {
      root._syncDevices();
      root._applyConnectivity();
      root._refreshProfiles(null);
    }
  }

  // Prevent an initial "Wi-Fi enabled" toast and trigger initial scan
  Timer {
    id: wifiInitTimer
    interval: 500
    onTriggered: {
      root.wifiInit = true;
      if (root.wifiEnabled) {
        scan();
      }
      if (!root.wifiEnabled && BluetoothService.blocked) {
        root.airplaneModeEnabled = true;
      }
    }
  }

  // Debounce to prevent multiple toast notifications from transient states
  Timer {
    id: wifiDebounce
    interval: 300
    onTriggered: {
      if (!ProgramCheckerService.nmcliAvailable) {
        return;
      }
      if (root.airplaneModeToggled) {
        root.airplaneModeToggled = false;
        if (root.wifiEnabled) {
          scan();
        } else {
          root.networks = ({});
        }
        return;
      }
      if (root.wifiEnabled) {
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.enabled"), "wifi");
        scan();
      } else {
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.disabled"), "wifi-off");
        root.networks = ({});
      }
    }
  }

  // Delayed scan timer
  Timer {
    id: delayedScanTimer
    interval: 7000
    onTriggered: scan()
  }

  // Core functions
  function setWifiEnabled(enabled) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    Logger.i("Wi-Fi", "SetWifiEnabled", enabled);
    // Properties.Set with a reply so a polkit denial surfaces (the reactive
    // wirelessEnabled read-back reverts the toggle visual if it didn't take).
    var reply = nmManagerProps.call("Set", ["org.freedesktop.NetworkManager", "WirelessEnabled", new DBusQML.variant(enabled)]);
    if (reply) {
      reply.finished.connect(function () {
        if (reply.isError) {
          Logger.w("Wi-Fi", "Set WirelessEnabled failed:", reply.error.message);
          ToastService.showWarning(I18n.tr("common.wifi"), I18n.tr("toast.wifi.toggle-failed", {
                                                                     "error": reply.error.message
                                                                   }), "wifi-off");
        }
      });
    }
  }

  function setAirplaneMode(state) {
    if (state) {
      Quickshell.execDetached(["rfkill", "block", "all"]);
    } else {
      Quickshell.execDetached(["rfkill", "unblock", "all"]);
    }
  }

  function scan() {
    if (!ProgramCheckerService.nmcliAvailable || !root.wifiEnabled) {
      return;
    }
    lastError = "";

    // If scanning in progress, mark as pending to trigger another scan when current when finished.
    if (root.scanningActive) {
      root.scanPending = true;
      return;
    }

    root.scanningActive = true;
    Logger.d("Network", "Scanning Wi-Fi networks (D-Bus)...");

    // Refresh saved profiles, then trigger a rescan + read APs
    root._refreshProfiles(function () {
      root._requestScanAndRead();
    });
  }

  // Ask NM for a fresh wifi scan, then read the AP list
  function _requestScanAndRead() {
    var wifiDev = null;
    for (var path in _devices) {
      var dev = _devices[path];
      if (dev.ready && dev.deviceType === 2) {
        wifiDev = dev;
        if (dev.connected) {
          break;
        }
      }
    }
    if (!wifiDev) {
      root.networks = ({});
      root.scanningActive = false;
      return;
    }

    var wproxy = wifiScanComponent.createObject(root, {
                                                  "path": wifiDev.path
                                                });
    var reply = wproxy.call("RequestScan", [
                              {}
                            ]);
    if (!reply) {
      wproxy.destroy();
      root._refreshWifiNetworks();
      return;
    }
    reply.finished.connect(function () {
      wproxy.destroy();
      // Give NM a moment to collect scan results before reading
      Qt.callLater(function () {
        root._refreshWifiNetworks();
      });
    });
  }

  Component {
    id: wifiScanComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Device.Wireless"
      connection: SystemBus
    }
  }

  function connect(ssid, password = "", isHidden = false, securityKey = "", identity = "", enterpriseConfig = {}) {
    if (!ProgramCheckerService.nmcliAvailable || connecting) {
      return;
    }

    const isSaved = (networks[ssid] && networks[ssid].existing);
    const isEnt = securityKey ? isEnterprise(securityKey) : isEnterprise(networks[ssid] ? networks[ssid].security : "");

    connecting = true;
    connectingTo = ssid;
    lastError = "";

    if (isSaved) {
      // D-Bus: activate the saved profile for this SSID
      root._connectSaved(ssid);
      return;
    }

    // New / manual / enterprise connections: build the NM connection dict
    // and activate via D-Bus AddAndActivateConnection. Plain JS objects
    // marshal to a{sa{sv}} via dbusqml's introspection-driven marshaling;
    // the SSID is a D-Bus byte array via DBusQML.bytes().
    root._connectNew(ssid, password, isHidden, securityKey, identity, enterpriseConfig);
  }

  // Build + activate a brand-new connection over D-Bus
  function _connectNew(ssid, password, isHidden, securityKey, identity, enterpriseConfig) {
    var devPath = root._activeWifiDevicePath();
    if (!devPath) {
      Logger.w("Network", "Connect: no wifi device for", ssid);
      root.connecting = false;
      root.connectingTo = "";
      return;
    }

    var sec = securityKey || (networks[ssid] ? networks[ssid].security : "") || "wpa-psk";
    var isEnt = isEnterprise(sec);

    var wifiSection = {
      "ssid": DBusQML.bytes(ssid),
      "mode": "infrastructure",
      "hidden": isHidden
    };

    var conn = {
      "connection": {
        "id": ssid,
        "type": "802-11-wireless",
        "autoconnect": true
      },
      "802-11-wireless": wifiSection,
      "ipv4": {
        "method": "auto"
      },
      "ipv6": {
        "method": "auto"
      }
    };

    if (sec && sec !== "open") {
      var secSection = {};
      if (sec === "wep") {
        secSection = {
          "key-mgmt": "none",
          "wep-key0": password
        };
      } else if (sec === "sae") {
        secSection = {
          "key-mgmt": "sae",
          "psk": password
        };
      } else if (isEnt) {
        secSection = {
          "key-mgmt": "wpa-eap",
          "802-1x": {
            "eap": [enterpriseConfig.eap || "peap"],
            "phase2-auth": enterpriseConfig.phase2 || "mschapv2",
            "identity": identity,
            "password": password
          }
        };
        if (enterpriseConfig.anonIdentity) {
          secSection["802-1x"]["anonymous-identity"] = enterpriseConfig.anonIdentity;
        }
        if (enterpriseConfig.caCert) {
          secSection["802-1x"]["ca-cert"] = enterpriseConfig.caCert;
        }
      } else {
        // wpa-psk / wpa2-psk and anything unrecognized
        secSection = {
          "key-mgmt": "wpa-psk",
          "psk": password
        };
      }
      conn["802-11-wireless-security"] = secSection;
    }

    var apPath = root._apPaths[ssid] || "/";
    Logger.d("Network", "Connect (D-Bus, new):", ssid, "sec:", sec);
    var reply = nmManager.call("AddAndActivateConnection", [conn, devPath, apPath]);
    if (!reply) {
      root.connecting = false;
      root.connectingTo = "";
      return;
    }
    reply.finished.connect(function () {
      root._onConnectFinished(reply, ssid);
    });
  }

  // Shared connect-result handling for the D-Bus paths
  function _onConnectFinished(reply, ssid) {
    if (!reply.isError) {
      Logger.i("Network", "Connected to network: '" + ssid + "' (D-Bus)");
      root.wifiConnected = true;
      root.updateNetworkStatus(ssid, true);
      root.refreshActiveWifiDetails();
      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                "ssid": ssid
                                                              }), root.getIcon(false));
    } else {
      var msg = reply.error.message || "";
      Logger.w("Network", "Connect error (D-Bus):", msg);
      if (msg.indexOf("ecret") !== -1) {
        root.lastError = I18n.tr("toast.wifi.incorrect-password");
        forget(ssid);
      } else if (msg.indexOf("not found") !== -1 || msg.indexOf("No network") !== -1) {
        root.lastError = I18n.tr("toast.wifi.network-not-found");
      } else if (msg.indexOf("imeout") !== -1) {
        root.lastError = I18n.tr("toast.wifi.connection-timeout");
      } else {
        root.lastError = I18n.tr("toast.wifi.connection-failed");
      }
      ToastService.showWarning(I18n.tr("common.wifi"), root.lastError, "wifi-exclamation");
      root.wifiConnected = false;
    }
    root.connecting = false;
    root.connectingTo = "";
    delayedScanTimer.interval = 5000;
    delayedScanTimer.restart();
  }

  // Activate a saved profile over D-Bus: ActivateConnection(conn, dev, ap)
  function _connectSaved(ssid) {
    root._findSavedConnectionBySsid(ssid, function (connPath) {
      if (!connPath) {
        Logger.w("Network", "Connect: no saved profile found for", ssid);
        root.connecting = false;
        root.connectingTo = "";
        return;
      }
      var devPath = root._activeWifiDevicePath();
      var apPath = root._apPaths[ssid] || "/";
      if (!devPath) {
        Logger.w("Network", "Connect: no wifi device for", ssid);
        root.connecting = false;
        root.connectingTo = "";
        return;
      }
      Logger.d("Network", "Connect (D-Bus, saved):", ssid, "via", connPath);
      var reply = nmManager.call("ActivateConnection", [connPath, devPath, apPath]);
      if (!reply) {
        root.connecting = false;
        root.connectingTo = "";
        return;
      }
      reply.finished.connect(function () {
        root._onConnectFinished(reply, ssid);
      });
    });
  }

  // Active (or first) wifi device's object path
  function _activeWifiDevicePath() {
    var first = "";
    for (var path in _devices) {
      var dev = _devices[path];
      if (dev.ready && dev.deviceType === 2) {
        if (!first) {
          first = path;
        }
        if (dev.connected) {
          return path;
        }
      }
    }
    return first;
  }

  function disconnect(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    disconnectingFrom = ssid;
    // D-Bus: deactivate the active connection whose Id matches the ssid
    root._findActiveConnectionById(ssid, function (acPath) {
      if (!acPath) {
        Logger.w("Network", "Disconnect: no active connection found for", ssid);
        root.disconnectingFrom = "";
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
        return;
      }
      var reply = nmManager.call("DeactivateConnection", [acPath]);
      if (!reply) {
        root.disconnectingFrom = "";
        return;
      }
      reply.finished.connect(function () {
        root._onActionFinished(reply, "disconnect", ssid);
      });
    });
  }

  function forget(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    forgettingNetwork = ssid;

    // D-Bus: find the saved profile for this SSID and delete it
    root._findSavedConnectionBySsid(ssid, function (connPath) {
      if (!connPath) {
        Logger.w("Network", "Forget: no saved profile found for", ssid);
        root._finishForget(ssid, null);
        return;
      }
      var proxy = connDeleteComponent.createObject(root, {
                                                     "path": connPath
                                                   });
      var reply = proxy.call("Delete", []);
      if (!reply) {
        proxy.destroy();
        root._finishForget(ssid, null);
        return;
      }
      reply.finished.connect(function () {
        proxy.destroy();
        root._finishForget(ssid, reply);
      });
    });
  }

  // Shared action-result handling (keeps the toast/scan behavior of the old
  // nmcli processes)
  function _onActionFinished(reply, action, ssid) {
    if (action === "disconnect") {
      if (!reply.isError) {
        Logger.i("Network", "Disconnected from network: '" + ssid + "'");
        root.wifiConnected = false;
        root.updateNetworkStatus(ssid, false);
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.disconnected", {
                                                                  "ssid": ssid
                                                                }), "wifi-off");
      } else {
        Logger.w("Network", "Disconnect error: " + reply.error.message);
      }
      root.disconnectingFrom = "";
      delayedScanTimer.interval = 5000;
      delayedScanTimer.restart();
    }
  }

  function _finishForget(ssid, reply) {
    if (reply && reply.isError) {
      Logger.w("Network", "Forget error: " + reply.error.message);
    } else {
      Logger.i("Network", "Forget network: \"" + ssid + "\"");
      // Update existing status immediately
      let nets = root.networks;
      if (nets[ssid]) {
        nets[ssid].existing = false;
        root.networks = ({});
        root.networks = nets;
      }
    }
    root.forgettingNetwork = "";
    delayedScanTimer.interval = 5000;
    delayedScanTimer.restart();
  }

  // Find the active connection object path whose Id matches
  function _findActiveConnectionById(id, cb) {
    var acs = nmManager.activeConnections || [];
    if (acs.length === 0) {
      cb("");
      return;
    }
    var pending = acs.length;
    var found = "";
    var doneOne = function () {
      pending--;
      if (pending <= 0) {
        cb(found);
      }
    };
    for (var i = 0; i < acs.length; i++) {
      root._readActiveConnId(acs[i], id, function (p, matched) {
        if (matched && !found) {
          found = p;
        }
        doneOne();
      });
    }
  }

  function _readActiveConnId(acPath, wantId, cb) {
    var proxy = acIdComponent.createObject(root, {
                                             "path": acPath
                                           });
    var reply = proxy.getProperty("Id");
    if (!reply) {
      proxy.destroy();
      cb(acPath, false);
      return;
    }
    reply.finished.connect(function () {
      var ok = !reply.isError && String(reply.value) === wantId;
      proxy.destroy();
      cb(acPath, ok);
    });
  }

  Component {
    id: acIdComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Connection.Active"
      connection: SystemBus
    }
  }

  // Find the saved profile path for a wifi SSID (for forget / connect-saved)
  function _findSavedConnectionBySsid(ssid, cb) {
    var reply = nmSettings.call("ListConnections", []);
    if (!reply) {
      cb("");
      return;
    }
    reply.finished.connect(function () {
      if (reply.isError) {
        cb("");
        return;
      }
      var paths = reply.value || [];
      if (paths.length === 0) {
        cb("");
        return;
      }
      var pending = paths.length;
      var found = "";
      var doneOne = function () {
        pending--;
        if (pending <= 0) {
          cb(found);
        }
      };
      for (var i = 0; i < paths.length; i++) {
        root._matchProfileSsid(paths[i], ssid, function (p, matched) {
          if (matched && !found) {
            found = p;
          }
          doneOne();
        });
      }
    });
  }

  function _matchProfileSsid(connPath, wantSsid, cb) {
    var proxy = profileReadComponent.createObject(root, {
                                                    "path": connPath
                                                  });
    var reply = proxy.call("GetSettings", []);
    if (!reply) {
      proxy.destroy();
      cb(connPath, false);
      return;
    }
    reply.finished.connect(function () {
      var ok = false;
      if (!reply.isError && reply.value && typeof reply.value === "object") {
        var s = reply.value;
        var wireless = s["802-11-wireless"] || {};
        var profSsid = root._decodeSsid(wireless["ssid"]);
        ok = (profSsid === wantSsid);
      }
      proxy.destroy();
      cb(connPath, ok);
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

  Component {
    id: connDeleteComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Settings.Connection"
      connection: SystemBus
    }
  }

  // Refresh details for the currently active Wi‑Fi link
  function refreshActiveWifiDetails() {
    for (var path in _devices) {
      var dev = _devices[path];
      if (dev.ready && dev.deviceType === 2 && dev.connected) {
        dev._refreshCore();
        return;
      }
    }
  }

  // Refresh details for the currently active Ethernet link
  function refreshActiveEthernetDetails() {
    for (var path in _devices) {
      var dev = _devices[path];
      if (dev.ready && dev.deviceType === 1 && dev.connected) {
        dev._refreshCore();
        return;
      }
    }
  }

  // Helper function to immediately update network status
  function updateNetworkStatus(ssid, connected) {
    let nets = networks;

    // Update all networks connected status
    for (let key in nets) {
      if (nets[key].connected && key !== ssid) {
        nets[key].connected = false;
      }
    }
    // Update the target network if it exists
    if (nets[ssid]) {
      nets[ssid].connected = connected;
      nets[ssid].existing = true;
    } else if (connected) {
      // Create a temporary entry if network doesn't exist yet
      nets[ssid] = {
        "ssid": ssid,
        "security": "--",
        "signal": 100,
        "connected": true,
        "existing": true
      };
    }
    // Trigger property change notification
    networks = ({});
    networks = nets;
  }

  // Helper functions
  function getSignalInfo(signal, isConnected) {
    let icon = "";
    if (isConnected) {
      if (root._networkConnectivity === "limited") {
        icon = "wifi-exclamation";
      } else if (root._networkConnectivity === "portal" || root._networkConnectivity === "unknown") {
        icon = "wifi-question";
      }
    }
    const label = signal >= 80 ? I18n.tr("wifi.signal.excellent") : signal >= 60 ? I18n.tr("wifi.signal.good") : signal >= 35 ? I18n.tr("wifi.signal.fair") : signal >= 15 ? I18n.tr("wifi.signal.poor") : I18n.tr("wifi.signal.weak");
    if (!icon) {
      icon = signal >= 80 ? "wifi" : signal >= 60 ? "wifi-3" : signal >= 35 ? "wifi-2" : signal >= 15 ? "wifi-1" : "wifi-0";
    }
    return {
      icon,
      label
    };
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== "";
  }

  function isEnterprise(security) {
    if (!security) {
      return false;
    }
    const s = security.toUpperCase();
    return s.indexOf("802.1X") !== -1 || s.indexOf("EAP") !== -1 || s.indexOf("ENTERPRISE") !== -1;
  }

  // Functions used in /Modules/Panels/ControlCenter/Widgets/Network.qml & /Modules/Bar/Widgets/Network.qml
  function getStatusText(showSpeed = false) {
    // This variable can be tied to a toggle
    if (root.connecting) {
      return root.connectingTo ? I18n.tr("common.connecting") + " " + root.connectingTo : I18n.tr("common.connecting");
    }

    if (NetworkService.airplaneModeEnabled) {
      return I18n.tr("toast.airplane-mode.title");
    }
    if (!root.wifiEnabled) {
      return "";
    }

    // Ethernet
    if (root.ethernetConnected) {
      const eth = root.activeEthernetDetails;
      const name = eth.connectionName || (root.ethernetInterfaces.length > 0 ? root.ethernetInterfaces[0].connectionName : "") || "";
      const speed = eth.speed || "";
      return (name + (showSpeed && speed ? " - " + speed : ""));
    }

    // Wi-Fi
    if (root.wifiConnected) {
      const wl = root.activeWifiDetails;
      const speed = wl.rateShort || wl.rate || "";
      const connectedNet = Object.values(root.networks).find(net => net.connected);
      const name = connectedNet ? connectedNet.ssid : (wl.connectionName || "");
      return (name + (showSpeed && speed ? " - " + speed : ""));
    }
    return "";
  }

  function getIcon(forceEthernet = false) {
    if (NetworkService.airplaneModeEnabled && !forceEthernet) {
      return "plane";
    }

    // 1. Ethernet Priority: Show Ethernet icon if connected OR if specifically requested (Panel)
    if (root.ethernetConnected || forceEthernet) {
      switch (root._networkConnectivity) {
      case "limited":
        return "ethernet-exclamation";
      case "portal":
      case "unknown":
        return "ethernet-question";
      case "full":
        return "ethernet";
      default:
        return "ethernet-off";
      }
    }

    // 2. Wi-Fi Fallback
    if (root.wifiAvailable || !forceEthernet) {
      const networkCount = Object.values(root.networks).length;
      if (!root.wifiEnabled) {
        return "wifi-off";
      }
      if (root.wifiConnected) {
        let s = (root.activeWifiDetails && root.activeWifiDetails.signal !== undefined && root.activeWifiDetails.signal !== "") ? root.activeWifiDetails.signal : 0;
        return root.getSignalInfo(s, true).icon;
      }
      if (root.connecting || networkCount > 0) {
        return "wifi-question";
      }
    }
    return (root.ethernetAvailable || root.ethernetConnected) ? "ethernet-off" : root.wifiAvailable ? "wifi-0" : "wifi-off";
  }

  // NetworkManager D-Bus event source (replaces the old `nmcli -t monitor`
  // process, which had no restart-on-exit and whose text parse missed events
  // like cable-unplug reporting device state "unavailable").
  // Manager-level signals cover every connection/device state transition.
  DBus {
    id: nmManager
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager"
    iface: "org.freedesktop.NetworkManager"
    connection: SystemBus
    watchServiceStatus: true
  }

  // The manager's Properties iface — for property SETS with error feedback
  // (setProperty() is fire-and-forget; a polkit denial should surface).
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
      if (name === "PropertiesChanged" || name === "StateChanged" || name === "DeviceAdded" || name === "DeviceRemoved") {
        nmEventDebounce.restart();
      }
    }

    function onServiceAvailableChanged() {
      if (nmManager.serviceAvailable) {
        // NetworkManager (re)started — full re-sync
        nmEventDebounce.restart();
      }
    }
  }

  // Coalesce the burst of D-Bus signals that accompany a single transition
  Timer {
    id: nmEventDebounce
    interval: 150
    onTriggered: {
      root._syncDevices();
      root._applyConnectivity();
    }
  }

  // ============================================================
  // NetworkManager D-Bus state engine (phase 2): device state, link
  // details, wifi AP list, connectivity — no nmcli in the data plane.
  // ============================================================

  // Settings service (saved connection profiles)
  DBus {
    id: nmSettings
    service: "org.freedesktop.NetworkManager"
    path: "/org/freedesktop/NetworkManager/Settings"
    iface: "org.freedesktop.NetworkManager.Settings"
    connection: SystemBus
  }

  // Per-device bundles (NmDevice), keyed by device path
  property var _devices: ({})

  Component {
    id: nmDeviceComponent
    NmDevice {
      onFactsChanged: root._recomputeState()
    }
  }

  // NM DeviceState uint → the state strings the UI knows
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
      return (state >= 40 && state <= 90) ? "connecting" : "unknown";
    }
  }

  function _syncDevices() {
    var paths = nmManager.devices || [];
    var had = false;
    for (var p in _devices) {
      if (paths.indexOf(p) === -1) {
        _devices[p].destroy();
        delete _devices[p];
        had = true;
      }
    }
    for (var i = 0; i < paths.length; i++) {
      var path = paths[i];
      if (!_devices[path]) {
        var dev = nmDeviceComponent.createObject(root, {
                                                   "path": path
                                                 });
        if (dev) {
          _devices[path] = dev;
          had = true;
        }
      }
    }
    if (had) {
      _recomputeState();
    }
  }

  // Connectivity from the manager property (replaces the nmcli 15s poller)
  function _applyConnectivity() {
    var c = nmManager.connectivity;
    var s = "unknown";
    if (c === 1) {
      s = "none";
    } else if (c === 2) {
      s = "portal";
    } else if (c === 3) {
      s = "limited";
    } else if (c === 4) {
      s = "full";
    }
    root._networkConnectivity = (s === "none") ? "unknown" : s;
    root._internetConnectivity = (s === "full");
  }

  // Assemble the public state from the device bundles
  function _recomputeState() {
    var ethList = [];
    var ethAvail = false;
    var wifiAvail = false;
    var ethConn = false;
    var wifiConn = false;
    var activeEth = "";
    var activeWifi = "";
    var ethDetails = ({});
    var wifiDetails = ({});

    for (var path in _devices) {
      var dev = _devices[path];
      if (!dev.ready) {
        continue;
      }
      if (dev.deviceType === 1) {
        ethAvail = true;
        ethList.push({
                       ifname: dev.ifname,
                       state: root._nmStateName(dev.nmState),
                       connected: dev.connected,
                       connectionName: dev.connectionName
                     });
        if (dev.connected && !activeEth) {
          activeEth = dev.ifname;
          ethConn = true;
          ethDetails = root._detailsFromDevice(dev, false);
        }
      } else if (dev.deviceType === 2) {
        wifiAvail = true;
        if (dev.connected && !activeWifi) {
          activeWifi = dev.ifname;
          wifiConn = true;
          wifiDetails = root._detailsFromDevice(dev, true);
        }
      }
    }

    ethList.sort((a, b) => (a.connected !== b.connected) ? (a.connected ? -1 : 1) : a.ifname.localeCompare(b.ifname));

    root._ethernetAvailable = ethAvail;
    root._wifiAvailable = wifiAvail;
    root.ethernetConnected = ethConn;
    root.wifiConnected = wifiConn;
    root.ethernetInterfaces = ethList;
    root.activeEthernetIf = activeEth;
    root.activeEthernetDetails = ethDetails;
    root.activeEthernetDetailsTimestamp = Date.now();
    root.activeWifiIf = activeWifi;
    root.activeWifiDetails = wifiDetails;
    root.activeWifiDetailsTimestamp = Date.now();

    Logger.d("Network", "D-Bus sync: wifiAvailable: " + wifiAvail + ", ethAvailable: " + ethAvail + ", wifiConnected: " + wifiConn + " (" + activeWifi + "), ethConnected: " + ethConn + " (" + activeEth + ")");
  }

  function _detailsFromDevice(dev, isWifi) {
    var d = {
      "connectionName": dev.connectionName,
      "ipv4": dev.ipv4,
      "gateway4": dev.gateway4,
      "dns4": dev.dns4,
      "ipv6": dev.ipv6,
      "gateway6": dev.gateway6,
      "dns6": dev.dns6,
      "hwAddr": dev.hwAddr,
      "speed": dev.speed,
      "ifname": dev.ifname
    };
    if (isWifi) {
      d["rate"] = dev.rate;
      d["rateShort"] = dev.rate;
      d["band"] = dev.wifiBand;
      d["channel"] = dev.wifiChannel;
      d["width"] = dev.wifiWidth;
      d["signal"] = dev.wifiSignal;
    }
    return d;
  }

  // Saved-profile SSIDs (for the "existing" flag on scanned networks)
  function _refreshProfiles(then) {
    var reply = nmSettings.call("ListConnections", []);
    if (!reply) {
      if (then) {
        then();
      }
      return;
    }
    reply.finished.connect(function () {
      if (reply.isError) {
        if (then) {
          then();
        }
        return;
      }
      var paths = reply.value || [];
      var profiles = {};
      var pending = 0;
      var doneOne = function () {
        pending--;
        if (pending <= 0) {
          root.existingProfiles = profiles;
          if (then) {
            then();
          }
        }
      };
      if (paths.length === 0) {
        root.existingProfiles = profiles;
        if (then) {
          then();
        }
        return;
      }
      pending = paths.length;
      for (var i = 0; i < paths.length; i++) {
        root._readProfileSsid(paths[i], profiles, doneOne);
      }
    });
  }

  function _readProfileSsid(connPath, profiles, done) {
    var proxy = profileComponent.createObject(root, {
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
        var wireless = s["802-11-wireless"] || {};
        var id = conn["id"] || "";
        var ssid = root._decodeSsid(wireless["ssid"]);
        var key = ssid || id;
        if (key) {
          profiles[key] = true;
        }
      }
      proxy.destroy();
      done();
    });
  }

  Component {
    id: profileComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Settings.Connection"
      connection: SystemBus
    }
  }

  // SSID arrives as a D-Bus byte array (ay); decode to string
  function _decodeSsid(ay) {
    if (typeof ay === "string") {
      return ay;
    }
    if (!ay || ay.length === undefined) {
      return "";
    }
    var s = "";
    for (var i = 0; i < ay.length; i++) {
      s += String.fromCharCode(ay[i]);
    }
    return s;
  }

  // Map NM AP security flags to our security keys
  function _deriveSecurity(flags, wpaFlags, rsnFlags) {
    var PRIVACY = 0x1;
    var PSK = 0x100;
    var EAP = 0x200;
    var SAE = 0x400;
    var SUITE_B = 0x2000;
    if (!(flags & PRIVACY)) {
      return "open";
    }
    if (!wpaFlags && !rsnFlags) {
      return "wep";
    }
    if (rsnFlags & SAE) {
      return "sae";
    }
    if (rsnFlags & SUITE_B) {
      return "wpa3-eap";
    }
    if (rsnFlags & EAP) {
      return "wpa2-eap";
    }
    if (rsnFlags & PSK) {
      return "wpa2-psk";
    }
    if (wpaFlags & EAP) {
      return "wpa-eap";
    }
    if (wpaFlags & PSK) {
      return "wpa-psk";
    }
    return "wpa-psk";
  }

  // Refresh the wifi AP list from the active wifi device
  function _refreshWifiNetworks() {
    var wifiDev = null;
    for (var path in _devices) {
      var dev = _devices[path];
      if (dev.ready && dev.deviceType === 2) {
        wifiDev = dev;
        if (dev.connected) {
          break;
        }
      }
    }
    if (!wifiDev) {
      root.networks = ({});
      return;
    }

    var wproxy = wifiListComponent.createObject(root, {
                                                  "path": wifiDev.path
                                                });
    var reply = wproxy.call("GetAllAccessPoints", []);
    if (!reply) {
      wproxy.destroy();
      return;
    }
    reply.finished.connect(function () {
      wproxy.destroy();
      if (reply.isError) {
        Logger.w("Network", "GetAllAccessPoints failed:", reply.error.message);
        return;
      }
      var apPaths = reply.value || [];
      var nets = {};
      var activeAp = wifiDev.activeAccessPoint || "";
      var pending = 0;
      var doneOne = function () {
        pending--;
        if (pending <= 0) {
          root.networks = nets;
          root.scanningActive = false;
          if (root.scanPending) {
            root.scanPending = false;
            delayedScanTimer.interval = 100;
            delayedScanTimer.restart();
          }
        }
      };
      if (apPaths.length === 0) {
        root.networks = nets;
        root.scanningActive = false;
        return;
      }
      pending = apPaths.length;
      for (var i = 0; i < apPaths.length; i++) {
        root._readAccessPoint(apPaths[i], nets, activeAp, doneOne);
      }
    });
  }

  Component {
    id: wifiListComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Device.Wireless"
      connection: SystemBus
    }
  }

  function _readAccessPoint(apPath, nets, activeAp, done) {
    var proxy = apReadComponent.createObject(root, {
                                               "path": apPath
                                             });
    var reply = proxy.call("GetAll", ["org.freedesktop.NetworkManager.AccessPoint"]);
    if (!reply) {
      proxy.destroy();
      done();
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError && reply.value && typeof reply.value === "object") {
        var props = reply.value;
        var ssid = root._decodeSsid(props["Ssid"]);
        if (ssid) {
          var signal = props["Strength"] || 0;
          var security = root._deriveSecurity(props["Flags"] || 0, props["WpaFlags"] || 0, props["RsnFlags"] || 0);
          var isConnected = (apPath === activeAp);
          if (!nets[ssid]) {
            nets[ssid] = {
              "ssid": ssid,
              "security": security,
              "signal": signal,
              "connected": isConnected,
              "existing": !!root.existingProfiles[ssid]
            };
            root._apPaths[ssid] = apPath;
          } else {
            if (isConnected) {
              nets[ssid].connected = true;
              nets[ssid].signal = signal;
            } else if (!nets[ssid].connected && signal > nets[ssid].signal) {
              nets[ssid].signal = signal;
            }
          }
        }
      }
      proxy.destroy();
      done();
    });
  }

  Component {
    id: apReadComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.DBus.Properties"
      connection: SystemBus
    }
  }
}
