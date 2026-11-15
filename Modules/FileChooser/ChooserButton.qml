import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// The existing NButton, with keyboard and focus presentation for this window.
NButton {
  id: root
  NInputGuard {
    target: root
  }
  property bool primary: false
  readonly property bool iconOnly: text === ""
  // An icon-only action has one square slot, centred by NButton's content row.
  Layout.preferredWidth: text === "" ? implicitHeight : -1
  width: text === "" ? implicitHeight : implicitWidth
  activeFocusOnTab: true
  backgroundColor: primary ? AtmoColor.mPrimary : "transparent"
  textColor: primary ? AtmoColor.mOnPrimary : AtmoColor.mOnSurface
  fontWeight: Style.fontWeightMedium
  Accessible.role: Accessible.Button
  Accessible.name: text || String(tooltipText || "")
  Accessible.onPressAction: clicked()
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()
  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.borderS
    color: "transparent"
    radius: root.buttonRadius
    border.width: root.activeFocus ? Style.borderM : 0
    border.color: root.primary ? AtmoColor.mOnPrimary : AtmoColor.mPrimary
  }
}
