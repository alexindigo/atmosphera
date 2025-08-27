import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root
  panelWidth: 380 * scaling
  panelHeight: 500 * scaling
  panelAnchorRight: true

  // When the panel opens
  onOpened: {
    ArchUpdaterService.doPoll()
    ArchUpdaterService.doAurPoll()
  }

  panelContent: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL * scaling

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          text: "system_update"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        Text {
          text: "System Updates"
          font.pointSize: Style.fontSizeL * scaling
          font.family: Settings.data.ui.fontDefault
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close"
          sizeRatio: 0.8
          onClicked: root.close()
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Update summary
      Text {
        text: ArchUpdaterService.totalUpdates + " package" + (ArchUpdaterService.totalUpdates !== 1 ? "s" : "") + " can be updated"
        font.pointSize: Style.fontSizeL * scaling
        font.family: Settings.data.ui.fontDefault
        font.weight: Style.fontWeightMedium
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      // Package selection info
      Text {
        text: ArchUpdaterService.selectedPackagesCount + " of " + ArchUpdaterService.totalUpdates + " packages selected"
        font.pointSize: Style.fontSizeS * scaling
        font.family: Settings.data.ui.fontDefault
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
      }

      // Unified list
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusM * scaling

        // Combine repo and AUR lists in order: repos first, then AUR
        property var items: (ArchUpdaterService.repoPackages || []).concat(ArchUpdaterService.aurPackages || [])

        ListView {
          id: unifiedList
          anchors.fill: parent
          anchors.margins: Style.marginS * scaling
          clip: true
          model: parent.items
          spacing: Style.marginXS * scaling
          cacheBuffer: 300 * scaling

          delegate: Rectangle {
            width: unifiedList.width
            height: 56 * scaling
            color: Color.transparent
            radius: Style.radiusS * scaling

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.marginS * scaling
              spacing: Style.marginS * scaling

              // Checkbox for selection (pure bindings; no imperative state)
              NIconButton {
                id: checkbox
                icon: ArchUpdaterService.isPackageSelected(modelData.name) ? "check_box" : "check_box_outline_blank"
                onClicked: ArchUpdaterService.togglePackageSelection(modelData.name)
                colorBg: Color.transparent
                colorFg: ArchUpdaterService.isPackageSelected(
                           modelData.name) ? ((modelData.source === "aur") ? Color.mSecondary : Color.mPrimary) : Color.mOnSurfaceVariant
                Layout.preferredWidth: 30 * scaling
                Layout.preferredHeight: 30 * scaling
              }

              // Package info
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS * scaling

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS * scaling

                  Text {
                    text: modelData.name
                    font.pointSize: Style.fontSizeM * scaling
                    font.family: Settings.data.ui.fontDefault
                    font.weight: Style.fontWeightMedium
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                  }

                  // Source badge (custom rectangle)
                  Rectangle {
                    visible: !!modelData.source
                    radius: 9999
                    color: modelData.source === "aur" ? Color.mSecondary : Color.mPrimary
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: Math.max(Style.fontSizeXS * 1.7 * scaling, 16 * scaling)
                    // Width based on label content + horizontal padding
                    implicitWidth: badgeText.implicitWidth + Math.max(12 * scaling, Style.marginS * scaling)

                    NText {
                      id: badgeText
                      anchors.centerIn: parent
                      text: modelData.source === "aur" ? "AUR" : "Repo"
                      font.pointSize: Style.fontSizeXS * scaling
                      font.weight: Style.fontWeightBold
                      color: modelData.source === "aur" ? Color.mOnSecondary : Color.mOnPrimary
                    }
                  }
                }

                Text {
                  text: modelData.oldVersion + " → " + modelData.newVersion
                  font.pointSize: Style.fontSizeS * scaling
                  font.family: Settings.data.ui.fontDefault
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                }
              }
            }
          }

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }
        }
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS * scaling

        NIconButton {
          icon: "refresh"
          tooltipText: "Check for updates"
          onClicked: {
            ArchUpdaterService.doPoll()
            ArchUpdaterService.doAurPoll()
          }
          colorBg: Color.mSurfaceVariant
          colorFg: Color.mOnSurface
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "system_update"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update all packages"
          enabled: !ArchUpdaterService.updateInProgress
          onClicked: {
            ArchUpdaterService.runUpdate()
            root.close()
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : Color.mPrimary
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : Color.mOnPrimary
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "settings"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update selected packages"
          enabled: !ArchUpdaterService.updateInProgress && ArchUpdaterService.selectedPackagesCount > 0
          onClicked: {
            if (ArchUpdaterService.selectedPackagesCount > 0) {
              ArchUpdaterService.runSelectiveUpdate()
              root.close()
            }
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                  > 0 ? Color.mSecondary : Color.mSurfaceVariant)
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                    > 0 ? Color.mOnSecondary : Color.mOnSurfaceVariant)
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }
      }
    }
  }
}
