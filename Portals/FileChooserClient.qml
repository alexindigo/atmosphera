pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  function init() {
    Logger.i("FileChooserClient", "Service started");
  }

  function toBytes(text) {
    var out = new Uint8Array(text.length);
    for (var i = 0; i < text.length; i++)
      out[i] = text.charCodeAt(i) & 0xff;
    return out;
  }

  function uriToPath(uri) {
    var s = String(uri);
    if (s.startsWith("file://"))
      return s.slice("file://".length);
    return s;
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
    if (options.initialPath)
      opts.current_folder = new DBusQML.variant(root.toBytes(options.initialPath), "ay");

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
          if (response === 0 && results && results.uris) {
            var uris = results.uris;
            var paths = [];
            for (var i = 0; i < uris.length; i++)
              paths.push(FileChooserClient.uriToPath(uris[i]));
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
