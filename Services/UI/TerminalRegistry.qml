pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Merged terminals: bundled + user override
  property var terminals: ({})

  // Paths
  readonly property string bundledFile: Quickshell.shellDir + "/Assets/terminals.json"
  readonly property string userFile: Settings.configDir + "terminals.json"

  FileView {
    id: bundledView
    path: root.bundledFile
    onLoaded: function () {
      root.loadTerminals();
    }
  }

  FileView {
    id: userView
    path: root.userFile
    onLoaded: function () {
      root.loadTerminals();
    }
  }

  function init() {
    Logger.i("TerminalRegistry", "Service started");
    loadTerminals();
  }

  function loadTerminals() {
    var merged = {};
    try {
      var bundledText = bundledView.text();
      if (bundledText && bundledText.trim() !== "") {
        Object.assign(merged, JSON.parse(bundledText));
      }
    } catch (e) {
      Logger.w("TerminalRegistry", "Failed to parse bundled terminals.json:", e);
    }
    try {
      var userText = userView.text();
      if (userText && userText.trim() !== "") {
        Object.assign(merged, JSON.parse(userText));
      }
    } catch (e) {
      Logger.w("TerminalRegistry", "Failed to parse user terminals.json:", e);
    }
    terminals = merged;
    Logger.d("TerminalRegistry", "Loaded", Object.keys(merged).length, "terminal definitions");
  }

  // Get default run flags for a terminal (prefill for the params field).
  // Returns [] for unknown appIds — callers don't need a separate membership check.
  function defaultRunArgs(appId) {
    if (!appId || !(appId in root.terminals))
      return [];
    return root.terminals[appId].runArgs || [];
  }

  // Get list of terminals that are actually installed on the system.
  // Each result: { id (desktop-entry key), name }
  function getInstalledTerminals() {
    var result = [];
    for (var key in root.terminals) {
      if (typeof DesktopEntries !== "undefined" && DesktopEntries.byId && DesktopEntries.byId(key)) {
        result.push({
                      "id": key,
                      "name": root.terminals[key].name || key
                    });
      }
    }
    result.sort(function (a, b) {
      return a.name.localeCompare(b.name);
    });
    return result;
  }
}
