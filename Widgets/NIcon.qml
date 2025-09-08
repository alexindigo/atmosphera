import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  text: "\uEE15" // fallback/default to skull icon
  font.family: "bootstrap-icons"
  font.pointSize: Style.fontSizeL * scaling
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
