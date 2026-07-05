import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Text {
  id: root

  property var icon: Icon.close
  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true

  readonly property var _resolved: {
    if (typeof icon === "string") {
      var entry = IconRegistry.resolved[icon];
      if (entry === undefined) {
        Logger.w("NIcon", "\"" + icon + "\" not found in icons, falling back to \"" + Icons.defaultIcon + "\"");
        return IconRegistry.resolved[Icons.defaultIcon];
      }
      return entry;
    }
    return icon;
  }

  visible: _resolved !== undefined && _resolved !== null

  text: _resolved && _resolved.char ? _resolved.char : ""
  font.family: _resolved && _resolved.fontFamily ? _resolved.fontFamily : Icons.fontFamily
  font.pointSize: Math.max(1, applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter

  // SVG path — colored Rectangle shaped by SVG alpha mask
  Item {
    id: svgContainer
    anchors.centerIn: parent
    width: parent.implicitHeight
    height: parent.implicitHeight
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
