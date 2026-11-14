import QtQuick
import Quickshell
import Quickshell.Io
import "FilePaths.js" as Paths

Scope {
  id: root
  property string text: ""
  property string basePath: ""
  property bool directoriesOnly: false
  property bool showHidden: false
  property var nameFilter: null
  property bool active: false
  readonly property var suggestions: _suggestions
  readonly property bool busy: _busy
  property var _suggestions: []
  property bool _busy: false
  property int _generation: 0
  onTextChanged: schedule()
  onBasePathChanged: schedule()
  onShowHiddenChanged: schedule()
  onNameFilterChanged: schedule()
  onDirectoriesOnlyChanged: schedule()
  onActiveChanged: schedule()
  Connections { target: FileTypes; function onFiltersChanged() { root.schedule(); } }

  function schedule() {
    ++_generation;
    _suggestions = [];
    _busy = false;
    debounce.stop();
    if (active && basePath) debounce.start();
  }
  function refresh() {
    var prefix = "", value = text, quoted = false;
    // Complete the current quoted name independently of previously entered
    // names. Unquoted spaces remain ordinary local filename characters.
    var start = -1;
    if (text.startsWith('"')) {
      for (var i = 0; i < text.length; i++) {
        if (text[i] === "\\" && quoted && ['"', "\\"].includes(text[i + 1])) { i++; continue; }
        if (text[i] === '"') { quoted = !quoted; if (quoted) start = i; }
      }
      if (quoted) {
        prefix = text.slice(0, start + 1);
        value = text.slice(start + 1).replace(/\\(["\\])/g, "$1");
      }
    }
    var slash = value.lastIndexOf("/");
    var head = slash >= 0 ? value.slice(0, slash + 1) : "";
    var stem = value.slice(slash + 1);
    if (value === "~") { head = "~/"; stem = ""; }
    var folder = Paths.local(head || ".", basePath, FilePlaces.home);
    if (!folder.ok) return;
    _busy = true;
    var job = completionFactory.createObject(root, {generation: _generation, folder: folder.path,
      head: head, prefix: prefix, stem: stem, quoted: quoted});
    job.running = true;
  }
  Timer { id: debounce; interval: 100; onTriggered: root.refresh() }
  Component {
    id: completionFactory
    Process {
      property int generation
      property string folder
      property string head
      property string prefix
      property string stem
      property bool quoted
      command: ["timeout", "5", "python3", "-c", `
import json, os, sys
folder, stem, hidden, directories = json.loads(sys.argv[1])
try:
    with os.scandir(folder) as items:
        rows = [{'name': e.name, 'path': e.path, 'directory': e.is_dir()} for e in items
                if e.name.casefold().startswith(stem.casefold()) and (hidden or stem.startswith('.') or not e.name.startswith('.'))
                and (not directories or e.is_dir())]
    print(json.dumps(sorted(rows, key=lambda e: (not e['directory'], e['name'].casefold()))))
except OSError:
    print('[]')
`, JSON.stringify([folder, stem, root.showHidden, root.directoriesOnly])]
      stdout: StdioCollector { id: output }
      onExited: function(code) {
        if (generation === root._generation) {
          root._busy = false;
          var entries = [];
          try { if (code === 0) entries = JSON.parse(output.text); } catch (error) {}
          root._suggestions = entries.filter(entry => entry.directory || FileTypes.matchesFilter(entry.name, root.nameFilter)).map(entry => ({
            name: entry.name, path: entry.path, directory: entry.directory,
            text: prefix + head + (quoted ? entry.name.replace(/\\/g, "\\\\").replace(/"/g, '\\"') : entry.name) + (entry.directory ? "/" : quoted ? '"' : "")
          }));
        }
        destroy();
      }
    }
  }
}
