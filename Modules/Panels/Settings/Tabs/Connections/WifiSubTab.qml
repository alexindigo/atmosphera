import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Bluetooth

import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: wifiprefs
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight

  // Combined visibility check: tab must be visible AND the window must be visible
  readonly property bool effectivelyVisible: wifiprefs.visible && Window.window && Window.window.visible

  ColumnLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.marginL

    // Airplane Mode Toggle
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: masterControlColAirplane.implicitHeight

      ColumnLayout {
        id: masterControlColAirplane
        anchors.fill: parent
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NIcon {
            icon: Settings.data.network.airplaneModeEnabled ? "plane" : "plane-off"
            pointSize: Style.fontSizeXXL
            color: Settings.data.network.airplaneModeEnabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          NLabel {
            label: I18n.tr("toast.airplane-mode.title")
          }

          Item {
            Layout.fillWidth: true
          }

          NToggle {
            checked: Settings.data.network.airplaneModeEnabled
            onToggled: checked => NetworkService.setAirplaneMode(checked)
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }

    // Wi-Fi Master Control
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: masterControlCol.implicitHeight

      ColumnLayout {
        id: masterControlCol
        anchors.fill: parent
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NIcon {
            icon: Settings.data.network.wifiEnabled ? "wifi" : "wifi-off"
            pointSize: Style.fontSizeXXL
            color: Settings.data.network.wifiEnabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          NLabel {
            label: I18n.tr("common.wifi")
          }

          Item {
            Layout.fillWidth: true
          }

          NToggle {
            checked: Settings.data.network.wifiEnabled
            onToggled: checked => NetworkService.setWifiEnabled(checked)
            Layout.alignment: Qt.AlignVCenter
            enabled: ProgramCheckerService.nmcliAvailable && !Settings.data.network.airplaneModeEnabled && NetworkService.wifiAvailable
          }
        }
      }
    }
  }
}
