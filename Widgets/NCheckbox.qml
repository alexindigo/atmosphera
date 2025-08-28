import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root

  // Public API (mirrors NToggle but compact)
  property string label: ""
  property string description: ""
  property bool checked: false
  property bool hovering: false
  // Smaller default footprint than NToggle
  property int baseSize: Math.max(Style.baseWidgetSize * 0.8, 14)

  signal toggled(bool checked)
  signal entered
  signal exited

  Layout.fillWidth: true

  NLabel {
    label: root.label
    description: root.description
  }

  Rectangle {
    id: box

    implicitWidth: root.baseSize * scaling
    implicitHeight: root.baseSize * scaling
    radius: Math.max(2 * scaling, Style.radiusXS * scaling)
    color: root.checked ? Color.mPrimary : Color.mSurface
    border.color: root.checked ? Color.mPrimary : Color.mOutline
    border.width: Math.max(1, Style.borderM * scaling)

    NIcon {
      visible: root.checked
      anchors.centerIn: parent
      text: "check"
      color: Color.mOnPrimary
      font.pointSize: Math.max(Style.fontSizeS, root.baseSize * 0.7) * scaling
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onEntered: { hovering = true; root.entered() }
      onExited: { hovering = false; root.exited() }
      onClicked: root.toggled(!root.checked)
    }

    Behavior on color { ColorAnimation { duration: Style.animationFast } }
    Behavior on border.color { ColorAnimation { duration: Style.animationFast } }
  }
}


