pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Renders an icon from the shell's icon sets (IconRegistry).
// Font-glyph entries render as text; SVG entries render in the tint color
// with the alpha of the admitted image.
//
// Root is an Item (not Text) so implicitWidth is bindable: SVG entries have
// no text, so a Text root would report implicitWidth 0 and collapse in
// layouts (icons losing all layout padding).
Item {
  id: root

  property var icon: Icon.close
  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true
  property color color: AtmoColor.mOnSurface

  // Text-compat forwarded properties (consumers used these when the root was a Text)
  property alias verticalAlignment: textItem.verticalAlignment
  property alias horizontalAlignment: textItem.horizontalAlignment
  property alias font: textItem.font
  readonly property real contentHeight: textItem.contentHeight
  readonly property real contentWidth: textItem.contentWidth

  readonly property var _resolved: {
    if (typeof icon === "string") {
      const entry = IconRegistry.resolved[icon];
      if (entry === undefined) {
        // An empty name is an unset icon, not a missing one: same fallback,
        // no warning (it was logged once per instance, e.g. per launcher row).
        if (icon !== "")
          Logger.w("AtmoIcon", "\"" + icon + "\" not found in icons, falling back to \"" + Icons.defaultIcon + "\"");
        return IconRegistry.resolved[Icons.defaultIcon];
      }
      return entry;
    }
    return icon;
  }

  // Square box for SVG entries (line height); natural glyph advance for font entries
  implicitWidth: root._resolved?.type === "svg" ? textItem.implicitHeight : textItem.implicitWidth
  implicitHeight: textItem.implicitHeight

  visible: _resolved !== undefined && _resolved !== null

  Text {
    id: textItem
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root._resolved && root._resolved.char ? root._resolved.char : ""
    font.family: root._resolved && root._resolved.fontFamily ? root._resolved.fontFamily : Icons.fontFamily
    font.pointSize: Math.max(1, root.applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
    color: root.color
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  // Icon-set files (including user icon sets) are decoded by the shared image
  // owner. A set file that cannot be displayed is a labelled failure.
  readonly property NImage maskImage: mask.item as NImage
  readonly property bool failed: maskImage?.imageState === "unavailable"
  readonly property string errorReason: failed ? maskImage.errorReason : ""
  Accessible.description: errorReason

  Loader {
    id: mask
    anchors.centerIn: parent
    width: root.implicitHeight
    height: root.implicitHeight
    // Its pixels are captured below, never presented in their original colors.
    opacity: 0
    active: root.visible && root._resolved?.type === "svg"
    sourceComponent: NImage {
      source: root._resolved?.source ?? ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      onImageStateChanged: {
        if (imageState === "unavailable")
          Logger.w("AtmoIcon", "Icon file", source, "could not be displayed:", errorReason);
      }
    }
  }

  Loader {
    anchors.fill: mask
    active: root.maskImage !== null
    sourceComponent: Canvas {
      contextType: "2d"
      readonly property NImage admitted: root.maskImage
      readonly property bool ready: available && visible && (Window.window?.visible ?? false) && admitted?.imageState === "ready"
      readonly property int generation: admitted?.generation ?? 0
      readonly property color tint: root.color
      property int captureRevision: 0
      property var pixels: null
      property bool painted: false
      opacity: painted ? 1 : 0

      function invalidate(): void {
        ++captureRevision;
        if (pixels)
          unloadImage(pixels.url);
        pixels = null;
        painted = false;
        requestPaint();
        if (ready)
          Qt.callLater(capture);
      }

      function capture(): void {
        if (!ready)
          return;
        const revision = captureRevision;
        // Sample the already rendered NImage; the Canvas URL is Qt's in-memory
        // grab result, never the original source or a fresh decode of it.
        admitted.grabToImage(result => {
          if (ready && revision === captureRevision) {
            pixels = result;
            loadImage(result.url);
            requestPaint();
          }
        });
      }

      onReadyChanged: invalidate()
      onAdmittedChanged: invalidate()
      onGenerationChanged: invalidate()
      onCanvasSizeChanged: invalidate()
      onImageLoaded: requestPaint()
      onTintChanged: requestPaint()

      onPaint: {
        const ctx = context;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        if (!pixels || !isImageLoaded(pixels.url))
          return;
        // Source-in is supported by the raster painter on both Qt Quick
        // backends. ShaderEffect-based masks disappear on the software backend.
        ctx.drawImage(pixels.url.toString(), 0, 0, width, height);
        ctx.globalCompositeOperation = "source-in";
        ctx.fillStyle = tint;
        ctx.fillRect(0, 0, width, height);
        ctx.globalCompositeOperation = "source-over";
        painted = true;
      }
    }
  }

  // Drawn without another icon lookup: the failure must not recurse.
  Rectangle {
    anchors.centerIn: parent
    width: Math.max(2, root.implicitHeight * 0.7)
    height: width
    visible: root.failed
    radius: width / 4
    color: "transparent"
    border.width: Math.max(1, width / 8)
    border.color: AtmoColor.mError
  }
}
