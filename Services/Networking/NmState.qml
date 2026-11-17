pragma Singleton
pragma ComponentBehavior: Bound

import DBus 1.0
import DBus 1.0 as DBusQML
import QtQuick
import Quickshell
import qs.Commons

// The only NetworkManager inventory/command owner. Facades receive replacement
// facts and compact operation results, never a proxy or a mutable registry.
Singleton {
  id: root
  readonly property bool available: _owner !== "" && !degraded
  property bool degraded: !SystemBus.connected
  property int epoch: 0
  property string errorText: ""
  property var manager: ({})
  property var profiles: ({})
  property var activeConnections: ({})
  property var devices: ({})
  property var accessPoints: ({})
  property var ipConfigs: ({})
  property bool refreshing: false
  property bool refreshPending: false
  property var recordCounts: ({
                                profiles: 0,
                                active: 0,
                                devices: 0,
                                accessPoints: 0,
                                ipConfigs: 0
                              })
  property string _owner: ""
  property int _ownerRevision: 0
  property var _session: null
  property var _profiles: ({})
  property var _active: ({})
  property var _devices: ({})
  property var _aps: ({})
  property var _ips: ({})
  property var _profileEvents: ({})
  property int _profileRevision: 0
  property bool _profilesReading: false
  property var _activeMembers: []
  property var _activeEnded: ({})
  property var _operations: ({})
  property int _operationSerial: 0
  property bool _publishing: false
  property bool _publishAgain: false
  property int _mutationDepth: 0

  DBusSignalWatcher {
    connection: SystemBus
    service: "org.freedesktop.DBus"
    path: "/org/freedesktop/DBus"
    iface: "org.freedesktop.DBus"
    member: "NameOwnerChanged"
    onReceived: function (member, args) {
      if (args[0] !== "org.freedesktop.NetworkManager")
        return;
      root._ownerRevision++;
      root._changeOwner(args[2] || "");
    }
  }
  Connections {
    target: SystemBus
    function onDisconnected() {
      root.degraded = true;
      root.errorText = "System bus disconnected; dbusqml does not reconnect automatically. Reload the shell after restoring the bus.";
      root._changeOwner("");
    }
  }
  Component.onCompleted: Qt.callLater(_resolveOwner)
  function _resolveOwner() {
    if (degraded)
      return;
    var revision = _ownerRevision;
    var reply = SystemBus.asyncCall({
                                      service: "org.freedesktop.DBus",
                                      path: "/org/freedesktop/DBus",
                                      iface: "org.freedesktop.DBus",
                                      member: "GetNameOwner",
                                      arguments: ["org.freedesktop.NetworkManager"],
                                      signature: "s",
                                      timeout: 10000
                                    });
    reply.finished.connect(function () {
      if (root.degraded || revision !== root._ownerRevision)
        return;
      root._changeOwner(reply.isError ? "" : String(reply.value));
    });
  }
  function _changeOwner(owner) {
    if (owner === _owner)
      return;
    epoch++;
    _owner = "";
    for (var id of Object.keys(_operations))
      _settle(id, false, "NetworkManager owner changed");
    if (_session) {
      _session.retire();
      for (var registry of [_profiles, _active, _devices, _aps, _ips])
        for (var path in registry)
          registry[path].retire();
      _session.destroy();
      _session = null;
    }
    _profiles = ({});
    _active = ({});
    _devices = ({});
    _aps = ({});
    _ips = ({});
    _profileEvents = ({});
    _profileRevision = 0;
    _profilesReading = false;
    _activeMembers = [];
    _activeEnded = ({});
    manager = ({});
    profiles = ({});
    activeConnections = ({});
    devices = ({});
    accessPoints = ({});
    ipConfigs = ({});
    recordCounts = ({
                      profiles: 0,
                      active: 0,
                      devices: 0,
                      accessPoints: 0,
                      ipConfigs: 0
                    });
    refreshing = false;
    refreshPending = false;
    if (!owner || degraded)
      return;
    _owner = owner;
    errorText = "";
    _session = sessionFactory.createObject(root, {
                                             owner: owner,
                                             generation: epoch
                                           });
    if (!_session) {
      _error("Cannot create NetworkManager session: " + sessionFactory.errorString());
      return;
    }
    _listProfiles();
  }
  Component {
    id: sessionFactory
    Scope {
      id: session
      required property string owner
      required property int generation
      property alias manager: nmManager
      property alias settings: nmSettings
      function retire() {
        nmManager.retire();
        nmSettings.retire();
      }
      NmDevice.Interface {
        id: nmManager
        owner: session.owner
        path: "/org/freedesktop/NetworkManager"
        iface: "org.freedesktop.NetworkManager"
        fields: ["Devices", "ActiveConnections", "Connectivity", "WirelessEnabled", "WirelessHardwareEnabled", "State"]
        signatures: ({
                       ActivateConnection: "ooo",
                       AddAndActivateConnection: "a{sa{sv}}oo",
                       DeactivateConnection: "o"
                     })
        onFactsChanged: {
          if (session.generation !== root.epoch)
            return;
          root.manager = root._snapshot(facts);
          root._syncManager();
        }
        onEventReceived: function (member, args) {
          if (member === "DeviceAdded" || member === "DeviceRemoved")
            nmManager.membership("Devices", args[0], member === "DeviceAdded");
          else if (member === "StateChanged")
            nmManager.apply({
                              State: args[0]
                            });
        }
        onFailed: message => root._error(message)
      }
      NmDevice.Interface {
        id: nmSettings
        owner: session.owner
        path: "/org/freedesktop/NetworkManager/Settings"
        iface: "org.freedesktop.NetworkManager.Settings"
        autoSeed: false
        onEventReceived: function (member, args) {
          if (session.generation !== root.epoch)
            return;
          if (member === "NewConnection")
            root._profileMembership(args[0], true);
          else if (member === "ConnectionRemoved")
            root._profileMembership(args[0], false);
        }
      }
    }
  }
  Component {
    id: profileFactory
    NmProfile {
      onChanged: root._schedulePublish()
      onRemoved: root._profileMembership(path, false)
    }
  }
  Component {
    id: activeFactory
    NmActiveConnection {
      onChanged: root._schedulePublish()
      onFailed: message => root._error(message)
    }
  }
  Component {
    id: deviceFactory
    NmDevice {
      onChanged: root._schedulePublish()
      onFailed: message => root._error(message)
    }
  }
  Component {
    id: apFactory
    NmAccessPoint {
      onChanged: root._schedulePublish()
      onFailed: message => root._error(message)
    }
  }
  Component {
    id: ipFactory
    NmIpConfig {
      onChanged: root._schedulePublish()
      onFailed: message => root._error(message)
    }
  }
  function _schedulePublish() {
    Qt.callLater(_publish);
  }
  function _error(message) {
    errorText = message;
    Logger.w("NetworkManager", message);
  }
  function _snapshot(facts) {
    return JSON.parse(JSON.stringify(facts));
  }
  function _usable(path) {
    return typeof path === "string" && path !== "" && path !== "/";
  }
  function _ensure(registry, factory, path, extra) {
    if (!available || !_session || !_usable(path) || registry[path])
      return;
    _mutationDepth++;
    var record = factory.createObject(_session, Object.assign({
                                                                owner: _owner,
                                                                path: path
                                                              }, extra || {}));
    if (record)
      registry[path] = record;
    else
      _error("Cannot create NetworkManager record: " + factory.errorString());
    _mutationDepth--;
  }
  function _retire(registry, path) {
    var record = registry[path];
    if (!record)
      return;
    _mutationDepth++;
    delete registry[path];
    record.retire();
    record.destroy();
    _mutationDepth--;
  }
  function _profileMembership(path, present) {
    if (!available)
      return;
    path = String(path);
    if (_profilesReading)
      _profileEvents[path] = {
        revision: ++_profileRevision,
        present: present
      };
    if (present)
      _ensure(_profiles, profileFactory, path);
    else {
      _retire(_profiles, path);
      for (var id in _operations)
        if (_operations[id].kind === "delete" && _operations[id].path === path)
          _operations[id].observed = true;
    }
    _publish();
  }
  function _listProfiles() {
    if (!_session || !available)
      return;
    if (_profilesReading) {
      refreshPending = true;
      return;
    }
    _profilesReading = true;
    refreshing = true;
    var generation = epoch, started = _profileRevision;
    _session.settings.invoke("ListConnections", [], function (result) {
      if (generation !== root.epoch)
        return;
      root._profilesReading = false;
      if (!result.ok)
        root._error(result.error);
      else {
        var paths = Array.from(result.value || []);
        for (var path in root._profileEvents)
          if (root._profileEvents[path].revision > started) {
            paths = paths.filter(p => p !== path);
            if (root._profileEvents[path].present)
              paths.push(path);
          }
        for (var old in root._profiles)
          if (paths.indexOf(old) === -1)
            root._retire(root._profiles, old);
        for (var p of paths)
          root._ensure(root._profiles, profileFactory, p);
      }
      root._profileEvents = ({});
      root._publish();
    });
  }
  function reconcileProfiles() {
    if (!available)
      return;
    if (refreshing) {
      refreshPending = true;
      return;
    }
    for (var path in _profiles)
      _profiles[path].reconcile();
    _listProfiles();
  }
  function reconcileDevice(path) {
    var device = _devices[path];
    if (!device)
      return;
    device.reconcile();
    var refs = device.references;
    if (_active[refs.active])
      _active[refs.active].reconcile();
    if (_aps[refs.accessPoint])
      _aps[refs.accessPoint].reconcile();
    if (_ips["4:" + refs.ip4])
      _ips["4:" + refs.ip4].reconcile();
    if (_ips["6:" + refs.ip6])
      _ips["6:" + refs.ip6].reconcile();
  }
  function _syncManager() {
    var paths = manager.Devices || [];
    for (var old in _devices)
      if (paths.indexOf(old) === -1)
        _retire(_devices, old);
    for (var path of paths)
      _ensure(_devices, deviceFactory, path);
    var active = manager.ActiveConnections || [];
    for (var previous of _activeMembers)
      if (active.indexOf(previous) === -1)
        _activeEnded[previous] = true;
    _activeMembers = Array.from(active);
    for (var p of active) {
      delete _activeEnded[p];
      _ensure(_active, activeFactory, p);
    }
    _publish();
  }
  function _publish() {
    if (!available || !_session)
      return;
    if (_publishing || _mutationDepth > 0) {
      _publishAgain = true;
      return;
    }
    _publishing = true;
    var activeRefs = {}, apRefs = {}, ipRefs = {}, path;
    for (var p of _activeMembers)
      activeRefs[p] = true;
    for (var id in _operations) {
      var operation = _operations[id];
      if (operation.kind === "activate" && operation.activePath && !_activeEnded[operation.activePath])
        activeRefs[operation.activePath] = true;
    }
    for (path in _devices) {
      var refs = _devices[path].references;
      if (_usable(refs.active) && !_activeEnded[refs.active])
        activeRefs[refs.active] = true;
      for (var ap of refs.accessPoints || [])
        if (_usable(ap))
          apRefs[ap] = true;
      if (_usable(refs.accessPoint))
        apRefs[refs.accessPoint] = true;
      if (_usable(refs.ip4))
        ipRefs["4:" + refs.ip4] = {
          path: refs.ip4,
          ipv6: false
        };
      if (_usable(refs.ip6))
        ipRefs["6:" + refs.ip6] = {
          path: refs.ip6,
          ipv6: true
        };
    }
    for (path in activeRefs)
      _ensure(_active, activeFactory, path);
    for (path in _active) {
      if (!activeRefs[path]) {
        _retire(_active, path);
        continue;
      }
      var activeFacts = _active[path].facts;
      if (_usable(activeFacts.Ip4Config))
        ipRefs["4:" + activeFacts.Ip4Config] = {
          path: activeFacts.Ip4Config,
          ipv6: false
        };
      if (_usable(activeFacts.Ip6Config))
        ipRefs["6:" + activeFacts.Ip6Config] = {
          path: activeFacts.Ip6Config,
          ipv6: true
        };
    }
    for (path in apRefs)
      _ensure(_aps, apFactory, path);
    for (path in _aps)
      if (!apRefs[path])
        _retire(_aps, path);
    for (path in ipRefs)
      _ensure(_ips, ipFactory, path, {
                path: ipRefs[path].path,
                ipv6: ipRefs[path].ipv6
              });
    for (path in _ips)
      if (!ipRefs[path])
        _retire(_ips, path);
    var profileSnapshot = {}, activeSnapshot = {}, deviceSnapshot = {}, apSnapshot = {}, ipSnapshot = {};
    var pendingProfiles = _profilesReading;
    for (path in _profiles) {
      if (_profiles[path].ready)
        profileSnapshot[path] = _snapshot(_profiles[path].facts);
      if (_profiles[path].reading)
        pendingProfiles = true;
    }
    for (path in _active)
      activeSnapshot[path] = _snapshot(_active[path].facts);
    for (path in _aps)
      apSnapshot[path] = _snapshot(_aps[path].facts);
    for (path in _ips)
      ipSnapshot[path] = _snapshot(_ips[path].facts);
    for (path in _devices) {
      var device = _devices[path], links = device.references;
      _assignLinks(device, "activeFacts", activeSnapshot[links.active] || {});
      _assignLinks(device, "accessPointFacts", apSnapshot[links.accessPoint] || {});
      _assignLinks(device, "ip4Facts", ipSnapshot["4:" + links.ip4] || {});
      _assignLinks(device, "ip6Facts", ipSnapshot["6:" + links.ip6] || {});
      deviceSnapshot[path] = _snapshot(device.facts);
    }
    profiles = profileSnapshot;
    activeConnections = activeSnapshot;
    devices = deviceSnapshot;
    accessPoints = apSnapshot;
    ipConfigs = ipSnapshot;
    recordCounts = ({
                      profiles: Object.keys(_profiles).length,
                      active: Object.keys(_active).length,
                      devices: Object.keys(_devices).length,
                      accessPoints: Object.keys(_aps).length,
                      ipConfigs: Object.keys(_ips).length
                    });
    refreshing = pendingProfiles;
    _updateOperations();
    // Keep removal history only while a device still references it or a
    // request acceptance can race it. Counts return to baseline after cycles.
    var awaitingReply = Object.values(_operations).some(op => op.kind === "activate" && !op.accepted);
    if (!awaitingReply)
      for (path in _activeEnded) {
        if (!Object.values(_devices).some(dev => dev.references.active === path))
          delete _activeEnded[path];
      }
    _publishing = false;
    if (_publishAgain) {
      _publishAgain = false;
      Qt.callLater(_publish);
    }
    if (!refreshing && refreshPending) {
      refreshPending = false;
      Qt.callLater(reconcileProfiles);
    }
  }
  function _assignLinks(device, property, value) {
    if (JSON.stringify(device[property]) !== JSON.stringify(value))
      device[property] = value;
  }
  function profileByUuid(uuid) {
    for (var path in profiles)
      if (profiles[path].uuid === uuid)
        return profiles[path];
    return null;
  }
  function profileForSsid(ssid) {
    var candidates = Object.values(profiles).filter(p => p.type === "802-11-wireless" && p.ssid === ssid);
    candidates.sort((a, b) => a.uuid.localeCompare(b.uuid) || a.path.localeCompare(b.path));
    var activeUuids = Object.values(activeConnections).filter(a => a.State === 2).map(a => a.Uuid);
    return candidates.find(p => activeUuids.indexOf(p.uuid) !== -1) || candidates[0] || null;
  }
  function _begin(kind, done, extra) {
    var id = String(++_operationSerial);
    var operation = Object.assign({
                                    id: id,
                                    epoch: epoch,
                                    kind: kind,
                                    callback: done,
                                    accepted: false
                                  }, extra || {});
    _operations[id] = operation;
    operation.timer = operationDeadline.createObject(root, {
                                                       operationId: id
                                                     });
    if (!available)
      Qt.callLater(function () {
        root._settle(id, false, "NetworkManager unavailable");
      });
    return operation;
  }
  Component {
    id: operationDeadline
    Timer {
      required property string operationId
      interval: 45000
      running: true
      repeat: false
      onTriggered: root._settle(operationId, false, "NetworkManager operation timed out")
    }
  }
  function _accepted(operation) {
    if (!_operations[operation.id] || operation.epoch !== epoch)
      return;
    operation.accepted = true;
    if (operation.callback)
      operation.callback({
                           id: operation.id,
                           status: "accepted",
                           ok: true
                         });
    _publish();
  }
  function _settle(id, ok, message) {
    var operation = _operations[id];
    if (!operation)
      return;
    delete _operations[id];
    operation.timer.stop();
    operation.timer.destroy();
    if (operation.callback)
      operation.callback({
                           id: id,
                           status: ok ? "completed" : "error",
                           ok: ok,
                           error: message || ""
                         });
  }
  function _updateOperations() {
    for (var id of Object.keys(_operations)) {
      var operation = _operations[id];
      if (operation.kind === "delete" && operation.observed) {
        _settle(id, true, "");
        continue;
      }
      if (operation.kind === "scan" && !devices[operation.path]) {
        _settle(id, false, "Wireless device removed");
        continue;
      }
      if (!operation.accepted)
        continue;
      if (operation.kind === "activate") {
        var active = activeConnections[operation.activePath];
        if (_activeEnded[operation.activePath] || (active && active.State === 4))
          _settle(id, false, "Activation ended" + (active && active.Reason ? " (reason " + active.Reason + ")" : ""));
        else if (active && active.State === 2)
          _settle(id, true, "");
      } else if (operation.kind === "deactivate") {
        if (operation.paths.every(path => !activeConnections[path] || activeConnections[path].State === 4))
          _settle(id, true, "");
      } else if (operation.kind === "delete") {
        if (operation.observed || !_profiles[operation.path])
          _settle(id, true, "");
      } else if (operation.kind === "scan") {
        var device = devices[operation.path];
        if (!device)
          _settle(id, false, "Wireless device removed");
        else if (device.lastScan > operation.lastScan)
          _settle(id, true, "");
      }
    }
  }
  function activate(path, device, specific, done) {
    var operation = _begin("activate", done, {
                             path: path,
                             activePath: ""
                           });
    if (!available)
      return operation.id;
    _session.manager.invoke("ActivateConnection", [new DBusQML.objectPath(path), new DBusQML.objectPath(device || "/"), new DBusQML.objectPath(specific || "/")], function (result) {
      if (!root._operations[operation.id])
        return;
      if (!result.ok) {
        root._settle(operation.id, false, result.error);
        return;
      }
      operation.activePath = String(result.value || "");
      if (!root._usable(operation.activePath)) {
        root._settle(operation.id, false, "Activation returned no active path");
        return;
      }
      root._accepted(operation);
    });
    return operation.id;
  }
  function addAndActivate(settings, device, specific, done) {
    var operation = _begin("activate", done, {
                             activePath: ""
                           });
    if (!available)
      return operation.id;
    _session.manager.invoke("AddAndActivateConnection", [settings, new DBusQML.objectPath(device), new DBusQML.objectPath(specific || "/")], function (result) {
      if (!root._operations[operation.id])
        return;
      if (!result.ok) {
        root._settle(operation.id, false, result.error);
        return;
      }
      var values = result.values || result.value || [];
      operation.activePath = String(values[1] || "");
      if (!root._usable(operation.activePath)) {
        root._settle(operation.id, false, "Activation returned no active path");
        return;
      }
      root._accepted(operation);
    });
    return operation.id;
  }
  function _eapMethods(method: string): list<string> {
    // The a{sv} slot supplies the variant, not its payload's element type.
    // Return a native string list so NM receives as, never inferred av/v(v(as)).
    return [method];
  }
  function activateWifi(ssid, password, hidden, security, identity, enterprise, device, specific, done) {
    var settings = {
      connection: {
        id: ssid,
        type: "802-11-wireless",
        autoconnect: true
      },
      "802-11-wireless": {
        ssid: new DBusQML.bytes(ssid),
        mode: "infrastructure",
        hidden: hidden
      },
      ipv4: {
        method: "auto"
      },
      ipv6: {
        method: "auto"
      }
    };
    if (security && security !== "open") {
      if (security === "wep")
        settings["802-11-wireless-security"] = {
          "key-mgmt": "none",
          "wep-key0": password
        };
      else if (security.indexOf("eap") !== -1) {
        settings["802-11-wireless-security"] = {
          "key-mgmt": "wpa-eap"
        };
        var eap = {
          eap: _eapMethods(enterprise.eap || "peap"),
          "phase2-auth": enterprise.phase2 || "mschapv2",
          identity: identity,
          password: password
        };
        if (enterprise.anonIdentity)
          eap["anonymous-identity"] = enterprise.anonIdentity;
        if (enterprise.caCert) {
          var certificate = enterprise.caCert;
          if (certificate.indexOf("/") === 0)
            certificate = "file://" + certificate;
          eap["ca-cert"] = new DBusQML.bytes(certificate + "\0");
        }
        settings["802-1x"] = eap;
      } else
        settings["802-11-wireless-security"] = {
          "key-mgmt": security === "sae" ? "sae" : "wpa-psk",
          psk: password
        };
    }
    return addAndActivate(settings, device, specific, done);
  }
  function deactivate(uuid, done) {
    var paths = Object.keys(activeConnections).filter(p => activeConnections[p].Uuid === uuid && activeConnections[p].State !== 4);
    return deactivatePaths(paths, done);
  }
  function deactivatePaths(paths, done) {
    var operation = _begin("deactivate", done, {
                             paths: paths,
                             replies: paths.length
                           });
    if (!available)
      return operation.id;
    if (!paths.length) {
      Qt.callLater(function () {
        root._settle(operation.id, false, "No active connection");
      });
      return operation.id;
    }
    for (var path of paths)
      _session.manager.invoke("DeactivateConnection", [new DBusQML.objectPath(path)], function (result) {
        if (!root._operations[operation.id])
          return;
        if (!result.ok) {
          root._settle(operation.id, false, result.error);
          return;
        }
        operation.replies--;
        if (operation.replies === 0)
          root._accepted(operation);
      });
    return operation.id;
  }
  function deleteProfile(path, done) {
    var operation = _begin("delete", done, {
                             path: path,
                             observed: false
                           });
    if (!available)
      return operation.id;
    if (!_profiles[path]) {
      Qt.callLater(function () {
        root._settle(operation.id, false, "Saved profile unavailable");
      });
      return operation.id;
    }
    _profiles[path].deleteProfile(function (result) {
      if (!root._operations[operation.id])
        return;
      if (!result.ok)
        root._settle(operation.id, false, result.error);
      else
        root._accepted(operation);
    });
    return operation.id;
  }
  function requestScan(path, done) {
    var operation = _begin("scan", done, {
                             path: path,
                             lastScan: devices[path] ? devices[path].lastScan : -1
                           });
    if (!available)
      return operation.id;
    if (!_devices[path]) {
      Qt.callLater(function () {
        root._settle(operation.id, false, "Wireless device unavailable");
      });
      return operation.id;
    }
    _devices[path].requestScan(function (result) {
      if (!root._operations[operation.id])
        return;
      if (!result.ok)
        root._settle(operation.id, false, result.error);
      else
        root._accepted(operation);
    });
    return operation.id;
  }
  function setWirelessEnabled(enabled, done) {
    var operation = _begin("radio", done);
    if (!available)
      return operation.id;
    var reply = SystemBus.asyncCall({
                                      service: _owner,
                                      path: "/org/freedesktop/NetworkManager",
                                      iface: "org.freedesktop.DBus.Properties",
                                      member: "Set",
                                      arguments: ["org.freedesktop.NetworkManager", "WirelessEnabled", new DBusQML.variant(enabled)],
                                      signature: "ssv",
                                      timeout: 10000
                                    });
    reply.finished.connect(function () {
      if (!root._operations[operation.id])
        return;
      root._settle(operation.id, !reply.isError, reply.isError ? reply.error.message : "");
    });
    return operation.id;
  }
}
