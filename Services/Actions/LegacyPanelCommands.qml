pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
  id: root

  readonly property bool ready: _ready
  property bool _ready: false
  property var _entries: []

  function normalize(command) {
    const tokens = /^atmosphera[ \t]+ipc[ \t]+(\w+)[ \t]+(\w+)$/.exec(command);
    const entry = tokens && _entries.find(row => row.target === tokens[1] && row.method === tokens[2]);
    return entry ? "atmosphera ipc plugin " + entry.panelMethod + " " + entry.pluginId : command;
  }

  function pickerActions(manifest) {
    if (manifest.actions !== undefined || !manifest.entryPoints?.panel || typeof manifest.version !== "string" || !Version.releaseVersion(manifest.version))
      return [];
    return _entries.filter(row => row.picker && row.pluginId === manifest.id && Version.compareVersions(manifest.version, row.minVersion) >= 0 && Version.compareVersions(manifest.version, row.maxVersion) <= 0).map(row => row.picker);
  }

  function parse(text) {
    const entries = [];
    for (const line of text.split("\n")) {
      if (line.startsWith("#"))
        continue;
      const [target, method, panelMethod, pluginId, minVersion, maxVersion, label, description, icon] = line.split("\t");
      if (!target || !method || !pluginId || !/^(open|toggle|close)Panel$/.test(panelMethod))
        continue;
      let picker = null;
      if (minVersion && maxVersion && Version.releaseVersion(minVersion) && Version.releaseVersion(maxVersion) && label && description && icon) {
        picker = {
          id: method,
          panel: panelMethod.slice(0, -5),
          label: label,
          description: description,
          icon: icon
        };
      }
      entries.push({
                     target: target,
                     method: method,
                     panelMethod: panelMethod,
                     pluginId: pluginId,
                     minVersion: minVersion,
                     maxVersion: maxVersion,
                     picker: picker
                   });
    }
    return entries;
  }

  FileView {
    path: Quickshell.shellDir + "/Assets/Actions/legacy-panel-commands.tsv"
    preload: true
    onLoaded: {
      root._entries = root.parse(text());
      root._ready = true;
    }
    onLoadFailed: root._ready = true
  }
}
