import QtQuick
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
      // Compat path for Noctalia call sites that pass strings
      return IconRegistry.resolved[icon];
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
}
