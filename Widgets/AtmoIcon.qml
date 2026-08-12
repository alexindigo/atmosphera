import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Renders an icon from the shell's icon sets (IconRegistry).
// Font-glyph entries render as text; SVG entries render as a colored
// rectangle shaped by the SVG alpha mask.
//
// Root is an Item (not Text) so implicitWidth is bindable: SVG entries have
// no text, so a Text root would report implicitWidth 0 and collapse in
// layouts (icons losing all layout padding).
Item {
  id: root

  property var icon: Icon.close
  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true
  property color color: Color.mOnSurface

  // Text-compat forwarded properties (consumers used these when the root was a Text)
  property alias verticalAlignment: textItem.verticalAlignment
  property alias horizontalAlignment: textItem.horizontalAlignment
  property alias font: textItem.font
  readonly property real contentHeight: textItem.contentHeight
  readonly property real contentWidth: textItem.contentWidth

  readonly property var _resolved: {
    if (typeof icon === "string") {
      var entry = IconRegistry.resolved[icon];
      if (entry === undefined) {
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
    anchors.centerIn: parent
    text: root._resolved && root._resolved.char ? root._resolved.char : ""
    font.family: root._resolved && root._resolved.fontFamily ? root._resolved.fontFamily : Icons.fontFamily
    font.pointSize: Math.max(1, root.applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
    color: root.color
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  // SVG path — colored Rectangle shaped by SVG alpha mask
  Item {
    id: svgContainer
    anchors.centerIn: parent
    width: root.implicitHeight
    height: root.implicitHeight
    visible: root._resolved?.type === "svg"

    Rectangle {
      anchors.fill: parent
      color: root.color
    }

    layer.enabled: root._resolved?.type === "svg"
    layer.effect: MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.5
      maskSpreadAtMin: 0.5
      maskSource: ShaderEffectSource {
        hideSource: true
        sourceItem: Image {
          width: svgContainer.width
          height: svgContainer.height
          source: root._resolved?.source ?? ""
          fillMode: Image.PreserveAspectFit
          smooth: true
          sourceSize.width: svgContainer.width * Screen.devicePixelRatio
          sourceSize.height: svgContainer.height * Screen.devicePixelRatio
        }
      }
    }
  }
}
