import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Text {
  id: root

  property string icon: Icons.defaultIcon
  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true

  visible: (icon !== undefined) && (icon !== "")

  property string _resolvedChar: ""
  property string _resolvedFontFamily: Icons.fontFamily

  Component.onCompleted: _resolveIcon()
  onIconChanged: _resolveIcon()

  function _resolveIcon() {
    if ((icon === undefined) || (icon === "")) {
      root.text = "";
      return;
    }

    var resolved = IconRegistry.resolve(icon);
    if (resolved && resolved.type === "font") {
      root._resolvedChar = resolved.char;
      root._resolvedFontFamily = Icons.fontFamily;
      root.text = resolved.char;
      root.visible = true;
      return;
    }

    if (Icons.get(icon) === undefined) {
      Logger.w("Icon", `"${icon}"`, "doesn't exist in the icons font");
      Logger.callStack();
      root.text = Icons.get(Icons.defaultIcon);
      return;
    }
    root.text = Icons.get(icon);
  }

  font.family: root._resolvedFontFamily
  font.pointSize: Math.max(1, applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter
}
