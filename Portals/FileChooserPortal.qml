// xdg-desktop-portal backend for org.freedesktop.impl.portal.FileChooser.
//
// Serves OpenFile, SaveFile and SaveFiles on the session bus under
// org.freedesktop.impl.portal.desktop.atmosphera, discovered via
// Portals/atmosphera.portal. Every method defers its reply with
// holdReply and settles it once the user finishes the PortalFileDialog
// for that request; a per-call org.freedesktop.impl.portal.Request
// adaptor lets the caller cancel via Close. Requires qt6-dbusqml
// >= 0.5.0 for deferred replies and typed variant payloads.
//
// NOTE: keep curly braces OUT of comments in this file — the quickshell
// qmlscanner mishandles braces inside comments and silently breaks
// singleton instantiation (quickshell bug; observed on quickshell 0.3.1).

pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import "../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Services.Compositor

Singleton {
  id: root

  property var activeRequests: ({})

  // Thrown by parseOptions when a byte-path option does not decode. Distinct
  // from a structurally malformed options dictionary, which is InvalidArgument.
  function decodeFailure(option, error) {
    return ({
              "option": option,
              "error": error,
              "decodeFailure": true
            });
  }

  function init() {
    Logger.i("FileChooserPortal", "Service started");
  }

  // Decodes an absolute path option. An empty result means the caller gave no
  // folder (a lone NUL terminator), and the option is left out.
  function decodeFolderOption(option, value) {
    var decoded = PortalPaths.decodeBytePath(value);
    if (!decoded.ok)
      throw root.decodeFailure(option, decoded.error);
    if (decoded.path !== "" && decoded.path.charAt(0) !== "/")
      throw root.decodeFailure(option, "not an absolute path");
    return decoded.path;
  }

  function splitPath(path) {
    var idx = path.lastIndexOf("/");
    if (idx <= 0)
      return ["", path];
    return [path.slice(0, idx), path.slice(idx + 1)];
  }

  function parseFilters(filters) {
    var globs = [];
    for (var i = 0; i < filters.length; i++) {
      var entry = filters[i];
      if (!entry || entry.length < 2)
        throw new Error("malformed filter entry");
      var patterns = entry[1];
      for (var j = 0; j < patterns.length; j++) {
        var pair = patterns[j];
        if (!pair || pair.length < 2)
          throw new Error("malformed filter pattern");
        if (pair[0] === 0 && typeof pair[1] === "string" && pair[1] !== "")
          globs.push(pair[1]);
      }
    }
    return globs;
  }

  function parseOptions(options, title) {
    var parsed = ({
                    "title": title || ""
                  });
    if (!options)
      return parsed;
    parsed.multiple = options.multiple === true;
    parsed.directory = options.directory === true;
    if (options.accept_label !== undefined)
      parsed.accept_label = String(options.accept_label);
    if (options.current_name !== undefined)
      parsed.current_name = String(options.current_name);
    if (options.current_folder !== undefined) {
      var folder = root.decodeFolderOption("current_folder", options.current_folder);
      if (folder !== "")
        parsed.current_folder = folder;
    }
    if (options.current_file !== undefined) {
      var file = root.decodeFolderOption("current_file", options.current_file);
      if (file !== "") {
        var parts = root.splitPath(file);
        if (parts[0] !== "")
          parsed.current_folder = parts[0];
        parsed.current_file_name = parts[1];
      }
    }
    if (options.filters !== undefined) {
      var globs = root.parseFilters(options.filters);
      if (globs.length > 0)
        parsed.filters = globs;
    }
    return parsed;
  }

  DBusAdaptor {
    id: adaptor
    service: "org.freedesktop.impl.portal.desktop.atmosphera"
    path: "/org/freedesktop/portal/desktop"
    captureSubtree: true
    iface: "org.freedesktop.impl.portal.FileChooser"
    connection: SessionBus

    function openFile(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, title, options, "open", adaptor.holdReply());
    }

    function saveFile(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, title, options, "save", adaptor.holdReply());
    }

    function saveFiles(handle, appId, parentWindow, title, options) {
      root.beginRequest(handle, title, options, "saveMulti", adaptor.holdReply());
    }
  }

  function beginRequest(handle, title, options, mode, reply) {
    var parsed;
    try {
      parsed = root.parseOptions(options, title);
    } catch (e) {
      if (e && e.decodeFailure === true) {
        Logger.w("FileChooserPortal", "Cannot decode " + e.option + " for " + handle + ": " + e.error);
        reply.send([2,
                    {}
                   ]);
        return;
      }
      Logger.w("FileChooserPortal", "Rejecting malformed options for " + handle);
      reply.sendError("org.freedesktop.portal.Error.InvalidArgument", "malformed options");
      return;
    }

    var request = requestFactory.createObject(root, {
                                                handle: handle
                                              });

    // Store BEFORE any settle path so a later Close always finds the entry.
    var entry = ({
                   request: request,
                   dialog: null,
                   reply: reply,
                   settled: false
                 });
    var map = root.activeRequests;
    map[handle] = entry;
    root.activeRequests = map;

    var screen = CompositorService.getFocusedScreen();
    if (!screen && Quickshell.screens.length > 0)
      screen = Quickshell.screens[0];
    if (!screen) {
      // Entry stored and marked settled: a later Close no-ops cleanly
      // (settles-once) instead of orphaning.
      entry.settled = true;
      reply.send([2,
                  {}
                 ]);
      request.destroy();
      return;
    }

    var dialog = dialogFactory.createObject(root, {
                                              screen: screen,
                                              mode: mode,
                                              options: parsed
                                            });

    entry.dialog = dialog;

    dialog.accepted.connect(function (paths) {
      var entry = root.activeRequests[handle];
      if (!entry || entry.settled)
        return;
      entry.settled = true;
      var uris = [];
      for (var i = 0; i < paths.length; i++) {
        var converted = PortalPaths.pathToUri(paths[i]);
        if (!converted.ok) {
          // All or nothing: a partial uri list would hide the failed path.
          Logger.w("FileChooserPortal", "Cannot convert accepted path for " + handle + ": " + converted.error);
          reply.send([2,
                      {}
                     ]);
          root.cleanup(handle);
          return;
        }
        uris.push(converted.uri);
      }
      reply.send([0,
                  {
                    "uris": new DBusQML.variant(uris, "as")
                  }
                 ]);
      root.cleanup(handle);
    });

    dialog.cancelled.connect(function () {
      root.settleCancelled(handle);
    });
  }

  // Single-settle cancel path: closeRequest destroys the dialog (whose
  // destruction later re-fires cancelled) and settles the reply; the
  // settled flag keeps that to exactly one send.
  function settleCancelled(handle) {
    var entry = root.activeRequests[handle];
    if (!entry || entry.settled)
      return;
    entry.settled = true;
    entry.reply.send([1,
                      {}
                     ]);
    root.cleanup(handle);
  }

  function closeRequest(handle) {
    var entry = root.activeRequests[handle];
    if (!entry)
      return;
    if (entry.dialog)
      entry.dialog.destroy();
    if (entry.settled) {
      // early-settled path: drop the entry, no second send
      var map = root.activeRequests;
      delete map[handle];
      root.activeRequests = map;
      return;
    }
    root.settleCancelled(handle);
  }

  function cleanup(handle) {
    var map = root.activeRequests;
    var entry = map[handle];
    if (!entry)
      return;
    if (entry.dialog)
      entry.dialog.destroy();
    if (entry.request)
      entry.request.destroy();
    delete map[handle];
    root.activeRequests = map;
  }

  Component {
    id: requestFactory

    DBusAdaptor {
      property string handle: ""

      path: handle
      iface: "org.freedesktop.impl.portal.Request"
      connection: SessionBus

      function close() {
        root.closeRequest(handle);
      }
    }
  }

  Component {
    id: dialogFactory

    PortalFileDialog {}
  }
}
