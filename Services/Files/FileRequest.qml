import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../Helpers/PortalPaths.js" as PortalPaths
import "FileSaveNames.js" as SaveNames
import "FilePaths.js" as Paths

Scope {
  id: root
  property string method: "open"
  property string appId: ""
  property var options: ({})
  readonly property var appEntry: {
    // Re-resolve when the desktop-entry model finishes loading or changes.
    void DesktopEntries.applications.values;
    return appId ? DesktopEntries.byId(appId) : null;
  }
  readonly property string appName: appEntry ? appEntry.name : ""
  readonly property string appIcon: appEntry ? appEntry.icon : ""
  readonly property string appOptionsLabel: appEntry ? I18n.tr("widgets.file-picker.options-from", {name: appName}) : I18n.tr("widgets.file-picker.options-from-app")
  readonly property var choices: options.choices || []
  readonly property FileBrowser browser: requestBrowser
  readonly property FileSelection selection: requestSelection
  property string saveName: ""
  property string _nameBeforeEdit: ""
  property string openName: ""
  property bool _openNameEdited: false
  readonly property string openDisplayName: _openNameEdited ? openName : Paths.quote(selection.selectedPaths.map(Paths.leaf))
  property var _pendingSavePath: null
  readonly property var pathResolver: typedPaths
  property bool saveFilterEnabled: true
  property bool autoExtension: true
  readonly property var saveSuffixes: FileTypes.saveSuffixes(currentFilter)
  readonly property string preferredSuffix: saveSuffixes.length ? saveSuffixes[0] : ""
  property bool _namePolicyReady: false
  property var _previousNameFilter: null
  property bool _saveNameEdited: false
  readonly property string saveFilterStem: {
    var name = Paths.leaf(saveName), dot = name.lastIndexOf(".");
    return dot >= 0 ? name.slice(0, dot) : name;
  }
  property var choiceValues: ({})
  property var currentFilter: null
  readonly property string pendingReplace: _pendingReplace
  readonly property string errorText: _errorText
  readonly property bool settled: _settled
  readonly property bool busy: _checking || _nameChecking || typedPaths.busy || browser.status === "loading"
  readonly property string acceptLabel: options.accept_label || I18n.tr(method === "open" ? "widgets.file-picker.open" : "widgets.file-picker.save")
  property string viewMode: "grid"
  property bool _settled: false
  property bool _initialized: false
  property bool _waitingMemory: false
  property bool _checking: false
  property bool _nameChecking: false
  property int _nameGeneration: 0
  property string _pendingReplace: ""
  property string _errorText: ""
  property string _initialFile: ""
  property var _saveFilesNames: []
  property var _replacements: []
  property var _approved: []
  property var _snapshot: null
  property int _generation: 0

  signal finished(int response, var results)

  FileBrowser {
    id: requestBrowser
    nameFilter: root.currentFilter
    saveFilterText: root.method === "save" && root.saveFilterEnabled && root._saveNameEdited ? root.saveFilterStem : ""
    onNavigationRequested: {
      root._pendingSavePath = null;
      typedPaths.invalidate();
    }
    onCurrentPathChanged: {
      root._saveNameEdited = false;
      root._invalidateName();
    }
    onStatusChanged: {
      if (status === "loading")
        root._invalidateName();
      else if (status === "ready" && root._pendingSavePath) {
        var pending = root._pendingSavePath;
        root._pendingSavePath = null;
        if (pending.folder === currentPath) {
          root.saveName = pending.name;
          Qt.callLater(root.accept);
        }
      } else if (status === "ready" && root._initialFile) {
        var index = indexOfPath(root._initialFile);
        if (index >= 0)
          requestSelection.click(index, Qt.NoModifier);
        root._initialFile = "";
      }
    }
  }

  FilePathResolver {
    id: typedPaths
    basePath: requestBrowser.currentPath
    mode: root.method
    directoryMode: root.options.directory === true
    multiple: root.method === "open" && root.options.multiple === true
    onFailed: reason => root._errorText = I18n.tr("widgets.file-picker." + reason)
    onResolved: function(result) {
      if (root.settled) return;
      if (result.action === "navigate") {
        requestBrowser.navigate(result.paths[0]);
        if (root.method === "open") root._openNameEdited = false;
        else if (root.method === "save") root.saveName = root._nameBeforeEdit;
        root.pathNavigation();
      } else if (result.action === "save") {
        var path = result.paths[0], folder = Paths.parent(path), name = Paths.leaf(path);
        if (!root._validName(name)) {
          root._errorText = I18n.tr("widgets.file-picker.invalid-name");
        } else if (folder === requestBrowser.currentPath) {
          root.saveName = name;
          root.accept();
        } else {
          requestBrowser.navigate(folder);
          root._pendingSavePath = {folder: folder, name: name};
        }
      } else if (result.action === "open") root._acceptResolved(result.paths, Paths.parent(result.paths[0]));
    }
  }
  signal pathNavigation()
  function submitPath(text, source) {
    if (_settled || _checking || _pendingReplace) return;
    _invalidate();
    typedPaths.resolve(text, source || "name");
  }
  function editOpenName(value) {
    openName = value;
    _openNameEdited = true;
    typedPaths.invalidate();
    _invalidate();
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
      saveFilterEnabled = prefs.saveFilter !== false;
      autoExtension = prefs.autoExtension !== false;
      if (method === "saveFiles")
        _saveFilesNames = (options.files || []).map(value => _decode(value, false));
      var folder = options.current_folder !== undefined ? _decode(options.current_folder, true) : "";
      var file = options.current_file !== undefined ? _decode(options.current_file, true) : "";
      if (file) {
        folder = browser.parentPath(file);
        _initialFile = file;
      }
      saveName = options.current_name !== undefined ? String(options.current_name) : (file ? file.slice(file.lastIndexOf("/") + 1) : "");
      _nameBeforeEdit = saveName;
      currentFilter = options.current_filter || (options.filters && options.filters.length ? options.filters[0] : null);
      var values = {};
      for (var choice of choices)
        values[choice[0]] = choice[3] || (choice[2].length ? choice[2][0][0] : "false");
      choiceValues = values;
      // Folder availability can change between requests in the same shell.
      // Memory owns that read; wait for its validated snapshot before choosing
      // an app/shared/home fallback, rather than navigating a stale cache hit.
      _waitingMemory = !folder;
      FileChooserMemory.refresh();
      if (folder)
        browser.navigate(folder);
      _namePolicyReady = true;
    } catch (e) {
      _errorText = String(e.message);
      _finish(2, {});
    }
  }

  Component.onCompleted: Qt.callLater(_initialize)
  Connections {
    target: FileChooserMemory
    function onReadyChanged() { Qt.callLater(root._initialize); }
    function onRefreshed() {
      if (root._waitingMemory && !root.settled) {
        root._waitingMemory = false;
        root.browser.navigate(FileChooserMemory.folderFor(root.appId));
      }
    }
  }

  function _invalidate() {
    ++_generation;
    _checking = false;
    _pendingReplace = "";
    _errorText = "";
    _approved = [];
    _snapshot = null;
  }

  function _invalidateName() {
    ++_nameGeneration;
    _nameChecking = false;
    _invalidate();
  }
  onSaveNameChanged: {
    _pendingSavePath = null;
    typedPaths.invalidate();
    _invalidateName();
  }
  function editSaveName(value) {
    saveName = value;
    _saveNameEdited = true;
  }
  function beginNameEdit() {
    if (_validName(saveName)) _nameBeforeEdit = saveName;
  }
  function clearFilters() {
    browser.filterText = "";
    _saveNameEdited = false;
  }
  function beginCreateFolder() {
    clearFilters();
    browser.beginCreateFolder();
  }
  Connections {
    target: requestBrowser
    function onFolderCreated(path) {
      requestSelection.click(requestBrowser.indexOfPath(path), Qt.NoModifier);
    }
  }
  onCurrentFilterChanged: {
    var previous = FileTypes.saveSuffixes(_previousNameFilter);
    _previousNameFilter = currentFilter;
    _invalidateName();
    if (_namePolicyReady && method === "save" && autoExtension && _validName(Paths.leaf(saveName))) {
      var leaf = Paths.leaf(saveName);
      var changed = saveName.slice(0, saveName.length - leaf.length) + SaveNames.changeType(leaf, previous, FileTypes.saveSuffixes(currentFilter));
      if (changed !== saveName)
        _prepareName(changed, false);
    }
  }
  onAutoExtensionChanged: _invalidateName()
  onChoiceValuesChanged: _invalidateName()
  Connections {
    target: requestSelection
    function onSelectedPathsChanged() {
      root._invalidate();
    }
    function onChosen(path) {
      typedPaths.invalidate();
      root._pendingSavePath = null;
      if (root.method === "open") root._openNameEdited = false;
      if (root.method === "save" && requestSelection.selectedPaths.length === 1 && requestSelection.selectedPaths[0] === path) {
        root._saveNameEdited = false;
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
    if (method === "open" && _openNameEdited) {
      submitPath(openName, "name");
      return;
    }
    if (method === "save" && (saveName.includes("/") || saveName === "~")) {
      submitPath(saveName, "name");
      return;
    }
    if (method === "save" && autoExtension && saveSuffixes.length && _validName(saveName)) {
      var prepared = SaveNames.append(saveName, saveSuffixes);
      if (prepared !== saveName) {
        _prepareName(prepared, true);
        return;
      }
    }
    _acceptResolved();
  }

  // Existence is checked outside the GUI thread, including targets hidden by
  // the listing's filters. Existing files retain their exact name; directories
  // never get turned into a different, apparently valid filename.
  function _prepareName(proposed, accepting) {
    var target = Paths.local(saveName, browser.currentPath, FilePlaces.home);
    if (!target.ok) { _errorText = I18n.tr("widgets.file-picker." + target.error); return; }
    _nameChecking = true;
    var job = nameFactory.createObject(root, {generation: ++_nameGeneration, original: saveName,
      proposed: proposed, accepting: accepting, target: target.path});
    job.running = true;
  }
  Component {
    id: nameFactory
    Process {
      property int generation
      property string original
      property string proposed
      property bool accepting
      property string target
      command: ["timeout", "5", "python3", "-c", `
import json, os, sys
path, original, proposed, accepting = json.loads(sys.argv[1])
preserve = os.path.lexists(path) if accepting else os.path.isdir(path)
print(json.dumps({'name': original if preserve else proposed}))
`, JSON.stringify([target, original, proposed, accepting])]
      stdout: StdioCollector { id: nameOutput }
      onExited: function(code) {
        if (!root.settled && generation === root._nameGeneration) {
          root._nameChecking = false;
          var result;
          try { result = JSON.parse(nameOutput.text); }
          catch (error) { result = null; }
          if (code === 0 && result && typeof result.name === "string") {
            root.saveName = result.name;
            if (accepting)
              root._acceptResolved();
          } else root._errorText = I18n.tr("widgets.file-picker.selection-check-failed");
        }
        destroy();
      }
    }
  }

  function _acceptResolved(resolvedPaths, typedFolder) {
    if (_settled || busy || _pendingReplace)
      return;
    _errorText = "";
    var paths = [];
    var folder = typedFolder || (method === "saveFiles" && selection.selectedPaths.length ? selection.selectedPaths[0] : browser.currentPath);
    if (method === "open") {
      paths = resolvedPaths || selection.selectedPaths.slice();
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
    var selectedChoices = [];
    for (var choice of choices) {
      var value = choiceValues[choice[0]];
      var allowed = choice[2].length ? choice[2].map(item => item[0]) : ["true", "false"];
      if (!allowed.includes(value)) {
        _errorText = I18n.tr("widgets.file-picker.invalid-choice", {name: choice[1]});
        return;
      }
      selectedChoices.push([choice[0], value]);
    }
    var uris = [];
    for (var path of paths) {
      var converted = PortalPaths.pathToUri(path);
      if (!converted.ok) {
        _errorText = converted.error;
        _finish(2, {});
        return;
      }
      uris.push(converted.uri);
    }
    // One immutable-by-ownership input snapshot drives checks and the reply.
    // URI/name preparation happens before the final filesystem check, not after.
    _snapshot = {folder: folder, paths: paths, uris: uris, method: method, directory: options.directory === true, choices: selectedChoices, filter: currentFilter};
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
      property bool finalCheck: false
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
          root._validated(result, finalCheck);
        }
        destroy();
      }
    }
  }

  function _validate(finalCheck) {
    if (_settled || !_snapshot)
      return;
    _checking = true;
    var check = validationFactory.createObject(root, {generation: ++_generation, finalCheck: finalCheck === true, input: [_snapshot.method, _snapshot.directory, _snapshot.folder, _snapshot.paths]});
    check.running = true;
  }

  function _validated(result, finalCheck) {
    if (_settled || !_snapshot)
      return;
    if (!result.ok) {
      _errorText = I18n.tr("widgets.file-picker." + result.error);
      return;
    }
    var approved = Object.create(null);
    for (var path of _approved)
      approved[path] = true;
    _replacements = result.replacements.filter(path => !approved[path]);
    if (_replacements.length) {
      _pendingReplace = _replacements[0];
      return;
    }
    // A destination can appear after the initial check or while another target
    // awaits approval. Re-read every final path immediately before the reply.
    if (!finalCheck) {
      _validate(true);
      return;
    }
    var results = {uris: _snapshot.uris, writable: result.writable, choices: _snapshot.choices};
    if (_snapshot.filter)
      results.current_filter = _snapshot.filter;
    var folder = _snapshot.folder;
    var prefs = {view: viewMode, sortKey: browser.sortKey, sortDescending: browser.sortDescending, showHidden: browser.showHidden, saveFilter: saveFilterEnabled, autoExtension: autoExtension};
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
  function declineReplace() {
    if (_settled || !_pendingReplace)
      return;
    _invalidate();
  }

  function _finish(response, results) {
    if (_settled)
      return;
    _settled = true;
    _checking = false;
    _nameChecking = false;
    ++_nameGeneration;
    typedPaths.invalidate();
    _pendingSavePath = null;
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
