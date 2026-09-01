// xdg-desktop-portal backend for org.freedesktop.impl.portal.Inhibit (v3).
//
// Serves Inhibit, CreateMonitor and QueryEndResponse on the session bus
// under org.freedesktop.impl.portal.desktop.atmosphera, discovered via
// Portals/atmosphera.portal. Inhibit requests are granted and mapped
// onto IdleInhibitorService (Wayland idle-inhibit, systemd-inhibit
// fallback) — which blocks idle-triggered lock and idle-triggered
// suspend but never manual suspend/logout. CreateMonitor sessions emit
// StateChanged snapshots; screensaver-active mirrors the shell lock
// screen, session-state is always 1 (Running) because nothing on
// niri+logind emits Query End/Ending. Per-call Request/Session adaptors
// follow the FileChooser pattern.
//
// NOTE: keep curly braces OUT of comments in this file — the quickshell
// qmlscanner mishandles braces inside comments and silently breaks
// singleton instantiation (quickshell bug; observed on quickshell 0.3.1).

pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Power
import qs.Services.UI

Singleton {
  id: root

  // request handle (o) -> { adaptor, inhibitorId, appId }
  property var activeInhibits: ({})
  // session handle (o) -> { session, request, appId }
  property var activeMonitors: ({})

  // The lock screen is the shell's screensaver equivalent.
  readonly property bool screensaverActive: PanelService.lockScreen ? PanelService.lockScreen.active : false

  function init() {
    Logger.i("InhibitPortal", "Service started");
  }

  DBusAdaptor {
    id: adaptor
    service: "org.freedesktop.impl.portal.desktop.atmosphera"
    path: "/org/freedesktop/portal/desktop"
    iface: "org.freedesktop.impl.portal.Inhibit"
    connection: SessionBus

    function inhibit(handle, appId, window, flags, options) {
      root.beginInhibit(handle, appId, options);
      // falls through to a void reply -> daemon emits frontend Response(0)
    }

    function createMonitor(handle, sessionHandle, appId, window) {
      return root.beginMonitor(handle, sessionHandle, appId);
    }

    function queryEndResponse(sessionHandle) {
      // No session manager on niri emits Query End, so a well-formed
      // client can never have an ack to send us. Accept and log.
      Logger.d("InhibitPortal", "QueryEndResponse:", sessionHandle);
    }
  }

  function appLabel(appId) {
    if (appId && appId !== "") {
      try {
        if (typeof DesktopEntries !== "undefined" && DesktopEntries.heuristicLookup) {
          var entry = DesktopEntries.heuristicLookup(appId);
          if (entry && entry.name)
            return entry.name;
        }
      } catch (e) {}
      return appId;
    }
    return I18n.tr("toast.inhibit.unknown-app");
  }

  function hasInhibitForApp(appId) {
    var map = root.activeInhibits;
    for (var h in map)
      if (map[h].appId === appId)
        return true;
    return false;
  }

  // --- Inhibit ---

  function beginInhibit(handle, appId, options) {
    var reason = (options && options.reason !== undefined) ? String(options.reason) : "";
    var inhibitorId = "portal:" + handle;
    var firstForApp = !root.hasInhibitForApp(appId);

    IdleInhibitorService.addInhibitor(inhibitorId, reason !== "" ? reason : root.appLabel(appId));

    var map = root.activeInhibits;
    map[handle] = ({
                     "adaptor": requestFactory.createObject(root, {
                                                              "handle": handle,
                                                              "_onClosed": function () {
                                                                root.releaseInhibit(handle);
                                                              }
                                                            }),
                     "inhibitorId": inhibitorId,
                     "appId": appId
                   });
    root.activeInhibits = map;

    if (firstForApp)
      root.toastGranted(appId, reason);
  }

  function releaseInhibit(handle) {
    var map = root.activeInhibits;
    var entry = map[handle];
    if (!entry) {
      Logger.w("InhibitPortal", "Close for unknown inhibit handle:", handle);
      return;
    }
    IdleInhibitorService.removeInhibitor(entry.inhibitorId);
    entry.adaptor.destroy();
    delete map[handle];
    root.activeInhibits = map;
  }

  function toastGranted(appId, reason) {
    var app = root.appLabel(appId);
    var body = reason !== "" ? I18n.tr("toast.inhibit.description-reason", {
                                         "app": app,
                                         "reason": reason
                                       }) : I18n.tr("toast.inhibit.description", {
                                                      "app": app
                                                    });
    ToastService.showNotice(I18n.tr("tooltips.keep-awake"), body, "keep-awake-on");
  }

  // --- CreateMonitor / StateChanged ---

  function beginMonitor(handle, sessionHandle, appId) {
    if (root.activeMonitors[sessionHandle]) {
      Logger.w("InhibitPortal", "Duplicate monitor session:", sessionHandle);
      return new DBusQML.uint32(2);
    }

    var request = requestFactory.createObject(root, {
                                                "handle": handle,
                                                "_onClosed": function () {
                                                  root.releaseMonitor(sessionHandle);
                                                }
                                              });
    var session = sessionFactory.createObject(root, {
                                                "_sessionHandle": sessionHandle,
                                                "_onClosed": function () {
                                                  root.releaseMonitor(sessionHandle);
                                                }
                                              });

    var map = root.activeMonitors;
    map[sessionHandle] = ({
                            "session": session,
                            "request": request,
                            "appId": appId
                          });
    root.activeMonitors = map;

    // Initial snapshot, mirroring the gtk backend. Deferred one tick so
    // the reply is dispatched first — the daemon cannot route a
    // StateChanged for a session it has not finished exporting.
    Qt.callLater(function () {
      root.emitState(sessionHandle);
    });

    return new DBusQML.uint32(0);
  }

  function releaseMonitor(sessionHandle) {
    var map = root.activeMonitors;
    var entry = map[sessionHandle];
    if (!entry) {
      Logger.w("InhibitPortal", "Close for unknown monitor session:", sessionHandle);
      return;
    }
    entry.session.destroy();
    entry.request.destroy();
    delete map[sessionHandle];
    root.activeMonitors = map;
  }

  function emitState(sessionHandle) {
    // session-state is always 1 (Running): nothing on niri+logind
    // emits Query End / Ending. Explicit u-typing — a plain JS number
    // would marshal as i and the daemon would drop the key.
    adaptor.emitSignal("StateChanged", [new DBusQML.objectPath(sessionHandle), ({
                                                                                  "screensaver-active": root.screensaverActive,
                                                                                  "session-state": new DBusQML.variant(1, "u")
                                                                                })]);
  }

  onScreensaverActiveChanged: {
    for (var h in root.activeMonitors)
    root.emitState(h);
  }

  // --- Per-call object factories ---

  Component {
    id: requestFactory

    DBusAdaptor {
      property string handle: ""
      property var _onClosed: null

      path: handle
      iface: "org.freedesktop.impl.portal.Request"
      connection: SessionBus

      function close() {
        if (_onClosed)
          _onClosed();
      }
    }
  }

  Component {
    id: sessionFactory

    DBusAdaptor {
      // Underscore-prefixed: the daemon creates its impl-Session proxy
      // with G_DBUS_PROXY_FLAGS_NONE, so it DOES call GetAll on us —
      // keep bookkeeping out of the served property set.
      property string _sessionHandle: ""
      property var _onClosed: null

      path: _sessionHandle
      iface: "org.freedesktop.impl.portal.Session"
      connection: SessionBus

      function close() {
        if (_onClosed)
          _onClosed();
      }
    }
  }

  // Anti-leak on shell live-reload: a reloaded singleton's Request
  // adaptors vanish, so its inhibitors could never be released.
  Component.onDestruction: {
    var map = activeInhibits;
    for (var h in map)
    IdleInhibitorService.removeInhibitor(map[h].inhibitorId);
  }
}
