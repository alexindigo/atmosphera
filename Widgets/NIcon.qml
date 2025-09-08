import QtQuick
import qs.Commons
import qs.Widgets
import QtQuick.Layouts

Text {
  // Optional layout nudge for optical alignment when used inside Layouts
  property real layoutTopMargin: 0
  text: "question_mark"
  font.family: "bootstrap-icons"
  font.pointSize: Style.fontSizeL * scaling
  font.variableAxes: {
    "wght"// slightly bold to ensure all lines looks good
    : (Font.Normal + Font.Bold) / 2.5
  }
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
  Layout.topMargin: layoutTopMargin
}
