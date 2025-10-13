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

  panelKeyboardFocus: true
  preferredWidth: Math.round(460 * Style.uiScaleRatio)
  preferredHeight: {
    let height = profileHeight + weatherHeight + mediaSysMonHeight + utilsHeight
    let count = 4
    if (Settings.data.controlCenter.audioControlsEnabled) {
      count++
      height += audioHeight
    }
    return height + (count + 1) * Style.marginL
  }

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
  readonly property int utilsHeight: Math.round(52 * Style.uiScaleRatio)

  panelContent: Item {
    id: content

    // Layout content
    ColumnLayout {
      id: layout
      x: Style.marginL
      y: Style.marginL
      width: parent.width - (Style.marginL * 2)
      spacing: Style.marginL

      // Profile
      ProfileCard {
        Layout.fillWidth: true
        Layout.preferredHeight: profileHeight
      }

      // Utils
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: utilsHeight
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

      // Audio controls
      AudioCard {
        visible: Settings.data.controlCenter.audioControlsEnabled
        Layout.fillWidth: true
        Layout.preferredHeight: audioHeight
      }

      // Weather
      WeatherCard {
        Layout.fillWidth: true
        Layout.preferredHeight: weatherHeight
      }

      // Media + SysMon
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
    }
  }
}
