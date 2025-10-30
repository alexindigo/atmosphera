import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Settings
// import qs.Modules.Bar.Extras

Rectangle {
  id: root

  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property bool showCaps: (widgetSettings.showCapsLock !== undefined) ? widgetSettings.showCapsLock : widgetMetadata.showCapsLock
  readonly property bool showNum: (widgetSettings.showNumLock !== undefined) ? widgetSettings.showNumLock : widgetMetadata.showNumLock
  readonly property bool showScroll: (widgetSettings.showScrollLock !== undefined) ? widgetSettings.showScrollLock : widgetMetadata.showScrollLock

  property bool capsLockOn: LockKeysService.capsLockOn
  property bool numLockOn: LockKeysService.numLockOn
  property bool scrollLockOn: LockKeysService.scrollLockOn

  Connections {
    target: LockKeysService
    function onCapsLockChanged(active) { root.capsLockOn = active }
    function onNumLockChanged(active) { root.numLockOn = active }
    function onScrollLockChanged(active) { root.scrollLockOn = active }
  }

  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(layout.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginM * 2) : Style.capsuleHeight

  Layout.alignment: Qt.AlignVCenter

  radius: Style.radiusM
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  Item {
    id: layout
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter

    implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth
    implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight

    RowLayout {
      id: rowLayout
      visible: !root.isVertical
      spacing: 0

      NIcon {
        visible: showCaps
        icon: "letter-c"
        color: root.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: showNum
        icon: "letter-n"
        color: root.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: showScroll
        icon: "letter-s"
        color: root.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
    }

    ColumnLayout {
      id: colLayout
      visible: root.isVertical
      spacing: 0

      NIcon {
        visible: showCaps
        icon: "letter-c"
        color: root.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: showNum
        icon: "letter-n"
        color: root.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: showScroll
        icon: "letter-s"
        color: root.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
    }
  }
}
