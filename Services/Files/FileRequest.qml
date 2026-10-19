import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../Helpers/PortalPaths.js" as PortalPaths

Scope {
  id: root
  property string method: "open"
  property string appId: ""
  property var options: ({})
  readonly property FileBrowser browser: requestBrowser
  readonly property FileSelection selection: requestSelection
  property string saveName: ""
  property var choiceValues: ({})
  property var currentFilter: null
  readonly property string pendingReplace: _pendingReplace
  readonly property string errorText: _errorText
  readonly property bool settled: _settled
  readonly property bool busy: _checking || browser.status === "loading"
  readonly property string acceptLabel: options.accept_label || I18n.tr(method === "open" ? "widgets.file-picker.open" : "widgets.file-picker.save")
  property string viewMode: "grid"
  property bool _settled: false
  property bool _initialized: false
  property bool _checking: false
  property string _pendingReplace: ""
  property string _errorText: ""
  property string _initialFile: ""
  property var _saveFilesNames: []
  property var _targets: []
  property var _replacements: []
  property var _approved: []
  property var _snapshot: null
  property int _generation: 0

  signal finished(int response, var results)

  FileBrowser {
    id: requestBrowser
    nameFilter: root.currentFilter
    onCurrentPathChanged: root._invalidate()
    onStatusChanged: {
      if (status === "loading")
        root._invalidate();
      else if (status === "ready" && root._initialFile) {
        var index = indexOfPath(root._initialFile);
        if (index >= 0)
          requestSelection.click(index, Qt.NoModifier);
        root._initialFile = "";
      }
    }
  }

  FileSelection {
    id: requestSelection
    browser: requestBrowser
    selectable: root.method === "saveFiles" || root.options.directory === true ? "folders" : "files"
    multiple: root.method === "open" && root.options.multiple === true
  }

  function _decode(value, absolute) {
    var result = PortalPaths.decodeBytePath(value);
    if (!result.ok || (absolute && result.path && result.path[0] !== "/"))
      throw new Error(result.error || "Choose an absolute path");
    return result.path;
  }

  function _initialize() {
    if (_settled || _initialized || !FileChooserMemory.ready)
      return;
    _initialized = true;
    try {
      if (!["open", "save", "saveFiles"].includes(method))
        throw new Error("Unknown file chooser method");
      var prefs = FileChooserMemory.preferences;
      browser.sortKey = prefs.sortKey || "name";
      browser.sortDescending = prefs.sortDescending === true;
      browser.showHidden = prefs.showHidden === true;
      viewMode = prefs.view || "grid";
      if (method === "saveFiles")
        _saveFilesNames = (options.files || []).map(value => _decode(value, false));
      var folder = options.current_folder !== undefined ? _decode(options.current_folder, true) : "";
      var file = options.current_file !== undefined ? _decode(options.current_file, true) : "";
      if (file) {
        folder = browser.parentPath(file);
        _initialFile = file;
      }
      saveName = options.current_name !== undefined ? String(options.current_name) : (file ? file.slice(file.lastIndexOf("/") + 1) : "");
      currentFilter = options.current_filter || (options.filters && options.filters.length ? options.filters[0] : null);
      var values = {};
      for (var choice of options.choices || [])
        values[choice[0]] = choice[3] || (choice[2].length ? choice[2][0][0] : "false");
      choiceValues = values;
      browser.navigate(folder || FileChooserMemory.folderFor(appId));
    } catch (e) {
      _errorText = String(e.message);
      _finish(2, {});
    }
  }

  Component.onCompleted: Qt.callLater(_initialize)
  Connections {
    target: FileChooserMemory
    function onReadyChanged() { Qt.callLater(root._initialize); }
  }

  function _invalidate() {
    ++_generation;
    _checking = false;
    _pendingReplace = "";
    _errorText = "";
    _approved = [];
    _snapshot = null;
  }

  onSaveNameChanged: _invalidate()
  onCurrentFilterChanged: _invalidate()
  onChoiceValuesChanged: _invalidate()
  Connections {
    target: requestSelection
    function onSelectedPathsChanged() {
      root._invalidate();
      if (root.method === "save" && requestSelection.selectedPaths.length === 1) {
        var path = requestSelection.selectedPaths[0];
        root.saveName = path.slice(path.lastIndexOf("/") + 1);
      }
    }
  }

  function _validName(name) {
    return typeof name === "string" && name.length > 0 && ![".", ".."].includes(name) && !name.includes("/") && !name.includes("\u0000");
  }

  function setChoice(id, value) {
    var values = Object.assign({}, choiceValues);
    values[id] = value;
    choiceValues = values;
  }

  function activate(index) {
    var item = browser.entry(index);
    if (!item || _settled)
      return;
    if (item.directory)
      browser.navigate(item.path);
    else {
      if (!selection.selectedPaths.includes(item.path))
        selection.click(index, Qt.NoModifier);
      accept();
    }
  }

  function accept() {
    if (_settled || busy || _pendingReplace)
      return;
    _errorText = "";
    var paths = [];
    var folder = method === "saveFiles" && selection.selectedPaths.length ? selection.selectedPaths[0] : browser.currentPath;
    if (method === "open") {
      paths = selection.selectedPaths.slice();
      if (options.directory === true && !paths.length)
        paths = [browser.currentPath];
      if (!paths.length) {
        _errorText = I18n.tr("widgets.file-picker.choose-file-first");
        return;
      }
    } else {
      var names = method === "saveFiles" ? _saveFilesNames : [saveName];
      if (!names.length || names.some(name => !_validName(name))) {
        _errorText = I18n.tr("widgets.file-picker.invalid-name");
        return;
      }
      paths = names.map(name => (folder === "/" ? "" : folder) + "/" + name);
    }
    var choices = [];
    for (var choice of options.choices || []) {
      var value = choiceValues[choice[0]];
      var allowed = choice[2].length ? choice[2].map(item => item[0]) : ["true", "false"];
      if (!allowed.includes(value)) {
        _errorText = I18n.tr("widgets.file-picker.invalid-choice", {name: choice[1]});
        return;
      }
      choices.push([choice[0], value]);
    }
    _targets = paths;
    _snapshot = {folder: folder, choices: choices, filter: currentFilter};
    _validate();
  }

  // Read-only validation; saves return destinations without creating files.
  // Each async check carries a generation so stale completions cannot accept a
  // changed name, folder or selection, or revive a cancelled request.
  readonly property string _validateCode: `
import json, os, sys
mode, directory, folder, paths = json.loads(sys.argv[1])
try:
    if not os.path.isdir(folder):
        raise ValueError('folder-missing')
    if not os.access(folder, os.R_OK | os.X_OK):
        raise ValueError('folder-unreadable')
    replacements = []
    writable = True
    for path in paths:
        if mode == 'open':
            if not (os.path.isdir(path) if directory else os.path.isfile(path)):
                raise ValueError('wrong-kind')
            if not os.access(path, os.R_OK):
                raise ValueError('file-unreadable')
            writable = writable and os.access(path, os.W_OK)
        else:
            if not os.access(folder, os.W_OK | os.X_OK):
                raise ValueError('folder-unwritable')
            if os.path.lexists(path):
                if not os.path.isfile(path) or not os.access(path, os.W_OK):
                    raise ValueError('cannot-replace')
                replacements.append(path)
    print(json.dumps({'ok': True, 'replacements': replacements, 'writable': writable}))
except (ValueError, OSError) as e:
    print(json.dumps({'ok': False, 'error': str(e)}))
`

  Component {
    id: validationFactory
    Process {
      id: validation
      property int generation
      property var input
      command: ["timeout", "5", "python3", "-c", root._validateCode, JSON.stringify(input)]
      stdout: StdioCollector { id: validationOutput }
      onExited: function(code) {
        if (!root.settled && generation === root._generation) {
          root._checking = false;
          var result;
          try {
            result = JSON.parse(validationOutput.text);
          } catch (e) {
            result = {ok: false, error: "selection-check-failed"};
          }
          root._validated(result);
        }
        destroy();
      }
    }
  }

  function _validate() {
    _checking = true;
    var check = validationFactory.createObject(root, {generation: ++_generation, input: [method, options.directory === true, _snapshot.folder, _targets]});
    check.running = true;
  }

  function _validated(result) {
    if (!result.ok) {
      _errorText = I18n.tr("widgets.file-picker." + result.error);
      return;
    }
    _replacements = result.replacements.filter(path => !_approved.includes(path));
    if (_replacements.length) {
      _pendingReplace = _replacements[0];
      return;
    }
    var uris = [];
    for (var path of _targets) {
      var converted = PortalPaths.pathToUri(path);
      if (!converted.ok) {
        _errorText = converted.error;
        _finish(2, {});
        return;
      }
      uris.push(converted.uri);
    }
    var results = {uris: uris, writable: result.writable, choices: _snapshot.choices};
    if (_snapshot.filter)
      results.current_filter = _snapshot.filter;
    var folder = _snapshot.folder;
    var prefs = {view: viewMode, sortKey: browser.sortKey, sortDescending: browser.sortDescending, showHidden: browser.showHidden};
    _finish(0, results);
    FileChooserMemory.remember(appId, folder, prefs);
  }

  function confirmReplace() {
    if (_settled || !_pendingReplace || busy)
      return;
    _approved = _approved.concat([_pendingReplace]);
    _pendingReplace = "";
    _validate();
  }

  function _finish(response, results) {
    if (_settled)
      return;
    _settled = true;
    _checking = false;
    _pendingReplace = "";
    ++_generation;
    finished(response, results);
  }

  function cancel() { _finish(1, {}); }
  function fail(message) {
    _errorText = message;
    _finish(2, {});
  }
}
