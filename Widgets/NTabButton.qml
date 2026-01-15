import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  property string text: ""
  property bool checked: false
  property int tabIndex: 0
  property real pointSize: Style.fontSizeM
  property bool isFirst: false
  property bool isLast: false
  // Internal state
  property bool isHovered: false

  signal clicked

  // Sizing
  Layout.fillHeight: true
  implicitWidth: tabText.implicitWidth + Style.marginM * 2

  // Styling
  radius: (isFirst || isLast) ? Style.iRadiusM : 0
  color: root.isHovered ? Color.mHover : (root.checked ? Color.mPrimary : Color.mSurface)
  border.color: Color.mOutline
  border.width: Style.borderS

  // Squares off the RIGHT side of FIRST tab.
  Item {
    visible: root.isFirst
    width: root.radius
    anchors {
      right: parent.right
      top: parent.top
      bottom: parent.bottom
    }
    clip: true

    Rectangle {
      width: parent.width + border.width
      anchors {
        right: parent.right
        top: parent.top
        bottom: parent.bottom
      }

      color: root.color
      border.width: root.border.width
      border.color: root.border.color
    }
  }

  // Squares off the LEFT side of LAST tab.
  Item {
    visible: root.isLast
    width: root.radius
    anchors {
      left: parent.left
      top: parent.top
      bottom: parent.bottom
    }
    clip: true

    Rectangle {
      width: parent.width + border.width
      anchors {
        left: parent.left
        top: parent.top
        bottom: parent.bottom
      }

      color: root.color
      border.width: root.border.width
      border.color: root.border.color
    }
  }

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  NText {
    id: tabText
    anchors {
      left: parent.left
      right: parent.right
      verticalCenter: parent.verticalCenter
      leftMargin: Style.marginS
      rightMargin: Style.marginS
    }
    text: root.text
    pointSize: root.pointSize
    font.weight: Style.fontWeightSemiBold
    color: root.isHovered ? Color.mOnHover : (root.checked ? Color.mOnPrimary : Color.mOnSurface)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.isHovered = true
    onExited: root.isHovered = false
    onClicked: {
      root.clicked();
      // Update parent NTabBar's currentIndex
      if (root.parent && root.parent.parent && root.parent.parent.currentIndex !== undefined) {
        root.parent.parent.currentIndex = root.tabIndex;
      }
    }
  }
}
