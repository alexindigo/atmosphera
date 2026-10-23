import QtQuick
import qs.Commons
import qs.Widgets

// Column labels occupy the same bounds as row text, without button padding.
Item {
  id: root
  property Item keyFocusOwner: null
  NInputGuard {
    target: root
    focusOwner: root.keyFocusOwner
  }
  property string text
  property int alignment: Text.AlignLeft
  signal clicked
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.onPressAction: clicked()
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: Style.iRadiusXS
    border.width: root.activeFocus ? Style.borderM : 0
    border.color: AtmoColor.mPrimary
  }
  NText {
    anchors.fill: parent
    text: root.text
    horizontalAlignment: root.alignment
    pointSize: Style.fontSizeM
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
