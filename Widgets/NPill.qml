import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Services

Item {
  id: root

  property string icon: ""
  property string text: ""
  property string tooltipText: ""
  property real sizeRatio: 0.8
  property bool autoHide: false
  property bool forceOpen: false
  property bool disableOpen: false
  property bool rightOpen: false
  property bool hovered: false
  property real fontSize: Style.fontSizeXS

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  signal shown
  signal hidden
  signal entered
  signal exited
  signal clicked
  signal rightClicked
  signal middleClicked
  signal wheel(int delta)

  // Dynamic sizing based on loaded component
  width: pillLoader.item ? pillLoader.item.width : 0
  height: pillLoader.item ? pillLoader.item.height : 0

  // Loader to switch between vertical and horizontal pill implementations
  Loader {
    id: pillLoader
    sourceComponent: isVerticalBar ? verticalPillComponent : horizontalPillComponent

    Component {
      id: verticalPillComponent
      NPillVertical {
        icon: root.icon
        text: root.text
        tooltipText: root.tooltipText
        sizeRatio: root.sizeRatio
        autoHide: root.autoHide
        forceOpen: root.forceOpen
        disableOpen: root.disableOpen
        rightOpen: root.rightOpen
        hovered: root.hovered
        fontSize: root.fontSize

        onShown: root.shown()
        onHidden: root.hidden()
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
        onRightClicked: root.rightClicked()
        onMiddleClicked: root.middleClicked()
        onWheel: root.wheel
      }
    }

    Component {
      id: horizontalPillComponent
      NPillHorizontal {
        icon: root.icon
        text: root.text
        tooltipText: root.tooltipText
        sizeRatio: root.sizeRatio
        autoHide: root.autoHide
        forceOpen: root.forceOpen
        disableOpen: root.disableOpen
        rightOpen: root.rightOpen
        hovered: root.hovered
        fontSize: root.fontSize

        onShown: root.shown()
        onHidden: root.hidden()
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
        onRightClicked: root.rightClicked()
        onMiddleClicked: root.middleClicked()
        onWheel: root.wheel
      }
    }
  }

  function show() {
    if (pillLoader.item && pillLoader.item.show) {
      pillLoader.item.show()
    }
  }

  function hide() {
    if (pillLoader.item && pillLoader.item.hide) {
      pillLoader.item.hide()
    }
  }

  function showDelayed() {
    if (pillLoader.item && pillLoader.item.showDelayed) {
      pillLoader.item.showDelayed()
    }
  }
}
