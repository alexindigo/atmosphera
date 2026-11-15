import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../Helpers/PortalPaths.js" as PortalPaths
import "FilePaths.js" as Paths

// The only mutation owner. Browser supplies its live filesystem projection;
// views only send intents. Completion is published after that projection agrees.
Scope {
  id: root
  required property var browser
  property var selection: null
  readonly property bool busy: worker.running || _reconcile !== null
  readonly property bool available: !busy && browser.status === "ready"
  property bool creatingFolder: false
  property string newFolderName: ""
  property string createFolderError: ""
  readonly property bool createFolderBusy: busy && _kind === "create"
  property string renamePath: ""
  readonly property bool renaming: renamePath !== ""
  property string renameName: ""
  property string renameError: ""
  property string errorText: ""
  readonly property var pendingDelete: _pendingDelete ? _pendingDelete.paths : []
  property var _pendingDelete: null
  property var _reconcile: null
  property var _job: null
  property string _kind: ""
  property int _generation: 0
  signal folderCreated(string path)
  signal renamed(string previous, string path)
  signal renameApplied(string previous, string path)
  signal completed()

  function targets() {
    if (!selection) return [];
    var item = browser.entry(selection.cursor);
    if (!item) return [];
    return selection.selectedPaths.includes(item.path) ? selection.selectedPaths.slice() : [item.path];
  }
  function context(index) {
    if (!selection || busy) return;
    var item = browser.entry(index);
    if (item && !selection.selectedPaths.includes(item.path)) selection.click(index, Qt.NoModifier);
    else if (item) selection.moveTo(index, false, true);
    else selection.background(Qt.NoModifier);
  }
  function _valid(name) { return typeof name === "string" && name !== "" && ![".", ".."].includes(name) && !name.includes("/") && !name.includes("\u0000"); }
  function _start(kind, paths, extra) {
    if (!available || !browser.currentPath || !paths.length) return;
    var folder = browser.currentPath;
    if (paths.some(path => Paths.parent(path) !== folder)) return;
    errorText = "";
    _kind = kind;
    _job = Object.assign({kind: kind, folder: folder, names: paths.map(Paths.leaf), generation: _generation}, extra || {});
    worker.running = true;
    worker.write(JSON.stringify(_job));
    worker.stdinEnabled = false;
  }
  function beginCreateFolder() {
    if (!available || !browser.currentPath) return;
    cancelRename();
    browser.filterText = "";
    newFolderName = I18n.tr("widgets.file-picker.new-folder");
    createFolderError = "";
    creatingFolder = true;
  }
  function cancelCreateFolder() { creatingFolder = false; createFolderError = ""; }
  function createFolder(name) {
    if (busy) return;
    newFolderName = String(name);
    creatingFolder = true;
    if (!_valid(name)) { createFolderError = I18n.tr("widgets.file-picker.create-folder-invalid"); return; }
    _start("create", [Paths.join(browser.currentPath, name)]);
  }
  function beginRename() {
    var paths = targets();
    if (!available || paths.length !== 1) return;
    cancelCreateFolder();
    renamePath = paths[0];
    renameName = Paths.leaf(renamePath);
    renameError = "";
  }
  function cancelRename() { renamePath = ""; renameError = ""; }
  function rename(name) {
    if (busy || !renaming) return;
    renameName = String(name);
    if (!_valid(name)) { renameError = I18n.tr("widgets.file-picker.create-folder-invalid"); return; }
    _start("rename", [renamePath], {name: name});
  }
  function trash() { _start("trash", targets()); }
  function requestDelete() { _start("inspect", targets()); }
  function declineDelete() { _pendingDelete = null; }
  function confirmDelete() {
    if (!_pendingDelete || busy) return;
    var pending = _pendingDelete;
    _pendingDelete = null;
    _start("delete", pending.paths, {identities: pending.identities});
  }
  function copyPath(background) {
    if (clipboard.running) return;
    var paths = background ? [browser.currentPath] : targets();
    if (!paths.length) return;
    clipboard.running = true;
    clipboard.write(paths.join("\n"));
    clipboard.stdinEnabled = false;
  }
  onNewFolderNameChanged: createFolderError = ""
  onRenameNameChanged: renameError = ""
  function _message(result) {
    var errors = result.errors || [{reason: result.reason || "unavailable"}];
    return errors.map(error => (error.name ? error.name + ": " : "") + I18n.tr("widgets.file-picker.operation-" + error.reason) + (error.detail ? " " + error.detail : "")).join("\n");
  }
  function _finish(result, code) {
    var job = _job;
    if (!job || job.generation !== _generation || job.folder !== browser.currentPath) return;
    if (code !== 0) result = {ok: false, reason: "unavailable"};
    if (job.kind === "inspect") {
      if (result.ok) _pendingDelete = {paths: job.names.map(name => Paths.join(job.folder, name)), identities: result.identities};
      else errorText = _message(result);
      return;
    }
    var completedNames = result.completed || [];
    if (completedNames.length) {
      if ((job.kind === "rename" ? job.name : completedNames[0]).startsWith(".")) browser.showHidden = true;
      // A successful rename must remain visible even when its new name does not
      // match the previous filter. Request owns the Save-name filter projection.
      if (job.kind === "rename") browser.filterText = "";
      if (job.kind === "rename") renameApplied(Paths.join(job.folder, job.names[0]), Paths.join(job.folder, job.name));
    }
    // Failure is completion too. Keep the operation busy and publish its error
    // only after the refreshed projection settles, so the next submission is
    // never offered while _start() would reject it as unavailable.
    _reconcile = {job: job, completed: completedNames, result: result};
    // Refresh even after partial failures; never fake an optimistic model row.
    browser.refresh();
  }
  function _reconciled() {
    if (!_reconcile || browser.status === "loading") return;
    var task = _reconcile, job = task.job;
    var path = Paths.join(job.folder, job.kind === "rename" ? job.name : job.names[0]);
    // Ready is a freshly scanned filesystem snapshot, not a promise that the
    // target is visible: a renamed suffix may no longer match the type filter,
    // or another process may have removed/recreated an entry in the meantime.
    _reconcile = null;
    if (!task.result.ok) {
      if (job.kind === "create") {
        var reason = ((task.result.errors || [])[0] || task.result).reason;
        if (!["invalid", "exists", "permission", "readonly", "long"].includes(reason)) reason = "unavailable";
        createFolderError = I18n.tr("widgets.file-picker.create-folder-" + reason);
      } else if (job.kind === "rename") renameError = _message(task.result);
      else errorText = _message(task.result);
    }
    if (!task.completed.length) return;
    if (browser.status !== "ready") { errorText = browser.errorText; completed(); return; }
    if (job.kind === "create") { creatingFolder = false; folderCreated(path); }
    else if (job.kind === "rename") { renamePath = ""; renamed(Paths.join(job.folder, job.names[0]), path); }
    completed();
  }
  Connections {
    target: root.browser
    function onCurrentPathChanged() {
      root._generation++;
      root.cancelCreateFolder(); root.cancelRename(); root.declineDelete(); root._reconcile = null; root.errorText = "";
    }
    function onListingChanged() { Qt.callLater(root._reconciled); }
    function onStatusChanged() { Qt.callLater(root._reconciled); }
  }
  Process {
    id: worker
    command: ["timeout", "30", "python3", PortalPaths.uriToPath(Qt.resolvedUrl("../../Scripts/python/file-operations.py").toString()).path]
    onRunningChanged: if (!running) stdinEnabled = true
    stdinEnabled: true
    stdout: StdioCollector { id: output }
    onExited: code => {
      var result;
      try { result = JSON.parse(output.text); }
      catch (error) { result = {ok: false, reason: "unavailable"}; }
      root._finish(result, code);
    }
  }
  Process {
    id: clipboard
    command: ["timeout", "5", "wl-copy", "--type", "text/plain;charset=utf-8"]
    stdinEnabled: true
    onRunningChanged: if (!running) stdinEnabled = true
    onExited: code => { if (code !== 0) root.errorText = I18n.tr("widgets.file-picker.operation-clipboard"); }
  }
}
