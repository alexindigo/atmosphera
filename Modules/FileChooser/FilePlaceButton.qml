import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// A place has separate icon and label roles. Selection colors its surface;
// it never recolors the folder glyph through a shared button content color.
Item {
  id: root
  NInputGuard {
    target: root
  }
  property string text: ""
  property var icon: Icon.filepickerFolder
  property bool selected: false
  property string tooltipText: ""
  signal clicked
  implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.description: tooltipText
  Accessible.onPressAction: clicked()
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()
  Rectangle {
    anchors.fill: parent
    radius: Style.iRadiusS
    color: root.selected ? Qt.alpha(AtmoColor.mPrimary, 0.18) : pointer.containsMouse ? Qt.alpha(AtmoColor.mOnSurface, 0.05) : "transparent"
    border.width: root.activeFocus ? Style.borderM : 0
    border.color: AtmoColor.mPrimary
  }
  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.marginM
    anchors.rightMargin: Style.marginM
    spacing: Style.marginS
    AtmoIcon {
      icon: root.icon
      pointSize: Style.fontSizeM
      color: AtmoColor.mOnSurfaceVariant
    }
    NText {
      Layout.fillWidth: true
      text: root.text
      pointSize: Style.fontSizeM
      color: AtmoColor.mOnSurface
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.tooltipText)
                 TooltipService.show(root, root.tooltipText)
    onExited: if (root.tooltipText)
                TooltipService.hide()
    onClicked: {
      if (root.tooltipText)
        TooltipService.hide();
      root.forceActiveFocus();
      root.clicked();
    }
  }
}
