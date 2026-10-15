pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import "../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons

Singleton {
  id: root

  function init() {
    Logger.i("FileChooserClient", "Service started");
  }

  // All or nothing: one unusable URI fails the whole response, so the caller
  // never receives a partial or empty path list. Returns null on failure.
  function urisToPaths(uris) {
    var paths = [];
    for (var i = 0; i < uris.length; i++) {
      var converted = PortalPaths.uriToPath(uris[i]);
      if (!converted.ok) {
        Logger.w("FileChooserClient", "Portal returned an unusable URI: " + converted.error);
        return null;
      }
      paths.push(converted.path);
    }
    return paths;
  }

  function openPicker(options, onAccepted, onCancelled) {
    var opts = ({});
    if (options.directory)
      opts.directory = true;
    if (options.multiple)
      opts.multiple = true;
    if (options.filters && options.filters.length > 0) {
      var filters = [];
      for (var i = 0; i < options.filters.length; i++)
        filters.push([options.filters[i], [[0, options.filters[i]]]]);
      opts.filters = filters;
    }
    if (options.initialPath) {
      var initial = PortalPaths.encodeBytePath(options.initialPath);
      if (initial.ok)
        opts.current_folder = new DBusQML.variant(new Uint8Array(initial.bytes), "ay");
      else
        Logger.w("FileChooserClient", "Leaving out initialPath: " + initial.error);
    }

    var reply = frontend.call("OpenFile", ["", options.title || "", opts]);
    reply.finished.connect(function () {
      if (reply.isError) {
        Logger.w("FileChooserClient", "OpenFile failed: " + reply.error.message);
        if (onCancelled)
          onCancelled();
        return;
      }
      root.watchRequest(String(reply.value), onAccepted, onCancelled);
    });
  }

  function watchRequest(handle, onAccepted, onCancelled) {
    watcherFactory.createObject(root, {
                                  handle: handle,
                                  onAccepted: onAccepted,
                                  onCancelled: onCancelled
                                });
  }

  DBus {
    id: frontend
    service: "org.freedesktop.portal.desktop"
    path: "/org/freedesktop/portal/desktop"
    iface: "org.freedesktop.portal.FileChooser"
    connection: SessionBus
  }

  Component {
    id: watcherFactory

    Item {
      id: watcher

      property string handle: ""
      property var onAccepted: null
      property var onCancelled: null

      DBus {
        service: "org.freedesktop.portal.desktop"
        path: watcher.handle
        iface: "org.freedesktop.portal.Request"
        connection: SessionBus
        signalsEnabled: true

        onSignalReceived: (name, args) => {
          if (name !== "Response")
            return;
          var response = args[0];
          var results = args[1];
          var paths = response === 0 && results && results.uris ? FileChooserClient.urisToPaths(results.uris) : null;
          if (paths !== null && paths.length > 0) {
            if (watcher.onAccepted)
              watcher.onAccepted(paths);
          } else {
            if (watcher.onCancelled)
              watcher.onCancelled();
          }
          watcher.destroy();
        }
      }
    }
  }
}
