import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.ControlCenter.Cards
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 460
  preferredHeight: 790
  panelKeyboardFocus: true

  // Positioning
  readonly property string controlCenterPosition: Settings.data.controlCenter.position
  panelAnchorHorizontalCenter: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_center")
  panelAnchorVerticalCenter: false
  panelAnchorLeft: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_left")
  panelAnchorRight: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_right")
  panelAnchorBottom: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("bottom_")
  panelAnchorTop: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("top_")

  panelContent: Item {
    id: content

    property real cardSpacing: Style.marginL

    // Layout content
    ColumnLayout {
      id: layout
      x: content.cardSpacing
      y: content.cardSpacing
      width: parent.width - (2 * content.cardSpacing)
      spacing: content.cardSpacing

      // Cards (consistent inter-card spacing via ColumnLayout spacing)
      ProfileCard {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(64)
      }

      WeatherCard {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(190)
      }

      // Middle section: media + stats column
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(260)
        spacing: content.cardSpacing

        // Media card
        MediaCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        // System monitors combined in one card
        SystemMonitorCard {
          Layout.preferredWidth: Style.baseWidgetSize * 2.625
          Layout.fillHeight: true
        }
      }

      // Audio card below media and system monitor
      AudioCard {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(120)
      }

      // Bottom actions (two grouped rows of round buttons)
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(60)
        spacing: content.cardSpacing

        // Power Profiles switcher
        PowerProfilesCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: content.cardSpacing
        }

        // Utilities buttons
        UtilitiesCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: content.cardSpacing
        }
      }
    }
  }
}
