import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  text: "\uF706" // fallback/default to balloon icon
  font.family: "bootstrap-icons"
  font.pointSize: Style.fontSizeL * scaling
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
