import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  property string icon: Icons.defaultIcon
  property string family: Icons.fontFamily

  visible: (icon !== undefined) && (icon !== "")
  text: {
    if ((icon === undefined) || (icon === "")) {
      return ""
    }
    if (Icons.get(icon) === undefined) {
      Logger.warn("Icon", `"${icon}"`, "doesn't exist in the icons font")
      Logger.callStack()
      return Icons.get(defaultIcon)
    }
    return Icons.get(icon)
  }
  font.family: family
  font.pointSize: Style.fontSizeL * scaling
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
