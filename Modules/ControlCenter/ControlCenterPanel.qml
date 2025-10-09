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

  preferredWidth: 440
  preferredHeight: topHeight + bottomHeight +  Math.round(Style.marginL * scaling  * 3)
  panelKeyboardFocus: true

  readonly property int bottomHeight: Math.round(Math.max(196 * scaling))
  readonly property int topHeight: {
    const rowsCount = Math.ceil(Settings.data.controlCenter.widgets.quickSettings.length / 3)

    var buttonHeight;
    if (Settings.data.controlCenter.quickSettingsStyle === "classic") {
      buttonHeight = Style.baseWidgetSize
    }
    else {
      buttonHeight = 56
    }

    return (rowsCount * buttonHeight) + (120 * scaling)
  }

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

    property real cardSpacing: Style.marginL * scaling

    // Layout content
    ColumnLayout {
      id: layout
      anchors.fill: parent
      anchors.margins: content.cardSpacing
      spacing: content.cardSpacing

      // Top Card: profile + utilities
      TopCard {
        id: topCard
        Layout.fillWidth: true
        Layout.preferredHeight: topHeight
      }

      // Media + stats column
      RowLayout {
        id: bottomCard
        Layout.fillWidth: true
        Layout.preferredHeight: bottomHeight
        spacing: content.cardSpacing

        // Media card
        MediaCard {
          Layout.preferredWidth: Math.max(250 * scaling)
          Layout.preferredHeight: bottomHeight
        }

        // System monitors combined in one card
        SystemMonitorCard {
          Layout.preferredWidth: Math.max(140 * scaling)
          Layout.preferredHeight: bottomHeight
        }
      }
    }
  }
}
