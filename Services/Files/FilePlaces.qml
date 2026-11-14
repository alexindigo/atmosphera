pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../Helpers/PortalPaths.js" as PortalPaths

Singleton {
  id: root
  readonly property string home: Quickshell.env("HOME") || "/"
  readonly property var places: _places
  readonly property var removable: FileVolumes.volumes
  readonly property var favorites: _favorites
  readonly property bool editing: bookmarkEdit.running || _editing
  property string errorText: ""
  readonly property var recentFiles: _recentFiles
  readonly property var recentFolders: _recentFolders
  readonly property var xdgFolders: _xdgFolders
  readonly property bool loading: _scanning || scan.running || _refreshPending || editing
  property var _places: []
  property var _favorites: []
  property var _recentFiles: []
  property var _recentFolders: []
  property bool _refreshPending: false
  property bool _scanning: false
  property bool _editing: false
  property int _editRevision: 0
  property var _xdgFolders: ({})
  signal refreshed()

  // Parse formats as data, never source/eval user-dirs.dirs or bookmarks.
  // XBEL uses an XML parser so escaped attributes and namespaces stay intact.
  readonly property string _scanCode: `
import datetime, json, os, pathlib, re, sys, urllib.parse, xml.etree.ElementTree as ET
home = pathlib.Path.home()
config = pathlib.Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
data = pathlib.Path(os.environ.get('XDG_DATA_HOME', str(home / '.local/share')))
places = [{'name': 'Home', 'path': str(home), 'kind': 'home'}]
xdg = {}
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
                if match[1] in ('DESKTOP', 'DOCUMENTS', 'DOWNLOAD', 'MUSIC', 'PICTURES', 'VIDEOS', 'TEMPLATES', 'PUBLICSHARE') and value != str(home):
                    xdg[match[1]] = os.path.normpath(value)
                add(value, match[1].replace('DOWNLOAD', 'Downloads').title(), 'standard')
except OSError:
    pass
favorites = []
try:
    for line in (config / 'gtk-3.0/bookmarks').read_text().splitlines():
        uri, _, label = line.partition(' ')
        path = local_uri(uri)
        if path and os.path.isdir(path) and not any(p['path'] == path for p in favorites):
            favorites.append({'name': label or os.path.basename(path) or '/', 'path': path, 'kind': 'bookmark'})
except OSError:
    pass
recent = []
folders = {}
def recent_folder(path, stamp):
    if not path or not os.path.isabs(path):
        return
    path = os.path.normpath(path)
    if os.path.isdir(path):
        folders[path] = max(folders.get(path, 0), stamp)
for entry in json.loads(sys.argv[1]):
    # Older chooser state records order but no timestamp. Zero means unknown;
    # stable sorting preserves that order without fabricating historical dates.
    recent_folder(entry['path'], float(entry.get('lastUsed') or 0))
try:
    for bookmark in ET.parse(data / 'recently-used.xbel').getroot().findall('bookmark'):
        path = local_uri(bookmark.get('href', ''))
        modified = bookmark.get('modified', '')
        try:
            date = datetime.datetime.fromisoformat(modified.replace('Z', '+00:00'))
            if date.tzinfo is None:
                date = date.replace(tzinfo=datetime.timezone.utc)
            stamp = date.timestamp() * 1000
        except (ValueError, OverflowError):
            stamp = 0
        if path:
            recent_folder(path if os.path.isdir(path) else os.path.dirname(path), stamp)
        if path and os.path.isfile(path):
            recent.append({'name': os.path.basename(path), 'path': path, 'modified': modified, 'kind': 'recent'})
    recent.sort(key=lambda p: p['modified'], reverse=True)
except (OSError, ET.ParseError):
    pass
recent_folders = [{'name': os.path.basename(path) or '/', 'path': path, 'lastUsed': stamp, 'kind': 'recent', 'directory': True}
                  for path, stamp in sorted(folders.items(), key=lambda item: item[1], reverse=True)[:10]]
print(json.dumps({'places': places + favorites, 'favorites': favorites, 'recent': recent, 'recentFolders': recent_folders, 'xdg': xdg}))
`

  function refresh() {
    if (!_scanning && !scan.running) {
      _scanning = true;
      scan.editRevision = _editRevision;
      scan.running = true;
    } else
      _refreshPending = true;
  }

  function isFavorite(path) { return favorites.some(entry => entry.path === path); }
  function addFavorite(path) { _edit("add", path, 0); }
  function removeFavorite(path) { _edit("remove", path, 0); }
  function moveFavorite(path, direction) { _edit("move", path, direction); }
  function _edit(kind, path, direction) {
    if (editing) return;
    errorText = "";
    _editing = true;
    bookmarkEdit.running = true;
    bookmarkEdit.write(JSON.stringify({kind: kind, path: path, direction: direction}));
    bookmarkEdit.stdinEnabled = false;
  }
  Process {
    id: bookmarkEdit
    command: ["timeout", "5", "python3", PortalPaths.uriToPath(Qt.resolvedUrl("../../Scripts/python/file-bookmarks.py").toString()).path]
    stdinEnabled: true
    onRunningChanged: if (!running) stdinEnabled = true
    stdout: StdioCollector { id: editOutput }
    onExited: code => {
      var result;
      try { result = JSON.parse(editOutput.text); } catch (error) { result = {ok: false}; }
      if (code !== 0 || !result.ok) root.errorText = I18n.tr("widgets.file-picker.bookmark-error") + (result.error ? " " + result.error : "");
      root._editRevision++;
      root.refresh();
    }
  }

  Component.onCompleted: refresh()
  Connections {
    target: FileChooserMemory
    function onRefreshed() { root.refresh(); }
  }

  Process {
    id: scan
    property int editRevision: 0
    command: ["timeout", "5", "python3", "-c", root._scanCode, JSON.stringify(FileChooserMemory.recentEntries)]
    stdout: StdioCollector { id: output }
    onExited: function(code) {
      try {
        if (code !== 0)
          throw new Error("places scan failed");
        var data = JSON.parse(output.text);
        root._places = data.places;
        root._favorites = data.favorites;
        root._recentFiles = data.recent;
        root._recentFolders = data.recentFolders;
        root._xdgFolders = data.xdg;
      } catch (e) {
        Logger.w("FilePlaces", "Invalid places response");
        if (root._editing) root.errorText = I18n.tr("widgets.file-picker.bookmark-error");
      } finally {
        // Completion belongs to the published filesystem snapshot, not the
        // worker's running edge. An older in-flight scan cannot finish an edit.
        if (editRevision === root._editRevision && !bookmarkEdit.running) root._editing = false;
        root._scanning = false;
        if (root._refreshPending) {
          root._refreshPending = false;
          Qt.callLater(root.refresh);
        }
        root.refreshed();
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
