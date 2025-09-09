import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  property string icon: "balloon"

  text: Bootstrap.icons[icon]
  font.family: "bootstrap-icons"
  font.pointSize: Style.fontSizeL * scaling
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
