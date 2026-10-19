import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
import qs.Services.UI
import qs.Modules.FileChooser
import "../../../Helpers/PortalPaths.js" as PortalPaths

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("FILECHOOSER_UI_ROOT")
  property var request: null
  property var replies: []
  Component { id: requests; FileRequest {} }
  Loader {
    id: windowLoader
    active: root.request !== null
    sourceComponent: FileChooserWindow { request: root.request }
  }
  function open(mode) {
    windowLoader.active = false;
    if (request) request.destroy();
    replies = [];
    var options = {
      title: mode === "save" ? "Save field notes" : "Choose a file",
      current_folder: PortalPaths.encodeBytePath(mode === "empty" ? base + "/Empty" : base).bytes,
      multiple: mode !== "save",
      current_name: "Field notes.md",
      accept_label: mode === "save" ? "Save" : "Upload",
      filters: [["All files", [[0, "*"]]], ["Images", [[1, "image/*"]]], ["Text", [[0, "*.md"], [0, "*.txt"]]]],
      choices: [["quality", "Quality", [["original", "Original"], ["compact", "Compact"]], "original"], ["metadata", "Keep metadata", [], "true"]]
    };
    request = requests.createObject(root, {method: mode === "save" ? "save" : "open", options: options, appId: "dev.filechooser"});
    request.finished.connect((response, results) => { root.replies = root.replies.concat([{response: response, results: results}]); });
    windowLoader.active = true;
  }
  function snapshot() {
    var window = windowLoader.item;
    var selected = request ? request.selection : null;
    var entry = request ? request.browser.entry(selected.cursor) : null;
    return JSON.stringify({
      ready: !!request && request.browser.status === "ready",
      path: request ? request.browser.currentPath : "",
      error: request ? request.errorText || request.browser.errorText : "",
      count: request ? request.browser.count : 0,
      cursor: selected ? selected.cursor : -1,
      name: entry ? entry.name : "",
      selected: selected ? selected.selectedPaths : [],
      view: request ? request.viewMode : "",
      sort: request ? request.browser.sortKey : "",
      descending: request ? request.browser.sortDescending : false,
      filter: request && request.currentFilter ? request.currentFilter[0] : "",
      choices: request ? request.choiceValues : {},
      hidden: request ? request.browser.showHidden : false,
      saveName: request ? request.saveName : "",
      replace: request ? request.pendingReplace : "",
      settled: request ? request.settled : false,
      focus: window ? window.focusArea : "",
      focusedControl: window ? window.focusedControl : "",
      motion: window ? window.previewMotion : {},
      nameSelection: window ? window.nameSelection : [],
      columnGeometry: window ? window.columnGeometry : {},
      choiceCenters: window ? window.choiceGeometry() : [],
      preview: window ? window.quickLookOpen : false,
      pathEditing: window ? window.pathEditing : false,
      kind: window ? window.preview.kind : "",
      previewStatus: window ? window.preview.status : "",
      previewText: window ? window.preview.text.slice(0, 100) : "",
      pdfAvailable: window ? window.preview.pdfAvailable : false,
      rendered: window && window.previewRenderer ? window.previewRenderer.previewState : "",
      frame: window && window.previewRenderer && window.preview.kind === "animatedImage" ? window.previewRenderer.frame : -1,
      frames: window && window.previewRenderer && window.preview.kind === "animatedImage" ? window.previewRenderer.frames : 0,
      position: window && window.previewRenderer && ["video", "audio"].includes(window.preview.kind) ? window.previewRenderer.position : -1,
      replies: replies
    });
  }
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:atmosphera-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  Component.onCompleted: Qt.callLater(() => open("open"))
  IpcHandler {
    target: "filechooserHarness"
    function open(mode: string): void { root.open(mode); }
    function state(): string { return root.snapshot(); }
    function list(): void { root.request.viewMode = "list"; root.request.browser.sortKey = "modified"; root.request.browser.sortDescending = true; windowLoader.item.focusListing(); }
    function grid(): void { root.request.viewMode = "grid"; windowLoader.item.focusListing(); }
    function focusListing(): void { windowLoader.item.focusListing(); }
    function failFolder(): void { root.request.browser.navigate(root.base + "/Missing"); }
    function reducedMotion(value: bool): void { Settings.data.general.animationDisabled = value; }
    function quit(): void { Qt.quit(); }
  }
}
