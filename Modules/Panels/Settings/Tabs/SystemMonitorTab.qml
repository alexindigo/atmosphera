import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  Component.onCompleted: {

  }

  NHeader {
    label: I18n.tr("settings.system-monitor.general.section.label")
    description: I18n.tr("settings.system-monitor.general.section.description")
  }
}
