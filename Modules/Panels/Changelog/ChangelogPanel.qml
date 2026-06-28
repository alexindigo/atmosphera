import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(820 * Style.uiScaleRatio)
  preferredHeight: Math.round(620 * Style.uiScaleRatio)
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  panelContent: Rectangle {
    id: panelContent
    color: Color.mSurfaceVariant
    radius: Style.radiusM
    border.color: Color.mOutline
    border.width: Style.borderS

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      ChangelogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        Item {
          Layout.fillWidth: true
        }

        NButton {
          icon: Icon.check
          text: I18n.tr("changelog.panel.buttons-dismiss")
          onClicked: root.close()
        }
      }
    }
  }

  onClosed: {
    if (UpdateService && UpdateService.changelogCurrentVersion) {
      UpdateService.markChangelogSeen(UpdateService.changelogCurrentVersion);
    }
  }
}
