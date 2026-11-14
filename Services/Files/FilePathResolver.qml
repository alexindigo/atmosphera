import QtQuick
import Quickshell
import Quickshell.Io
import "FilePaths.js" as Paths

// One typed-path contract for both Name and Location. This owns asynchronous
// filesystem classification; FileRequest alone applies the resulting intent.
Scope {
  id: root
  property string basePath
  property string mode: "open"
  property bool directoryMode: false
  property bool multiple: false
  property int _generation: 0
  readonly property bool busy: _busy
  property bool _busy: false
  signal resolved(var result)
  signal failed(string reason)

  function invalidate() { ++_generation; _busy = false; }
  function resolve(text, source) {
    invalidate();
    var parsed = Paths.names(text, multiple && source === "name");
    if (!parsed.ok) { failed(parsed.error); return; }
    var paths = [];
    for (var value of parsed.values) {
      var path = Paths.local(value, basePath, FilePlaces.home);
      if (!path.ok) { failed(path.error); return; }
      paths.push(path.path);
    }
    _busy = true;
    var job = resolverFactory.createObject(root, {generation: _generation, paths: paths,
      source: source, explicitFolder: text.includes("/") || text === "~", requiresFolder: text.endsWith("/")});
    job.running = true;
  }
  Component {
    id: resolverFactory
    Process {
      property int generation
      property var paths
      property string source
      property bool explicitFolder
      property bool requiresFolder
      command: ["timeout", "5", "python3", "-c", `
import json, os, sys
try:
    print(json.dumps({'directories': [os.path.isdir(path) for path in json.loads(sys.argv[1])]}))
except (ValueError, OSError):
    print('{}')
`, JSON.stringify(paths)]
      stdout: StdioCollector { id: output }
      onExited: function(code) {
        if (generation === root._generation) {
          root._busy = false;
          var result;
          try { result = JSON.parse(output.text); } catch (error) { result = null; }
          if (code !== 0 || !result || !Array.isArray(result.directories)) root.failed("selection-check-failed");
          else if (requiresFolder && !result.directories.every(value => value)) root.failed("wrong-kind");
          else {
            var folder = paths.length === 1 && result.directories[0];
            var navigate = folder && (source === "location" || (root.mode === "open" && !root.directoryMode) || (root.mode === "save" && explicitFolder));
            root.resolved({action: navigate ? "navigate" : root.mode, paths: paths});
          }
        }
        destroy();
      }
    }
  }
}
