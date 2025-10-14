import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Cards

RowLayout {
  Layout.fillWidth: true
  spacing: Style.marginL

  NBox {
    Layout.fillWidth: true
    Layout.preferredHeight: root.shortcutsHeight

    RowLayout {
      id: leftContent
      anchors.fill: parent
      spacing: Style.marginS

      Item {
        Layout.fillWidth: true
      }

      Repeater {
        model: Settings.data.controlCenter.shortcuts.left
        delegate: ControlCenterWidgetLoader {
          Layout.fillWidth: false
          widgetId: (modelData.id !== undefined ? modelData.id : "")
          widgetProps: {
            "screen": root.modelData || null,
            "widgetId": modelData.id,
            "section": "quickSettings",
            "sectionWidgetIndex": index,
            "sectionWidgetsCount": Settings.data.controlCenter.shortcuts.left.length
          }
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }

  NBox {
    Layout.fillWidth: true
    Layout.preferredHeight: root.shortcutsHeight

    RowLayout {
      id: rightContent
      anchors.fill: parent
      spacing: Style.marginS

      Item {
        Layout.fillWidth: true
      }

      Repeater {
        model: Settings.data.controlCenter.shortcuts.right
        delegate: ControlCenterWidgetLoader {
          Layout.fillWidth: false
          widgetId: (modelData.id !== undefined ? modelData.id : "")
          widgetProps: {
            "screen": root.modelData || null,
            "widgetId": modelData.id,
            "section": "quickSettings",
            "sectionWidgetIndex": index,
            "sectionWidgetsCount": Settings.data.controlCenter.shortcuts.right.length
          }
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }
}
