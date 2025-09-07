import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.SidePanel.Cards
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: 460 * scaling
  panelHeight: contentHeight

  // Default height, will be modified via binding when the content is fully loaded
  property real contentHeight: 720 * scaling

  panelContent: Item {
    id: content

    property real cardSpacing: Style.marginL * scaling

    width: root.panelWidth
    implicitHeight: layout.implicitHeight + (2 * cardSpacing)
    height: implicitHeight

    // Update parent's contentHeight whenever our height changes
    onHeightChanged: {
      root.contentHeight = height
    }

    onImplicitHeightChanged: {
      if (implicitHeight > 0) {
        root.contentHeight = implicitHeight
      }
    }

    // Layout content
    ColumnLayout {
      id: layout
      x: content.cardSpacing
      y: content.cardSpacing
      width: parent.width - (2 * content.cardSpacing)
      spacing: content.cardSpacing

      // Cards (consistent inter-card spacing via ColumnLayout spacing)
      ProfileCard {
        id: profileCard
        Layout.fillWidth: true
      }

      WeatherCard {
        id: weatherCard
        Layout.fillWidth: true
      }

      // Middle section: media + stats column
      RowLayout {
        id: middleRow
        Layout.fillWidth: true
        Layout.minimumHeight: 280 * scaling
        Layout.preferredHeight: Math.max(280 * scaling, statsCard.implicitHeight)
        spacing: content.cardSpacing

        // Media card
        MediaCard {
          id: mediaCard
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        // System monitors combined in one card
        SystemMonitorCard {
          id: statsCard
          Layout.alignment: Qt.AlignTop
        }
      }

      // Bottom actions (two grouped rows of round buttons)
      RowLayout {
        id: bottomRow
        Layout.fillWidth: true
        Layout.minimumHeight: 60 * scaling
        Layout.preferredHeight: Math.max(60 * scaling, powerProfilesCard.implicitHeight, utilitiesCard.implicitHeight)
        spacing: content.cardSpacing

        // Power Profiles switcher
        PowerProfilesCard {
          id: powerProfilesCard
          spacing: content.cardSpacing
          Layout.fillWidth: true
        }

        // Utilities buttons
        UtilitiesCard {
          id: utilitiesCard
          spacing: content.cardSpacing
          Layout.fillWidth: true
        }
      }
    }
  }
}
