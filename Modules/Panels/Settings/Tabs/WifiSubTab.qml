import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("actions.enable-wifi")
    description: I18n.tr("panels.network.wifi-description")
    checked: ProgramCheckerService.nmcliAvailable && Settings.data.network.wifiEnabled
    onToggled: checked => NetworkService.setWifiEnabled(checked)
    enabled: ProgramCheckerService.nmcliAvailable
  }
}
