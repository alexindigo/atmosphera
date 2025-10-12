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

  preferredWidth: Math.round(460 * Style.uiScaleRatio)
  preferredHeight: (profileHeight + weatherHeight + mediaSysMonHeight + audioHeight + bottomHeight) + 6 * Style.marginL
  panelKeyboardFocus: true

  // Positioning
  readonly property string controlCenterPosition: Settings.data.controlCenter.position
  panelAnchorHorizontalCenter: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_center")
  panelAnchorVerticalCenter: false
  panelAnchorLeft: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_left")
  panelAnchorRight: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_right")
  panelAnchorBottom: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("bottom_")
  panelAnchorTop: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("top_")

  readonly property int profileHeight: Math.round(64 * Style.uiScaleRatio)
  readonly property int weatherHeight: Math.round(190 * Style.uiScaleRatio)
  readonly property int mediaSysMonHeight: Math.round(260 * Style.uiScaleRatio)
  readonly property int audioHeight: Math.round(120 * Style.uiScaleRatio)
  readonly property int bottomHeight: Math.round(60 * Style.uiScaleRatio)

  panelContent: Item {
    id: content

    // Layout content
    ColumnLayout {
      id: layout
      x: Style.marginL
      y: Style.marginL
      width: parent.width - (Style.marginL * 2)
      spacing: Style.marginL

      // Cards (consistent inter-card spacing via ColumnLayout spacing)
      ProfileCard {
        Layout.fillWidth: true
        Layout.preferredHeight: profileHeight
      }

      WeatherCard {
        Layout.fillWidth: true
        Layout.preferredHeight: weatherHeight
      }

      // Middle section: media + stats column
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: mediaSysMonHeight
        spacing: Style.marginL

        // Media card
        MediaCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        // System monitors combined in one card
        SystemMonitorCard {
          Layout.preferredWidth: Math.round(Style.baseWidgetSize * 2.625)
          Layout.fillHeight: true
        }
      }

      // Audio card below media and system monitor
      AudioCard {
        Layout.fillWidth: true
        Layout.preferredHeight: audioHeight
      }

      // Bottom actions (two grouped rows of round buttons)
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: bottomHeight
        spacing: Style.marginL

        // Power Profiles switcher
        PowerProfilesCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.marginL
        }

        // Utilities buttons
        UtilitiesCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.marginL
        }
      }
    }
  }
}
