pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property bool ready: _ready
  readonly property var recentLocations: _recentLocations
  readonly property var preferences: store.preferences
  readonly property string home: Quickshell.env("HOME") || "/"
  property bool _ready: false
  property var _recentLocations: []
  property var _validPaths: []
  property int _generation: 0
  signal refreshed

  // Same FileView/JsonAdapter state transport as the other persistent services.
  // Merely opening a request never creates or rewrites this file.
  FileView {
    id: view
    path: Settings.cacheDir + "filechooser.json"
    printErrors: false
    adapter: JsonAdapter {
      id: store
      property var appFolders: ({})
      property string sharedFolder: ""
      property var recent: []
      property var preferences: ({view: "grid", sortKey: "name", sortDescending: false, showHidden: false})
    }
    onLoaded: root.refresh()
    onLoadFailed: root.refresh()
    onSaveFailed: Logger.w("FileChooserMemory", "Could not save chooser memory")
  }

  readonly property string _validateCode: `
import json, os, sys
paths = json.loads(sys.argv[1])
print(json.dumps([p for p in paths if isinstance(p, str) and os.path.isabs(p) and os.path.isdir(p) and os.access(p, os.R_OK | os.X_OK)]))
`

  Component {
    id: validatorFactory
    Process {
      id: validator
      property int generation
      property var paths
      command: ["timeout", "5", "python3", "-c", root._validateCode, JSON.stringify(paths)]
      stdout: StdioCollector { id: validationOutput }
      onExited: function(code) {
        if (generation === root._generation) {
          var valid = [];
          try {
            valid = JSON.parse(validationOutput.text);
          } catch (e) {
            Logger.w("FileChooserMemory", "Could not validate remembered folders");
          }
          root._validPaths = valid;
          root._recentLocations = store.recent.filter((p, i, paths) => valid.includes(p) && paths.indexOf(p) === i).slice(0, 10);
          root._ready = true;
          root.refreshed();
        }
        destroy();
      }
    }
  }

  function refresh() {
    var paths = store.recent.concat(Object.values(store.appFolders), [store.sharedFolder]);
    var validator = validatorFactory.createObject(root, {generation: ++_generation, paths: paths});
    validator.running = true;
  }

  function folderFor(appId) {
    var path = appId ? store.appFolders[appId] : "";
    if (path && _validPaths.includes(path))
      return path;
    return _validPaths.includes(store.sharedFolder) ? store.sharedFolder : home;
  }

  function remember(appId, folder, prefs) {
    if (!folder || folder[0] !== "/")
      return;
    // The successful request has just validated this directory. Publish one
    // immutable snapshot, and filter old/missing entries on each refresh.
    var apps = Object.assign({}, store.appFolders);
    if (appId)
      apps[appId] = folder;
    store.appFolders = apps;
    store.sharedFolder = folder;
    store.recent = [folder].concat(store.recent.filter(p => p !== folder && _validPaths.includes(p))).slice(0, 10);
    if (prefs)
      store.preferences = Object.assign({}, prefs);
    _validPaths = _validPaths.concat([folder]);
    _recentLocations = store.recent.filter(p => _validPaths.includes(p));
    refresh();
    if (!makeDirectory.running)
      makeDirectory.running = true;
  }

  Process {
    id: makeDirectory
    command: ["timeout", "5", "mkdir", "-p", Settings.cacheDir]
    onExited: function(code) {
      if (code === 0)
        view.writeAdapter();
      else
        Logger.w("FileChooserMemory", "Could not create chooser state directory");
    }
  }
}
