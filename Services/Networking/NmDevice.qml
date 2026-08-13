pragma ComponentBehavior: Bound

import DBus 1.0
import QtQuick

// A NetworkManager device bundle: state + details via D-Bus (no nmcli).
//
// Layered proxies because NM's object model splits per interface and some
// objects (Ip4Config/Ip6Config, Connection.Active) do not answer
// introspection — those reads go through getProperty()/call() directly.
//
// Root is an Item (not QtObject) so the Component children below are legal:
// QtObject's default property is list<QtObject>, which rejects Components.
Item {
  id: root

  // The D-Bus object path of the device (e.g. /org/freedesktop/NetworkManager/Devices/2)
  property string path: ""

  // Public, auto-updating device facts
  readonly property bool ready: _devReady
  readonly property string ifname: _ifname
  readonly property int deviceType: _deviceType // NM DeviceType: 1=ethernet, 2=wifi, 32=generic/loopback
  readonly property int nmState: _state // NM DeviceState: 100=activated; exposed as nmState
  readonly property bool connected: _state === 100
  readonly property string hwAddr: _hwAddr
  readonly property string connectionName: _connectionName
  readonly property string speed: _speed // ethernet: e.g. "1000 Mbps" (Wired.Speed is Mb/s)
  readonly property string rate: _rate // wifi: bitrate, normalized to "N Mbit/s"
  readonly property string ipv4: _ipv4
  readonly property string gateway4: _gateway4
  readonly property var dns4: _dns4
  readonly property var ipv6: _ipv6
  readonly property var gateway6: _gateway6
  readonly property var dns6: _dns6

  // Wifi-only (populated via the active AccessPoint)
  readonly property string activeAccessPoint: _activeAccessPoint
  readonly property string wifiSignal: _wifiSignal
  readonly property string wifiBand: _wifiBand
  readonly property string wifiChannel: _wifiChannel
  readonly property string wifiWidth: _wifiWidth

  property bool _devReady: false
  property string _ifname: ""
  property int _deviceType: 0
  property int _state: 0
  property string _hwAddr: ""
  property string _connectionName: ""
  property string _speed: ""
  property string _rate: ""
  property string _ipv4: ""
  property string _gateway4: ""
  property var _dns4: []
  property var _ipv6: []
  property var _gateway6: []
  property var _dns6: []
  property string _activeAccessPoint: ""
  property string _ip4Path: ""
  property string _ip6Path: ""
  property string _acPath: ""
  property string _wifiSignal: ""
  property string _wifiBand: ""
  property string _wifiChannel: ""
  property string _wifiWidth: ""

  signal factsChanged

  function _emitFacts() {
    factsChanged();
  }

  // The device object itself (introspects fine)
  property var _dev: DBus {
    service: "org.freedesktop.NetworkManager"
    path: root.path
    iface: "org.freedesktop.NetworkManager.Device"
    connection: SystemBus

    onSignalReceived: function (name, args) {
      if (name === "StateChanged") {
        root._refreshCore();
      } else if (name === "PropertiesChanged") {
        root._refreshCore();
      }
    }

    onIntrospectionCompleted: {
      root._refreshCore();
    }
  }

  // Wired-specific facts (speed, carrier)
  property var _wired: null
  // Wireless-specific facts (bitrate, active AP)
  property var _wireless: null

  function _refreshCore() {
    var dev = root._dev;
    // Dynamic props auto-fetched post-introspection
    var newState = (dev.state !== undefined) ? dev.state : 0;
    var newType = (dev.deviceType !== undefined) ? dev.deviceType : 0;
    var newIf = dev["interface"] || "";
    var newHw = dev.hwAddress || "";
    var newAcPath = dev.activeConnection || "";
    var newIp4 = dev.ip4Config || "";
    var newIp6 = dev.ip6Config || "";

    var changed = (newState !== root._state) || (newType !== root._deviceType) || (newIf !== root._ifname) || (newHw !== root._hwAddr) || (newAcPath !== root._acPath) || (newIp4 !== root._ip4Path) || (newIp6 !== root._ip6Path);

    root._state = newState;
    root._deviceType = newType;
    root._ifname = newIf;
    root._hwAddr = newHw;
    root._acPath = newAcPath;
    root._ip4Path = newIp4;
    root._ip6Path = newIp6;

    root._devReady = true;

    // Type-specific proxies
    if (newType === 1 && !root._wired) {
      root._wired = wiredComponent.createObject(root, {
                                                  "path": root.path
                                                });
    } else if (newType === 2 && !root._wireless) {
      root._wireless = wirelessComponent.createObject(root, {
                                                        "path": root.path
                                                      });
    }

    if (root.connected) {
      root._refreshDetails();
    } else {
      root._clearDetails();
    }

    if (changed) {
      root._emitFacts();
    }
  }

  function _refreshDetails() {
    // Connection display name via Connection.Active.Id (no introspection on
    // that object — getProperty directly)
    if (root._acPath && root._acPath !== "/") {
      var acProxy = acComponent.createObject(root, {
                                               "path": root._acPath
                                             });
      var idReply = acProxy.getProperty("Id");
      if (idReply) {
        idReply.finished.connect(function () {
          if (!idReply.isError && idReply.value !== undefined && idReply.value !== "") {
            if (root._connectionName !== String(idReply.value)) {
              root._connectionName = String(idReply.value);
              root._emitFacts();
            }
          }
          acProxy.destroy();
        });
      } else {
        acProxy.destroy();
      }
    }

    // IPv4 details (Ip4Config does not introspect — getProperty directly)
    if (root._ip4Path && root._ip4Path !== "/") {
      root._readIpConfig(root._ip4Path, false);
    }
    if (root._ip6Path && root._ip6Path !== "/") {
      root._readIpConfig(root._ip6Path, true);
    }
  }

  function _readIpConfig(cfgPath, isV6) {
    var proxy = ipCfgComponent.createObject(root, {
                                              "path": cfgPath
                                            });
    var reply = proxy.call("GetAll", ["org.freedesktop.NetworkManager.IP" + (isV6 ? "6" : "4") + "Config"]);
    if (!reply) {
      proxy.destroy();
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError) {
        var props = reply.value;
        if (props && typeof props === "object") {
          var addrData = props["AddressData"] || [];
          var gateway = props["Gateway"] || "";
          var nsData = props["NameserverData"] || [];

          var addrs = [];
          for (var i = 0; i < addrData.length; i++) {
            if (addrData[i] && addrData[i]["address"]) {
              addrs.push(addrData[i]["address"]);
            }
          }
          var dns = [];
          for (var j = 0; j < nsData.length; j++) {
            if (nsData[j] && nsData[j]["address"]) {
              dns.push(nsData[j]["address"]);
            }
          }

          if (!isV6) {
            root._ipv4 = addrs.length > 0 ? addrs[0] : "";
            root._gateway4 = gateway || "";
            root._dns4 = dns;
          } else {
            root._ipv6 = addrs;
            root._gateway6 = gateway ? [gateway] : [];
            root._dns6 = dns;
          }
          root._emitFacts();
        }
      }
      proxy.destroy();
    });
  }

  function _clearDetails() {
    var had = root._connectionName !== "" || root._ipv4 !== "" || root._ipv6.length > 0;
    root._connectionName = "";
    root._ipv4 = "";
    root._gateway4 = "";
    root._dns4 = [];
    root._ipv6 = [];
    root._gateway6 = [];
    root._dns6 = [];
    root._speed = "";
    root._rate = "";
    root._activeAccessPoint = "";
    if (had) {
      root._emitFacts();
    }
  }

  Component {
    id: wiredComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Device.Wired"
      connection: SystemBus
      onSignalReceived: function (name, args) {
        if (name === "PropertiesChanged") {
          root._refreshWired();
        }
      }
      onIntrospectionCompleted: root._refreshWired()
    }
  }

  Component {
    id: wirelessComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Device.Wireless"
      connection: SystemBus
      onSignalReceived: function (name, args) {
        if (name === "PropertiesChanged") {
          root._refreshWireless();
        }
      }
      onIntrospectionCompleted: root._refreshWireless()
    }
  }

  Component {
    id: acComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.NetworkManager.Connection.Active"
      connection: SystemBus
    }
  }

  Component {
    id: ipCfgComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.DBus.Properties"
      connection: SystemBus
    }
  }

  Component {
    id: apComponent
    DBus {
      service: "org.freedesktop.NetworkManager"
      iface: "org.freedesktop.DBus.Properties"
      connection: SystemBus
    }
  }

  function _refreshWired() {
    if (!root._wired) {
      return;
    }
    var sp = root._wired.speed;
    var s = (sp !== undefined && sp > 0) ? sp + " Mbps" : "";
    if (s !== root._speed) {
      root._speed = s;
      root._emitFacts();
    }
  }

  function _refreshWireless() {
    if (!root._wireless) {
      return;
    }
    var br = root._wireless.bitrate; // Kb/s
    var r = (br !== undefined && br > 0) ? Math.round(br / 100) / 10 + " Mbit/s" : "";
    if (r !== root._rate) {
      root._rate = r;
    }
    var ap = root._wireless.activeAccessPoint || "";
    if (ap !== root._activeAccessPoint) {
      root._activeAccessPoint = ap;
      if (ap && ap !== "/") {
        root._readApDetails(ap);
      } else {
        root._wifiSignal = "";
        root._wifiBand = "";
        root._wifiChannel = "";
        root._wifiWidth = "";
      }
    }
    root._emitFacts();
  }

  // Read the active AccessPoint's signal/band/channel (AccessPoint objects
  // do not introspect — getProperty directly, via the Properties iface).
  function _readApDetails(apPath) {
    var proxy = apComponent.createObject(root, {
                                           "path": apPath
                                         });
    var reply = proxy.call("GetAll", ["org.freedesktop.NetworkManager.AccessPoint"]);
    if (!reply) {
      proxy.destroy();
      return;
    }
    reply.finished.connect(function () {
      if (!reply.isError && reply.value && typeof reply.value === "object") {
        var props = reply.value;
        var strength = props["Strength"];
        var freq = props["Frequency"];
        var width = props["Bandwidth"];

        root._wifiSignal = (strength !== undefined) ? String(strength) : "";
        if (width !== undefined && width > 0) {
          root._wifiWidth = width + " MHz";
        } else {
          root._wifiWidth = "";
        }
        if (freq !== undefined) {
          var f = +freq;
          var band = "";
          if (f >= 5925 && f < 7125) {
            band = "6 GHz";
          } else if (f >= 5150 && f < 5925) {
            band = "5 GHz";
          } else if (f >= 2400 && f < 2500) {
            band = "2.4 GHz";
          } else if (f) {
            band = f + " MHz";
          }
          root._wifiBand = band;
          var channel = root._freqToChannel(f);
          root._wifiChannel = channel ? String(channel) : "";
        }
        root._emitFacts();
      }
      proxy.destroy();
    });
  }

  function _freqToChannel(f) {
    if (f >= 2412 && f <= 2472) {
      return Math.round((f - 2407) / 5);
    }
    if (f >= 5000 && f <= 5900) {
      return Math.round((f - 5000) / 5);
    }
    if (f >= 5955 && f <= 7115) {
      return Math.round((f - 5950) / 5);
    }
    return 0;
  }
}
