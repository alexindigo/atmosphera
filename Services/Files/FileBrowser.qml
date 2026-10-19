import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../Helpers/PortalPaths.js" as PortalPaths

Scope {
  id: root

  readonly property string currentPath: _currentPath
  readonly property var model: listing
  readonly property string status: _status
  readonly property string errorText: _errorText
  property string sortKey: "name"
  property bool sortDescending: false
  property bool showHidden: false
  property var nameFilter: null
  readonly property int count: {
    void _listingRevision;
    return listing.rowCount();
  }
  readonly property bool canBack: _historyIndex > 0
  readonly property bool canForward: _historyIndex >= 0 && _historyIndex < _history.length - 1
  readonly property bool hasHidden: _hasHidden

  property string _currentPath: ""
  property string _status: "loading"
  property string _errorText: ""
  property var _history: []
  property int _historyIndex: -1
  property int _serial: 0
  property bool _hasHidden: false
  property int _listingRevision: 0
  property bool _validating: false

  signal listingChanged
  onListingChanged: _listingRevision++

  // All filesystem reads are bounded, argument-vector calls. A failed target
  // never reaches FolderListModel, so it cannot disconnect folder from listing.
  readonly property string _checkCode: `
import json, os, sys
p = os.path.abspath(os.path.expanduser(sys.argv[1]))
try:
    with os.scandir(p) as entries:
        if not os.access(p, os.R_OK | os.X_OK):
            raise PermissionError(13, os.strerror(13), p)
        hidden = any(e.name.startswith('.') for e in entries)
    print(json.dumps({'ok': True, 'path': p, 'hidden': hidden}))
except OSError as e:
    parent = p
    while not os.path.isdir(parent) and parent != '/':
        parent = os.path.dirname(parent)
    print(json.dumps({'ok': False, 'error': e.strerror, 'parent': parent, 'missing': not os.path.exists(p)}))
`

  Component {
    id: checkFactory
    Process {
      id: check
      property int serial
      property string target
      property int historyIndex: -1
      property bool monitor: false
      command: ["timeout", "5", "python3", "-c", root._checkCode, target]
      stdout: StdioCollector { id: checkOutput }
      onExited: function(code) {
        if (serial === root._serial) {
          var result;
          try {
            result = JSON.parse(checkOutput.text);
          } catch (e) {
            result = {ok: false, error: I18n.tr("widgets.file-picker.folder-check-failed")};
          }
          root._checked(result, target, historyIndex, monitor);
        }
        destroy();
      }
    }
  }

  function _check(path, historyIndex, monitor) {
    if (!monitor) {
      _validating = true;
      _status = "loading";
    }
    var check = checkFactory.createObject(root, {serial: ++_serial, target: path, historyIndex: historyIndex, monitor: monitor});
    check.running = true;
  }

  function navigate(path) {
    if (typeof path !== "string" || path.indexOf("\u0000") >= 0 || !(path[0] === "/" || path === "~" || path.startsWith("~/"))) {
      ++_serial;
      _validating = false;
      _errorText = I18n.tr("widgets.file-picker.absolute-folder");
      _status = "error";
      return;
    }
    _status = "loading";
    _errorText = "";
    _check(path, -1, false);
  }

  function _checked(result, target, historyIndex, monitor) {
    if (!result.ok) {
      _validating = false;
      _errorText = I18n.tr("widgets.file-picker.open-folder-error", {path: target, reason: result.error});
      _status = "error";
      if (monitor && result.missing && result.parent !== target)
        _check(result.parent, -1, false);
      return;
    }
    _hasHidden = result.hidden;
    if (monitor)
      return;
    if (historyIndex >= 0)
      _historyIndex = historyIndex;
    else if (result.path !== currentPath) {
      _history = _history.slice(0, _historyIndex + 1).concat([result.path]);
      _historyIndex = _history.length - 1;
    }
    _currentPath = result.path;
    var uri = PortalPaths.pathToUri(currentPath).uri;
    // Clearing forces a refresh even when navigating to the same folder.
    source.folder = "";
    source.folder = uri;
    _validating = false;
  }

  function _publishReady() {
    if (!_validating && _status !== "error" && currentPath && source.status === FolderListModel.Ready && source.folder.toString() === PortalPaths.pathToUri(currentPath).uri) {
      _status = "ready";
      listingChanged();
    }
  }

  function back() {
    if (canBack) {
      _status = "loading";
      _check(_history[_historyIndex - 1], _historyIndex - 1, false);
    }
  }

  function forward() {
    if (canForward) {
      _status = "loading";
      _check(_history[_historyIndex + 1], _historyIndex + 1, false);
    }
  }

  function parentPath(path) {
    return path.slice(0, path.lastIndexOf("/")) || "/";
  }

  function up() { navigate(parentPath(currentPath)); }
  function refresh() { navigate(currentPath); }

  // Consumers use this projection for cursor/selection lookup, never a copied
  // listing. The model itself is passed straight to grid/list delegates.
  function entry(index) {
    if (index < 0 || index >= listing.rowCount())
      return null;
    var row = listing.mapToSource(listing.index(index, 0)).row;
    return {name: source.get(row, "fileName"), path: source.get(row, "filePath"), directory: source.isFolder(row), size: source.get(row, "fileSize"), modified: source.get(row, "fileModified")};
  }

  function indexOfPath(path) {
    for (var i = 0; i < listing.rowCount(); i++) {
      if (entry(i).path === path)
        return i;
    }
    return -1;
  }

  onSortKeyChanged: listing.invalidateSorter()
  onSortDescendingChanged: listing.invalidateSorter()
  onShowHiddenChanged: listing.invalidate()
  onNameFilterChanged: listing.invalidate()

  Connections {
    target: FileTypes
    function onFiltersChanged() { listing.invalidate(); }
  }

  FolderListModel {
    id: source
    folder: ""
    showHidden: true
    showDotAndDotDot: false
    sortField: FolderListModel.Unsorted
    onStatusChanged: {
      if (status === FolderListModel.Ready)
        Qt.callLater(root._publishReady);
    }
  }

  SortFilterProxyModel {
    id: listing
    model: source
    filters: FunctionFilter {
      function filter(fileName: string, fileIsDir: bool): bool {
        return (root.showHidden || !fileName.startsWith(".")) && (fileIsDir || FileTypes.matchesFilter(fileName, root.nameFilter));
      }
    }
    sorters: [
      RoleSorter { roleName: "fileIsDir"; sortOrder: Qt.DescendingOrder; priority: 0 },
      RoleSorter { roleName: "fileSize"; enabled: root.sortKey === "size"; sortOrder: root.sortDescending ? Qt.DescendingOrder : Qt.AscendingOrder; priority: 1 },
      StringSorter { roleName: "fileSuffix"; enabled: root.sortKey === "type"; caseSensitivity: Qt.CaseInsensitive; sortOrder: root.sortDescending ? Qt.DescendingOrder : Qt.AscendingOrder; priority: 1 },
      RoleSorter { roleName: "fileModified"; enabled: root.sortKey === "modified"; sortOrder: root.sortDescending ? Qt.DescendingOrder : Qt.AscendingOrder; priority: 1 },
      StringSorter { roleName: "fileName"; numericMode: true; locale: Qt.locale().name === "C" ? Qt.locale("en_US") : Qt.locale(); caseSensitivity: Qt.CaseInsensitive; sortOrder: root.sortDescending ? Qt.DescendingOrder : Qt.AscendingOrder; priority: 2 }
    ]
  }

  Connections {
    target: listing
    function onModelReset() { root.listingChanged(); }
    function onRowsInserted() { root.listingChanged(); }
    function onRowsRemoved() { root.listingChanged(); }
    function onLayoutChanged() { root.listingChanged(); }
    function onDataChanged() { root.listingChanged(); }
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.currentPath !== "" && root.status !== "loading"
    onTriggered: root._check(root.currentPath, -1, true)
  }
}
