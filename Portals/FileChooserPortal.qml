// One deferred backend call, FileRequest and window per portal handle.
pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Files
import qs.Modules.FileChooser

Singleton {
  id: root
  property var activeRequests: ({})

  function init() { Logger.i("FileChooserPortal", "Service started"); }

  DBusAdaptor {
    id: adaptor
    service: "org.freedesktop.impl.portal.desktop.atmosphera"
    path: "/org/freedesktop/portal/desktop"
    captureSubtree: true
    iface: "org.freedesktop.impl.portal.FileChooser"
    connection: SessionBus

    function openFile(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, appId, parentWindow, title, options, "open", adaptor.holdReply());
    }
    function saveFile(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, appId, parentWindow, title, options, "save", adaptor.holdReply());
    }
    function saveFiles(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, appId, parentWindow, title, options, "saveFiles", adaptor.holdReply());
    }
    onNameLost: root.cancelAll()
  }

  function beginRequest(handle, appId, parentWindow, title, options, method, reply) {
    if (activeRequests[handle]) {
      reply.sendError("org.freedesktop.portal.Error.InvalidArgument", "Request handle already exists");
      return;
    }
    var screen = CompositorService.getFocusedScreen() || Quickshell.screens[0];
    // Parent identifiers and modal are accepted. The overlay is focused, stays
    // above the app and is centred on its focused output (best effort).
    var entry = requestFactory.createObject(root, {
      handle: handle, appId: appId, parentWindow: parentWindow, method: method,
      options: Object.assign({}, options || {}, {title: title}), reply: reply,
      caller: reply.callerService(), output: screen || null
    });
    if (!entry) {
      reply.send([2, {}]);
      return;
    }
    activeRequests = Object.assign({}, activeRequests, {[handle]: entry});
    if (!screen)
      entry.request.fail("No output available");
  }

  function finish(handle, response, results) {
    var entry = activeRequests[handle];
    if (!entry || entry.replied)
      return;
    entry.replied = true;
    var payload = {};
    if (response === 0) {
      payload.uris = new DBusQML.variant(results.uris, "as");
      payload.writable = new DBusQML.variant(results.writable, "b");
      payload.choices = new DBusQML.variant(results.choices, "a(ss)");
      if (results.current_filter)
        payload.current_filter = new DBusQML.variant(results.current_filter, "(sa(us))");
    }
    entry.reply.send([response, payload]);
    var remaining = Object.assign({}, activeRequests);
    delete remaining[handle];
    activeRequests = remaining;
    // destroy() is deferred: FileRequest finishes its success/memory transition
    // before its owner and the per-handle adaptor disappear.
    entry.destroy();
  }

  function cancelAll() {
    for (var handle of Object.keys(activeRequests))
      activeRequests[handle].request.cancel();
  }

  Component {
    id: requestFactory
    Scope {
      id: entry
      required property string handle
      required property string appId
      required property string parentWindow
      required property string method
      required property var options
      required property var reply
      required property string caller
      required property var output
      property bool replied: false
      readonly property FileRequest request: fileRequest

      FileRequest {
        id: fileRequest
        method: entry.method
        appId: entry.appId
        options: entry.options
        onFinished: (response, results) => root.finish(entry.handle, response, results)
      }
      DBusAdaptor {
        path: entry.handle
        iface: "org.freedesktop.impl.portal.Request"
        connection: SessionBus
        allowedSender: entry.caller
        function close() { fileRequest.cancel(); }
      }
      DBusServiceWatcher {
        connection: SessionBus
        service: entry.caller
        onOwnerChanged: (oldOwner, newOwner) => { if (oldOwner && oldOwner !== newOwner) fileRequest.cancel(); }
      }
      Loader {
        active: entry.output !== null
        sourceComponent: FileChooserWindow { request: fileRequest; screen: entry.output }
      }
      Component.onDestruction: fileRequest.cancel()
    }
  }
}
