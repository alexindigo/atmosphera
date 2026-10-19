import QtQuick
import QtQuick.Pdf

// Loaded by URL only after FilePreview has successfully probed this module.
Item {
  id: root
  property url source
  readonly property string previewState: pdfDocument.status === PdfDocument.Ready && page.status === Image.Ready ? "ready" : pdfDocument.status === PdfDocument.Error ? "error" : "loading"
  PdfDocument { id: pdfDocument; source: root.source }
  Rectangle { anchors.centerIn: page; width: page.paintedWidth; height: page.paintedHeight; color: "white" }
  PdfPageImage { id: page; anchors.fill: parent; document: pdfDocument; currentFrame: 0; fillMode: Image.PreserveAspectFit; asynchronous: true }
}
