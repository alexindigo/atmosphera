import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
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
      text: I18n.tr("common.general")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("panels.hooks.handlers-title")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("panels.hooks.listeners-title")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginS
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    GeneralSubTab {}
    HandlersSubTab {}
    ListenersSubTab {}
  }
}
