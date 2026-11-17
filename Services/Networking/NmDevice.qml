// Interface is reused by sibling records and captures no outer IDs. Bound
// inline components cannot be instantiated from another QML file (Qt contract).
pragma ComponentBehavior: Unbound

import DBus 1.0
import QtQuick

// Retained device bundle. Linked facts are inputs, never child-object reads.
Item {
  id: root
  required property string owner
  required property string path
  property bool live: true
  property var activeFacts: ({})
  property var accessPointFacts: ({})
  property var ip4Facts: ({})
  property var ip6Facts: ({})
  readonly property var references: ({
                                       active: core.facts.ActiveConnection || "/",
                                       ip4: core.facts.Ip4Config || "/",
                                       ip6: core.facts.Ip6Config || "/",
                                       accessPoint: wireless.item ? wireless.item.facts.ActiveAccessPoint || "/" : "/",
                                       accessPoints: wireless.item ? wireless.item.facts.AccessPoints || [] : []
                                     })
  readonly property var facts: {
    var c = core.facts, w = wireless.item ? wireless.item.facts : {}, e = wired.item ? wired.item.facts : {};
    var connected = c.State === 100, ap = accessPointFacts;
    var frequency = ap.Frequency || 0;
    return {
      path: path,
      ready: core.ready,
      ifname: c.Interface || "",
      deviceType: c.DeviceType || 0,
      nmState: c.State || 0,
      connected: connected,
      hwAddr: c.HwAddress || "",
      connectionName: connected ? activeFacts.Id || "" : "",
      activeConnection: references.active,
      speed: connected && e.Speed ? e.Speed + " Mbps" : "",
      rate: connected && w.Bitrate ? Math.round(w.Bitrate / 100) / 10 + " Mbit/s" : "",
      ipv4: connected ? (ip4Facts.addresses || [])[0] || "" : "",
      gateway4: connected ? ip4Facts.Gateway || "" : "",
      dns4: connected ? ip4Facts.nameservers || [] : [],
      ipv6: connected ? ip6Facts.addresses || [] : [],
      gateway6: connected && ip6Facts.Gateway ? [ip6Facts.Gateway] : [],
      dns6: connected ? ip6Facts.nameservers || [] : [],
      activeAccessPoint: references.accessPoint,
      accessPoints: references.accessPoints,
      lastScan: w.LastScan === undefined ? -1 : Number(w.LastScan),
      wifiSignal: connected && ap.Strength !== undefined ? String(ap.Strength) : "",
      wifiBand: !connected || !frequency ? "" : frequency >= 5925 && frequency < 7125 ? "6 GHz" : frequency >= 5150 && frequency < 5925 ? "5 GHz" : frequency >= 2400 && frequency < 2500 ? "2.4 GHz" : frequency + " MHz",
      wifiChannel: connected && frequency ? String(root.channel(frequency) || "") : "",
      wifiWidth: connected && ap.Bandwidth ? ap.Bandwidth + " MHz" : ""
    };
  }
  signal changed
  signal failed(string message)
  onFactsChanged: changed()
  function channel(frequency) {
    if (frequency === 2484)
      return 14;
    if (frequency >= 2412 && frequency <= 2472)
      return Math.round((frequency - 2407) / 5);
    if (frequency >= 5000 && frequency <= 5900)
      return Math.round((frequency - 5000) / 5);
    if (frequency >= 5955 && frequency <= 7115)
      return Math.round((frequency - 5950) / 5);
    return 0;
  }
  function reconcile() {
    core.reconcile();
    if (wired.item)
      wired.item.reconcile();
    if (wireless.item)
      wireless.item.reconcile();
  }
  function requestScan(done) {
    if (!wireless.item) {
      done({
             ok: false,
             error: "Wireless device unavailable"
           });
      return;
    }
    wireless.item.invoke("RequestScan", [
                           {}
                         ], done);
  }
  function retire() {
    live = false;
    core.retire();
    if (wired.item)
      wired.item.retire();
    if (wireless.item)
      wireless.item.retire();
  }
  Interface {
    id: core
    owner: root.owner
    path: root.path
    iface: "org.freedesktop.NetworkManager.Device"
    fields: ["Interface", "DeviceType", "State", "HwAddress", "ActiveConnection", "Ip4Config", "Ip6Config"]
    onEventReceived: function (member, args) {
      if (member === "StateChanged")
        core.apply({
                     State: args[0]
                   });
    }
    onFailed: message => root.failed(message)
  }
  Loader {
    id: wired
    active: root.live && core.facts.DeviceType === 1
    sourceComponent: Interface {
      owner: root.owner
      path: root.path
      iface: "org.freedesktop.NetworkManager.Device.Wired"
      fields: ["Speed", "Carrier"]
      onFailed: message => root.failed(message)
    }
  }
  Loader {
    id: wireless
    active: root.live && core.facts.DeviceType === 2
    sourceComponent: Interface {
      id: wifi
      owner: root.owner
      path: root.path
      iface: "org.freedesktop.NetworkManager.Device.Wireless"
      fields: ["Bitrate", "ActiveAccessPoint", "AccessPoints", "LastScan"]
      signatures: ({
                     RequestScan: "a{sv}"
                   })
      onEventReceived: function (member, args) {
        if (member === "AccessPointAdded" || member === "AccessPointRemoved")
          wifi.membership("AccessPoints", args[0], member === "AccessPointAdded");
      }
      onFailed: message => root.failed(message)
    }
  }

  // Shared retained-interface implementation for the named backend records.
  // Explicit watchers attach before the one seed. Automatic proxy subscriptions
  // and cache reads are disabled: exactly one layer owns invalidations/revisions.
  component Interface: Item {
    id: record
    required property string owner
    required property string path
    required property string iface
    property var fields: []
    property var signatures: ({})
    property bool autoSeed: true
    property bool live: true
    property bool ready: false
    property string errorText: ""
    property var facts: ({})
    property int revision: 0
    property bool reading: false
    property bool dirtyAgain: false
    property var _versions: ({})
    property var _memberships: ({})
    property var _pending: ({})
    property var _invalidAgain: ({})
    signal eventReceived(string member, var args)
    signal failed(string message)
    signal seeded

    DBus {
      id: endpoint
      service: record.owner
      path: record.path
      iface: record.iface
      connection: SystemBus
      propertiesEnabled: false
      signalsEnabled: false
      callTimeout: 10000
      _signatures: record.signatures
    }
    DBusSignalWatcher {
      connection: SystemBus
      service: record.owner
      path: record.path
      iface: record.iface
      enabled: record.live
      onReceived: function (member, args) {
        if (record && record.live)
          record.eventReceived(member, args);
      }
    }
    DBusSignalWatcher {
      connection: SystemBus
      service: record.owner
      path: record.path
      iface: "org.freedesktop.DBus.Properties"
      member: "PropertiesChanged"
      enabled: record.live
      onReceived: function (member, args) {
        if (!record || !record.live || args[0] !== record.iface)
          return;
        record.apply(args[1] || {});
        for (var name of args[2] || [])
          if (record.fields.indexOf(name) !== -1)
            record.invalidate(name);
      }
    }
    Component.onCompleted: Qt.callLater(function () {
      if (record && record.live && record.autoSeed)
        record.reconcile();
    })

    function _error(message) {
      errorText = message;
      failed(message);
    }
    function _value(name, value) {
      // dbusqml preserves a native object-path inside a variant as a boxed
      // value, unlike paths decoded inside ao. Normalize identity once here.
      if (["Connection", "ActiveConnection", "Ip4Config", "Ip6Config", "ActiveAccessPoint"].indexOf(name) !== -1)
        return String(value || "/");
      if (["Devices", "ActiveConnections", "AccessPoints"].indexOf(name) !== -1)
        return Array.from(value || []).map(path => String(path));
      return value;
    }
    function apply(changed) {
      if (!live)
        return;
      var next = Object.assign({}, facts);
      for (var name of fields) {
        if (changed[name] === undefined)
          continue;
        _versions[name] = ++revision;
        next[name] = _value(name, changed[name]);
      }
      facts = next;
    }
    function membership(name, memberPath, present) {
      if (!live)
        return;
      memberPath = String(memberPath);
      revision++;
      if (reading) {
        if (!_memberships[name])
          _memberships[name] = {};
        _memberships[name][memberPath] = {
          present: present,
          revision: revision
        };
      }
      var paths = (facts[name] || []).filter(p => p !== memberPath);
      if (present)
        paths.push(memberPath);
      var next = Object.assign({}, facts);
      next[name] = paths;
      facts = next;
    }
    function reconcile() {
      if (!live)
        return;
      if (reading) {
        dirtyAgain = true;
        return;
      }
      reading = true;
      var started = revision;
      // One GetAll, with explicit signature, independent of introspection. No
      // new proxy is created and no dbusqml cache can race this record's state.
      var reply = SystemBus.asyncCall({
                                        service: owner,
                                        path: path,
                                        iface: "org.freedesktop.DBus.Properties",
                                        member: "GetAll",
                                        arguments: [iface],
                                        signature: "s",
                                        timeout: 10000
                                      });
      reply.finished.connect(function () {
        if (!record || !record.live)
          return;
        record.reading = false;
        if (reply.isError) {
          var retained = Object.assign({}, record.facts);
          for (var field of record.fields)
            if ((record._versions[field] || 0) <= started)
              delete retained[field];
          record.facts = retained;
          record.ready = false;
          record._error(reply.error.message);
        } else {
          var next = Object.assign({}, record.facts), values = reply.value || {};
          for (var name of record.fields) {
            if ((record._versions[name] || 0) > started)
              continue;
            if (values[name] === undefined) {
              delete next[name];
              continue;
            }
            var value = record._value(name, values[name]), events = record._memberships[name];
            if (events) {
              value = Array.from(value || []);
              for (var memberPath in events)
                if (events[memberPath].revision > started) {
                  value = value.filter(p => p !== memberPath);
                  if (events[memberPath].present)
                    value.push(memberPath);
                }
            }
            next[name] = value;
          }
          record.facts = next;
          record.ready = true;
          record.errorText = "";
        }
        // Membership events only protect an in-flight read. Do not accumulate
        // a history of every removed AP/device across a long-running session.
        record._memberships = ({});
        record.seeded();
        if (record.dirtyAgain) {
          record.dirtyAgain = false;
          record.reconcile();
        }
      });
    }
    function invalidate(name) {
      _versions[name] = ++revision;
      var next = Object.assign({}, facts);
      delete next[name];
      facts = next;
      if (_pending[name]) {
        _invalidAgain[name] = true;
        return;
      }
      _readProperty(name);
    }
    function _readProperty(name) {
      if (!live)
        return;
      _pending[name] = true;
      var started = _versions[name];
      var reply = endpoint.getProperty(name);
      reply.finished.connect(function () {
        if (!record || !record.live)
          return;
        delete record._pending[name];
        if (record._versions[name] === started) {
          if (reply.isError)
            record._error(reply.error.message);
          else {
            var next = Object.assign({}, record.facts);
            next[name] = record._value(name, reply.value);
            record.facts = next;
          }
        }
        if (record._invalidAgain[name]) {
          delete record._invalidAgain[name];
          record._readProperty(name);
        }
      });
    }
    function invoke(member, args, done) {
      if (!live) {
        done({
               ok: false,
               error: "NetworkManager owner unavailable"
             });
        return;
      }
      var reply = endpoint.call(member, args);
      if (!reply) {
        done({
               ok: false,
               error: "NetworkManager request unavailable"
             });
        return;
      }
      reply.finished.connect(function () {
        if (!record || !record.live)
          return;
        done(reply.isError ? {
                               ok: false,
                               error: reply.error.message,
                               errorName: reply.error.name
                             } : {
               ok: true,
               value: reply.value,
               values: reply.values
             });
      });
    }
    function retire() {
      live = false;
      facts = ({});
      ready = false;
    }
  }
}
