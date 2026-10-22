import QtQuick
import Quickshell
import "../../Helpers/OwnedProcess.js" as OwnedProcess
import "FilePdfProbe.js" as PdfProbe
import qs.Commons

Scope {
  id: root

  // A browser entry (plus an optional kind). No listing or selection is copied.
  property var item: null
  readonly property string kind: item && !item.directory ? (item.kind || FileTypes.previewKind(item.name || item.path)) : "none"
  readonly property string path: item ? item.path : ""
  readonly property string status: _status
  readonly property string text: _text
  readonly property bool truncated: _truncated
  readonly property string errorText: _status === "error" ? I18n.tr("widgets.file-picker.preview-unavailable") : ""
  readonly property bool pdfAvailable: _pdfAvailable
  readonly property bool pdfDetectionDone: _pdfDetectionDone
  property string _status: "idle"
  property string _text: ""
  property bool _truncated: false
  property bool _pdfAvailable: false
  property bool _pdfDetectionDone: false
  property int _generation: 0

  function _load() {
    var generation = ++_generation;
    // Consume the input snapshot, not sibling derived bindings: QML does not
    // promise that path/kind bindings update before onItemChanged runs.
    var nextPath = item ? item.path : "";
    var nextKind = item && !item.directory ? (item.kind || FileTypes.previewKind(item.name || item.path)) : "none";
    _text = "";
    _truncated = false;
    if (!nextPath) {
      _status = "idle";
      return;
    }
    if (nextKind !== "text") {
      _status = "ready";
      return;
    }
    _status = "loading";
    OwnedProcess.run(root, ["timeout", "5", "python3", "-B", Quickshell.shellDir + "/Scripts/python/src/filechooser/preview-text.py", nextPath], null, function (result) {
      if (generation !== root._generation)
        return;
      try {
        var content = JSON.parse(result.stdout);
        if (!result.success || !content.ok || typeof content.text !== "string")
          throw new Error("preview unavailable");
        root._text = content.text;
        root._truncated = content.truncated === true;
        root._status = "ready";
      } catch (error) {
        root._status = "error";
      }
    });
  }

  onItemChanged: _load()
  Component.onCompleted: {
    // A dynamic import keeps QtPdf genuinely optional on a real installation.
    // Probe once for this picker; decoder failures still fall back in the view.
    try {
      var document = PdfProbe.create(root);
      _pdfAvailable = !!document;
      if (document)
        document.destroy();
    } catch (error) {
      Logger.i("FilePreview", "QtPdf unavailable; using file information", String(error));
    }
    _pdfDetectionDone = true;
  }
}
