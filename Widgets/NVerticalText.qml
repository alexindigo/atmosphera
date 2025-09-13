import QtQuick
import qs.Commons
import qs.Services

Column {
  id: root

  property string text: ""
  property real fontSize: Style.fontSizeXS
  property color color: Color.mOnSurface
  property int fontWeight: Style.fontWeightBold

  spacing: -2 * scaling

  Repeater {
    model: root.text.split("")
    NText {
      text: modelData
      font.pointSize: root.fontSize
      font.weight: root.fontWeight
      font.family: Settings.data.ui.fontDefault
      color: root.color
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
