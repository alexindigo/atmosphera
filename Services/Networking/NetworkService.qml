pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
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
  readonly property bool wifiEnabled: Networking.wifiEnabled
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
    Networking.wifiEnabled = enabled;
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

    connectProcess.ssid = ssid;
    connectProcess.password = password;
    connectProcess.isHidden = isHidden;

    if (isSaved) {
      connectProcess.mode = "saved";
    } else if (isEnt || securityKey === "wep" || (securityKey && securityKey !== "open" && securityKey !== "wpa-psk" && securityKey !== "wpa2-psk")) {
      connectProcess.mode = "manual";
      connectProcess.securityKey = securityKey || (networks[ssid] ? networks[ssid].security : "wpa-psk");
      connectProcess.identity = identity;
      connectProcess.eap = enterpriseConfig.eap || "peap";
      connectProcess.phase2 = enterpriseConfig.phase2 || "mschapv2";
      connectProcess.anonIdentity = enterpriseConfig.anonIdentity || "";
      connectProcess.caCert = enterpriseConfig.caCert || "";
    } else {
      connectProcess.mode = "new";
    }

    connectProcess.running = true;
  }

  function disconnect(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    disconnectingFrom = ssid;
    disconnectProcess.ssid = ssid;
    disconnectProcess.running = true;
  }

  function forget(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    forgettingNetwork = ssid;

    // Remove from system
    forgetProcess.ssid = ssid;
    forgetProcess.running = true;
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

  // Connect to Wi-Fi network
  Process {
    id: connectProcess
    property string mode: "new" // "saved", "new", or "manual"
    property string ssid: ""
    property string password: ""
    property bool isHidden: false
    // Manual properties
    property string securityKey: ""
    property string identity: ""
    property string eap: "peap"
    property string phase2: "mschapv2"
    property string anonIdentity: ""
    property string caCert: ""
    running: false

    command: {
      if (mode === "saved") {
        return ["nmcli", "-t", "connection", "up", "id", ssid];
      } else if (mode === "manual") {
        const nmArgs = ["connection", "add", "type", "wifi", "con-name", ssid, "ssid", ssid, "--", "802-11-wireless.hidden", isHidden ? "yes" : "no"];

        if (securityKey === "wpa-psk" || securityKey === "wpa2-psk") {
          nmArgs.push("wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password);
        } else if (securityKey === "sae") {
          nmArgs.push("wifi-sec.key-mgmt", "sae", "wifi-sec.psk", password);
        } else if (securityKey === "wep") {
          nmArgs.push("wifi-sec.key-mgmt", "none", "wifi-sec.wep-key0", password);
        } else if (securityKey && securityKey.indexOf("-eap") !== -1) {
          nmArgs.push("wifi-sec.key-mgmt", "wpa-eap", "802-1x.eap", eap, "802-1x.phase2-auth", phase2, "802-1x.identity", identity, "802-1x.password", password);
          if (anonIdentity) {
            nmArgs.push("802-1x.anonymous-identity", anonIdentity);
          }
          if (caCert) {
            nmArgs.push("802-1x.ca-cert", caCert);
          }
        }

        const script = `
        SSID="$1"
        shift
        # Find existing profile by Name and Type
        UUID=$(nmcli -t -f NAME,UUID,TYPE connection show | awk -F: -v target="$SSID" '$1 == target && $3 == "802-11-wireless" { print $2; exit }')

        if [ -n "$UUID" ]; then
            echo "Using existing profile: $UUID"
            nmcli connection delete uuid "$UUID" 2>/dev/null || true
        else
            echo "Creating new profile for $SSID"
        fi
        nmcli "$@"
        nmcli connection up id "$SSID"
      `;

        return ["sh", "-c", script, "--", ssid].concat(nmArgs);
      } else {
        var cmd = ["nmcli", "-t", "device", "wifi", "connect", ssid];
        if (isHidden) {
          cmd.push("hidden", "yes");
        }
        if (password) {
          cmd.push("password", password);
        }
        if (root.activeWifiIf) {
          cmd.push("ifname", root.activeWifiIf);
        }
        return cmd;
      }
    }

    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: StdioCollector {
      onStreamFinished: {
        const output = text.trim();
        if (!output || (output.indexOf("successfully activated") === -1 && output.indexOf("Connection successfully") === -1)) {
          return;
        }

        root.wifiConnected = true;
        root.updateNetworkStatus(connectProcess.ssid, true);
        root.refreshActiveWifiDetails(); // This needs wifiConnected true.

        root.connecting = false;
        root.connectingTo = "";
        Logger.i("Network", "Connected to network: '" + connectProcess.ssid + "' (" + connectProcess.mode + ")");
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                  "ssid": connectProcess.ssid
                                                                }), root.getIcon(false));

        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          root.connecting = false;
          root.connectingTo = "";

          if (text.indexOf("Secrets were required") !== -1 || text.indexOf("no secrets provided") !== -1) {
            root.lastError = I18n.tr("toast.wifi.incorrect-password");
            forget(connectProcess.ssid);
          } else if (text.indexOf("No network with SSID") !== -1) {
            root.lastError = I18n.tr("toast.wifi.network-not-found");
          } else if (text.indexOf("Timeout") !== -1) {
            root.lastError = I18n.tr("toast.wifi.connection-timeout");
          } else {
            root.lastError = I18n.tr("toast.wifi.connection-failed");
          }

          Logger.w("Network", "Connect error (" + connectProcess.mode + "): " + text);
          ToastService.showWarning(I18n.tr("common.wifi"), root.lastError || I18n.tr("toast.wifi.connection-failed"), "wifi-exclamation");
          wifiConnected = false;
        }
      }
    }
  }

  // Disconnect from Wi-Fi network
  Process {
    id: disconnectProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "down", "id", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Disconnected from network: '" + disconnectProcess.ssid + "'");
        root.wifiConnected = false;
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.disconnected", {
                                                                  "ssid": disconnectProcess.ssid
                                                                }), "wifi-off");

        // Immediately update UI on successful disconnect
        root.updateNetworkStatus(disconnectProcess.ssid, false);
        root.disconnectingFrom = "";

        // Do a scan to refresh the list
        delayedScanTimer.interval = 3000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.disconnectingFrom = "";
        if (text.trim()) {
          Logger.w("Network", "Disconnect error: " + text);
        }
        // Still trigger a scan even on error
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }
  }

  // Forget given Wi-Fi network
  Process {
    id: forgetProcess
    property string ssid: ""
    running: false
    environment: ({
                    "LC_ALL": "C"
                  })

    // Try multiple common profile name patterns
    command: {
      var script = `
        ssid="$1"
        deleted=false

        # Find existing profile by Name and Type
        UUID=$(nmcli -t -f NAME,UUID,TYPE connection show | awk -F: -v target="$ssid" '$1 == target && $3 == "802-11-wireless" { print $2; exit }')

        if [ -n "$UUID" ]; then
            if nmcli connection delete uuid "$UUID" 2>/dev/null; then
                echo "Deleted profile: $ssid ($UUID)"
                deleted=true
            fi
        fi

        # Fallback: try common patterns if UUID lookup failed
        if [ "$deleted" = "false" ]; then
            # Try "Auto $ssid" pattern
            if nmcli connection delete id "Auto $ssid" 2>/dev/null; then
                echo "Deleted profile: Auto $ssid"
                deleted=true
            fi

            # Try "$ssid 1", "$ssid 2", etc. patterns
            for i in 1 2 3; do
                if nmcli connection delete id "$ssid $i" 2>/dev/null; then
                    echo "Deleted profile: $ssid $i"
                    deleted=true
                fi
            done
        fi

        if [ "$deleted" = "false" ]; then
            echo "No profiles found for SSID: $ssid"
        fi
      `;

      return ["sh", "-c", script, "--", ssid];
    }

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Forget network: \"" + forgetProcess.ssid + "\"");
        Logger.d("Network", text.trim().replace(/[\r\n]/g, " "));

        // Update existing status immediately
        let nets = root.networks;
        if (nets[forgetProcess.ssid]) {
          nets[forgetProcess.ssid].existing = false;
          // Trigger property change
          root.networks = ({});
          root.networks = nets;
        }

        root.forgettingNetwork = "";

        // Scan to verify the profile is gone
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.forgettingNetwork = "";
        if (text.trim() && text.indexOf("No profiles found") === -1) {
          Logger.w("Network", "Forget error: " + text);
        }
        // Still Trigger a scan even on error
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }
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
