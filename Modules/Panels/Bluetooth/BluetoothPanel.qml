import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings // For SettingsPanel

import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"

    property real contentPreferredHeight: Math.min(root.preferredHeight, mainColumn.implicitHeight + Style.marginL * 2)

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerRow.implicitHeight + Style.marginXL

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
            pointSize: Style.fontSizeXXL
            color: BluetoothService.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          NText {
            text: I18n.tr("common.bluetooth")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NToggle {
            id: bluetoothSwitch
            checked: BluetoothService.enabled
            onToggled: checked => BluetoothService.setBluetoothEnabled(checked)
            baseSize: Style.baseWidgetSize * 0.65
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      NScrollView {
        id: bluetoothScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        reserveScrollbarSpace: false
        gradientColor: Color.mSurface

        ColumnLayout {
          id: devicesList
          width: bluetoothScrollView.availableWidth
          spacing: Style.marginM

          // Adapter not available of disabled
          NBox {
            id: disabledBox
            visible: !(BluetoothService.adapter && BluetoothService.adapter.enabled)
            Layout.fillWidth: true
            Layout.preferredHeight: disabledColumn.implicitHeight + Style.marginXL

            // Center the content within this rectangle
            ColumnLayout {
              id: disabledColumn
              anchors.fill: parent
              anchors.margins: Style.marginM
              spacing: Style.marginL

              Item {
                Layout.fillHeight: true
              }

              NIcon {
                icon: "bluetooth-off"
                pointSize: 48
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: I18n.tr("bluetooth.panel.disabled")
                pointSize: Style.fontSizeL
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: I18n.tr("bluetooth.panel.enable-message")
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
              }

              Item {
                Layout.fillHeight: true
              }
            }
          }

          // Empty state when no paired devices
          NBox {
            id: emptyBox
            visible: {
              if (!(BluetoothService.adapter && BluetoothService.adapter.enabled && BluetoothService.adapter.devices))
                return false;

              // Check for connected or paired/trusted devices
              var knownCount = BluetoothService.adapter.devices.values.filter(dev => {
                                                                                return dev && !dev.blocked && (dev.connected || dev.paired || dev.trusted);
                                                                              }).length;
              return (knownCount === 0);
            }
            Layout.fillWidth: true
            Layout.preferredHeight: emptyColumn.implicitHeight + Style.marginXL

            ColumnLayout {
              id: emptyColumn
              anchors.fill: parent
              anchors.margins: Style.marginM
              spacing: Style.marginL

              Item {
                Layout.fillHeight: true
              }

              NIcon {
                icon: "bluetooth"
                pointSize: 48
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: I18n.tr("bluetooth.panel.no-devices")
                pointSize: Style.fontSizeL
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NButton {
                text: I18n.tr("common.settings")
                icon: "settings"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                  SettingsPanel.openToTab(SettingsPanel.Tab.Bluetooth);
                  root.close();
                }
              }

              Item {
                Layout.fillHeight: true
              }
            }
          }

          // Connected devices
          BluetoothDevicesList {
            label: I18n.tr("bluetooth.panel.connected-devices")
            headerMode: "layout"
            property var items: {
              if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
                return [];
              var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && dev.connected);
              filtered = BluetoothService.dedupeDevices(filtered);
              return BluetoothService.sortDevices(filtered);
            }
            model: items
            visible: items.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
            Layout.fillWidth: true
          }

          // Paired devices
          BluetoothDevicesList {
            label: I18n.tr("bluetooth.panel.paired-devices")
            headerMode: "layout"
            property var items: {
              if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
                return [];
              var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.connected && (dev.paired || dev.trusted));
              filtered = BluetoothService.dedupeDevices(filtered);
              return BluetoothService.sortDevices(filtered);
            }
            model: items
            visible: items.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
            Layout.fillWidth: true
          }
        }
      }
    }

    // PIN Authentication Overlay
    Rectangle {
      id: pinOverlay
      anchors.fill: parent
      color: Color.mSurface
      visible: BluetoothService.pinRequired

      // Trap all input
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => mouse.accepted = true
        onWheel: wheel => wheel.accepted = true
      }

      ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.85
        spacing: Style.marginL

        NIcon {
          icon: "lock"
          pointSize: 48
          color: Color.mPrimary
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("common.authentication-required")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          horizontalAlignment: Text.AlignHCenter
        }

        NText {
          text: I18n.tr("bluetooth.panel.pin-instructions")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          Layout.fillWidth: true
        }

        NTextInput {
          id: pinInput
          Layout.fillWidth: true
          placeholderText: "123456"
          inputIconName: "key"
          // Clear text when overlay appears
          onVisibleChanged: {
            if (visible) {
              text = "";
              inputItem.forceActiveFocus();
            }
          }
          // Submit on Enter
          inputItem.onAccepted: {
            if (text.length > 0) {
              BluetoothService.submitPin(text);
              text = "";
            }
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginM

          NButton {
            text: I18n.tr("common.cancel")
            icon: "x"
            onClicked: BluetoothService.cancelPairing()
          }

          NButton {
            text: I18n.tr("common.confirm")
            icon: "check"
            backgroundColor: Color.mPrimary
            textColor: Color.mOnPrimary
            enabled: pinInput.text.length > 0
            onClicked: {
              BluetoothService.submitPin(pinInput.text);
              pinInput.text = "";
            }
          }
        }
      }
    }
  }
}
