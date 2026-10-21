import QtQuick
import qs.Commons
import qs.Widgets

// The shell slider with the chooser's explicit keyboard-focus presentation.
NSlider {
  id: root
  activeFocusOnTab: true
  cutoutColor: AtmoColor.mSurfaceVariant
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: Style.iRadiusS
    border.color: AtmoColor.mPrimary
    border.width: root.activeFocus ? Style.borderM : 0
  }
}
