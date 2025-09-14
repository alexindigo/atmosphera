import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root

  property string title: ""
  property string description: ""
  property real bottomMargin: Style.marginL * scaling

  spacing: Style.marginXXS * scaling
  Layout.fillWidth: true

  NText {
    text: root.title
    font.pointSize: Style.fontSizeXXL * scaling
    font.weight: Style.fontWeightBold
    color: Color.mSecondary
    Layout.bottomMargin: Style.marginS * scaling
    visible: root.title !== ""
  }

  NText {
    text: root.description
    font.pointSize: Style.fontSizeM * scaling
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.bottomMargin: root.bottomMargin
    visible: root.description !== ""
  }
}
