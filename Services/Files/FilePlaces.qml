pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root
  readonly property string home: Quickshell.env("HOME") || "/"
  readonly property var places: _places
  readonly property var removable: _removable
  readonly property var recentFiles: _recentFiles
  readonly property bool loading: scan.running
  property var _places: []
  property var _removable: []
  property var _recentFiles: []

  // Parse formats as data, never source/eval user-dirs.dirs or bookmarks.
  // XBEL uses an XML parser so escaped attributes and namespaces stay intact.
  readonly property string _scanCode: `
import json, os, pathlib, re, urllib.parse, xml.etree.ElementTree as ET
home = pathlib.Path.home()
config = pathlib.Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
data = pathlib.Path(os.environ.get('XDG_DATA_HOME', str(home / '.local/share')))
places = [{'name': 'Home', 'path': str(home), 'kind': 'home'}]
seen = {str(home)}
def add(path, name, kind):
    if path and path not in seen and os.path.isdir(path):
        places.append({'name': name, 'path': path, 'kind': kind})
        seen.add(path)
def local_uri(uri):
    u = urllib.parse.urlsplit(uri)
    return urllib.parse.unquote(u.path) if u.scheme == 'file' and u.netloc in ('', 'localhost') else ''
try:
    for line in (config / 'user-dirs.dirs').read_text().splitlines():
        match = re.fullmatch(r'XDG_([A-Z]+)_DIR="(.*)"', line.strip())
        if match:
            value = match[2].replace('$HOME', str(home))
            value = re.sub(r'\\\\([\\\\"$' + "\x60" + r'])', r'\\1', value)
            if value.startswith('/'):
                add(value, match[1].replace('DOWNLOAD', 'Downloads').title(), 'standard')
except OSError:
    pass
try:
    for line in (config / 'gtk-3.0/bookmarks').read_text().splitlines():
        uri, _, label = line.partition(' ')
        path = local_uri(uri)
        add(path, label or os.path.basename(path), 'bookmark')
except OSError:
    pass
removable = []
media = pathlib.Path('/run/media') / os.environ.get('USER', home.name)
try:
    removable = [{'name': p.name, 'path': str(p), 'kind': 'removable'} for p in sorted(media.iterdir()) if p.is_dir()]
except OSError:
    pass
recent = []
try:
    for bookmark in ET.parse(data / 'recently-used.xbel').getroot().findall('bookmark'):
        path = local_uri(bookmark.get('href', ''))
        if path and os.path.isfile(path):
            recent.append({'name': os.path.basename(path), 'path': path, 'modified': bookmark.get('modified', ''), 'kind': 'recent'})
    recent.sort(key=lambda p: p['modified'], reverse=True)
except (OSError, ET.ParseError):
    pass
print(json.dumps({'places': places, 'removable': removable, 'recent': recent}))
`

  function refresh() {
    if (!scan.running)
      scan.running = true;
  }

  Component.onCompleted: refresh()

  Process {
    id: scan
    command: ["timeout", "5", "python3", "-c", root._scanCode]
    stdout: StdioCollector { id: output }
    onExited: function(code) {
      if (code !== 0) {
        Logger.w("FilePlaces", "Could not read file chooser places");
        return;
      }
      try {
        var data = JSON.parse(output.text);
        root._places = data.places;
        root._removable = data.removable;
        root._recentFiles = data.recent;
      } catch (e) {
        Logger.w("FilePlaces", "Invalid places response");
      }
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
}
