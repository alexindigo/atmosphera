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
          text: "system_update_alt"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        NText {
          text: "System Updates"
          font.pointSize: Style.fontSizeL * scaling
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
      NText {
        text: ArchUpdaterService.totalUpdates + " package" + (ArchUpdaterService.totalUpdates !== 1 ? "s" : "") + " can be updated"
        font.pointSize: Style.fontSizeL * scaling
        font.weight: Style.fontWeightMedium
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      // Package selection info
      NText {
        text: ArchUpdaterService.selectedPackagesCount + " of " + ArchUpdaterService.totalUpdates + " packages selected"
        font.pointSize: Style.fontSizeS * scaling
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
      }

      // Unified list
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Combine repo and AUR lists in order: repos first, then AUR
        property var items: (ArchUpdaterService.repoPackages || []).concat(ArchUpdaterService.aurPackages || [])

        ListView {
          id: unifiedList
          anchors.fill: parent
          anchors.margins: Style.marginM * scaling
          cacheBuffer: Math.round(300 * scaling)
          clip: true
          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }
          model: parent.items
          delegate: Rectangle {
            width: unifiedList.width
            height: 44 * scaling
            color: Color.transparent
            radius: Style.radiusS * scaling

            RowLayout {
              anchors.fill: parent
              spacing: Style.marginS * scaling

              // Checkbox for selection
              NCheckbox {
                id: checkbox
                label: ""
                description: ""
                checked: ArchUpdaterService.isPackageSelected(modelData.name)
                baseSize: Math.max(Style.baseWidgetSize * 0.7, 14)
                onToggled: function (checked) {
                  ArchUpdaterService.togglePackageSelection(modelData.name)
                  // Force refresh of the checked property
                  checkbox.checked = ArchUpdaterService.isPackageSelected(modelData.name)
                }
              }

              // Package info
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS * scaling

                NText {
                  text: modelData.name
                  font.pointSize: Style.fontSizeS * scaling
                  font.weight: Style.fontWeightBold
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                }

                NText {
                  text: modelData.oldVersion + " → " + modelData.newVersion
                  font.pointSize: Style.fontSizeXXS * scaling
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                }
              }

              // Source tag (AUR vs PAC)
              Rectangle {
                visible: !!modelData.source
                radius: width * 0.5
                color: modelData.source === "aur" ? Color.mTertiary : Color.mSecondary
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Style.fontSizeS * 1.8 * scaling
                // Width based on label content + horizontal padding
                implicitWidth: badgeText.implicitWidth + Math.max(12 * scaling, Style.marginS * scaling)

                NText {
                  id: badgeText
                  anchors.centerIn: parent
                  text: modelData.source === "aur" ? "AUR" : "PAC"
                  font.pointSize: Style.fontSizeXXS * scaling
                  font.weight: Style.fontWeightBold
                  color: modelData.source === "aur" ? Color.mOnTertiary : Color.mOnSecondary
                }
              }
            }
          }
        }
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginL * scaling

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
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "system_update_alt"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update all packages"
          enabled: !ArchUpdaterService.updateInProgress
          onClicked: {
            ArchUpdaterService.runUpdate()
            root.close()
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : Color.mPrimary
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : Color.mOnPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "check_box"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update selected packages"
          enabled: !ArchUpdaterService.updateInProgress && ArchUpdaterService.selectedPackagesCount > 0
          onClicked: {
            if (ArchUpdaterService.selectedPackagesCount > 0) {
              ArchUpdaterService.runSelectiveUpdate()
              root.close()
            }
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                  > 0 ? Color.mPrimary : Color.mSurfaceVariant)
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                    > 0 ? Color.mOnPrimary : Color.mOnSurfaceVariant)
          Layout.fillWidth: true
        }
      }
    }
  }
}
