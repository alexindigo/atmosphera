pragma ComponentBehavior: Bound

import QtQuick
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
    active: root.visible && root._resolved?.type === "svg"
    sourceComponent: NImage {
      source: root._resolved?.source ?? ""
      alphaMaskTint: root.color
      onImageStateChanged: {
        if (imageState === "unavailable")
          Logger.w("AtmoIcon", "Icon file", source, "could not be displayed:", errorReason);
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
