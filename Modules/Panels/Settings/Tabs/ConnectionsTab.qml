import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Modules.Panels.Settings.Tabs.Connections
import qs.Services.Networking
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("tooltips.manage-wifi")
      // visible: NetworkService.wifiAvailable
      enabled: NetworkService.wifiAvailable // Remove when work finished, only use visibility
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.bluetooth")
      // visible: BluetoothService.bluetoothAvailable
      enabled: BluetoothService.bluetoothAvailable // Remove when work finished, only use visibility
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("panels.connections.ethernet")
      // visible: NetworkService.wifiAvailable
      enabled: NetworkService.wifiAvailable // Remove when work finished, only use visibility
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    Layout.fillHeight: true
    currentIndex: subTabBar.currentIndex
    WifiSubTab {}
    BluetoothSubTab {}
    EthernetSubTab {}
  }
}
