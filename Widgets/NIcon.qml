import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  readonly property string defaultIcon: "balloon"
  property string icon: defaultIcon

  text: {
    if (Bootstrap.icons[icon] === undefined) {
      Logger.warn("Icon", `"${icon}"`, "doesn't exist in the bootstrap font")
      Logger.callStack()
      return Bootstrap.icons[defaultIcon]
    }
    return Bootstrap.icons[icon]
  }
  font.family: "bootstrap-icons"
  font.pointSize: Style.fontSizeL * scaling
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
