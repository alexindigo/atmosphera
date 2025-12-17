import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import qs.Commons
import qs.Services.Networking
import qs.Widgets

NBox {
  id: root

  property string label: ""
  property string tooltipText: ""
  property var model: {}
  // Per-list expanded details (by device key)
  property string expandedDeviceKey: ""

  Layout.fillWidth: true
  Layout.preferredHeight: column.implicitHeight + Style.marginM * 2

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Style.marginM

    spacing: Style.marginM

    NText {
      text: root.label
      pointSize: Style.fontSizeS
      color: Color.mSecondary
      font.weight: Style.fontWeightBold
      visible: root.model.length > 0
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginM
    }

    Repeater {
      id: deviceList
      Layout.fillWidth: true
      model: root.model
      visible: BluetoothService.adapter && BluetoothService.adapter.enabled

      Rectangle {
        id: device

        readonly property bool canConnect: BluetoothService.canConnect(modelData)
        readonly property bool canDisconnect: BluetoothService.canDisconnect(modelData)
        readonly property bool canPair: BluetoothService.canPair(modelData)
        readonly property bool isBusy: BluetoothService.isDeviceBusy(modelData)
        readonly property bool isExpanded: root.expandedDeviceKey === BluetoothService.deviceKey(modelData)

        function getContentColor(defaultColor) {
          if (defaultColor === undefined) defaultColor = Color.mOnSurface;
          if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
            return Color.mPrimary;
          if (modelData.blocked)
            return Color.mError;
          return defaultColor;
        }

        Layout.fillWidth: true
        Layout.preferredHeight: deviceColumn.implicitHeight + (Style.marginM * 2)
        radius: Style.radiusM
        color: Color.mSurface
        border.width: Style.borderS
        border.color: getContentColor(Color.mOutline)
        clip: true

        // Content column so expanded details are laid out inside the card
        ColumnLayout {
          id: deviceColumn
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          RowLayout {
            id: deviceLayout
            Layout.fillWidth: true
            spacing: Style.marginM
            Layout.alignment: Qt.AlignVCenter

            // One device BT icon
            NIcon {
              icon: BluetoothService.getDeviceIcon(modelData)
              pointSize: Style.fontSizeXXL
              color: getContentColor(Color.mOnSurface)
              Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginXXS

              // Device name
              NText {
                text: modelData.name || modelData.deviceName
                pointSize: Style.fontSizeM
                font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                elide: Text.ElideRight
                color: getContentColor(Color.mOnSurface)
                Layout.fillWidth: true
              }

              // Status
              NText {
                text: BluetoothService.getStatusString(modelData)
                visible: text !== ""
                pointSize: Style.fontSizeXS
                color: getContentColor(Color.mOnSurfaceVariant)
              }

              // Signal Strength
              RowLayout {
                visible: modelData.signalStrength !== undefined
                Layout.fillWidth: true
                spacing: Style.marginXS

                // Device signal strength - "Unknown" when not connected
                NText {
                  text: BluetoothService.getSignalStrength(modelData)
                  pointSize: Style.fontSizeXS
                  color: getContentColor(Color.mOnSurfaceVariant)
                }

                NIcon {
                  visible: modelData.signalStrength > 0 && !modelData.pairing && !modelData.blocked
                  icon: BluetoothService.getSignalIcon(modelData)
                  pointSize: Style.fontSizeXS
                  color: getContentColor(Color.mOnSurface)
                }

                NText {
                  visible: modelData.signalStrength > 0 && !modelData.pairing && !modelData.blocked
                  text: (modelData.signalStrength !== undefined && modelData.signalStrength > 0) ? modelData.signalStrength + "%" : ""
                  pointSize: Style.fontSizeXS
                  color: getContentColor(Color.mOnSurface)
                }
              }

              // Battery
              NText {
                visible: modelData.batteryAvailable
                text: BluetoothService.getBattery(modelData)
                pointSize: Style.fontSizeXS
                color: getContentColor(Color.mOnSurfaceVariant)
              }
            }

            // Spacer to push connect button to the right
            Item {
              Layout.fillWidth: true
            }

            // Call to action
            NButton {
              id: button
              visible: (modelData.state !== BluetoothDeviceState.Connecting)
              enabled: (canConnect || canDisconnect || canPair) && !isBusy
              outlined: !button.hovered
              fontSize: Style.fontSizeXS
              fontWeight: Style.fontWeightMedium
              backgroundColor: {
                if (device.canDisconnect && !isBusy) {
                  return Color.mError;
                }
                return Color.mPrimary;
              }
              tooltipText: root.tooltipText
              text: {
                if (modelData.pairing) {
                  return I18n.tr("bluetooth.panel.pairing");
                }
                if (modelData.blocked) {
                  return I18n.tr("bluetooth.panel.blocked");
                }
                if (modelData.connected) {
                  return I18n.tr("bluetooth.panel.disconnect");
                }
                if (device.canPair) {
                  return I18n.tr("bluetooth.panel.pair");
                }
                return I18n.tr("bluetooth.panel.connect");
              }
              icon: (isBusy ? "busy" : null)
              onClicked: {
                if (modelData.connected) {
                  BluetoothService.disconnectDevice(modelData);
                } else {
                  if (device.canPair) {
                    BluetoothService.pairDevice(modelData);
                  } else {
                    BluetoothService.connectDeviceWithTrust(modelData);
                  }
                }
              }
              onRightClicked: {
                BluetoothService.forgetDevice(modelData);
              }
            }

            // Extra actions
            RowLayout {
              spacing: Style.marginXS

              // Unpair for saved devices when not connected
              NIconButton {
                visible: (modelData.paired || modelData.trusted) && !modelData.connected && !isBusy && !modelData.blocked
                icon: "trash"
                tooltipText: I18n.tr("bluetooth.panel.unpair")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: BluetoothService.unpairDevice(modelData)
              }

              // Info for connected device
              NIconButton {
                visible: modelData.connected
                icon: "info-circle"
                tooltipText: I18n.tr("bluetooth.panel.info")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: {
                  const key = BluetoothService.deviceKey(modelData);
                  root.expandedDeviceKey = (root.expandedDeviceKey === key) ? "" : key;
                }
              }
            }
          }

          // Expanded info section
          Rectangle {
            visible: device.isExpanded
            Layout.fillWidth: true
            height: infoColumn.implicitHeight + Style.marginS * 2
            radius: Style.radiusS
            color: Color.mSurfaceVariant
            border.width: Style.borderS
            border.color: Color.mOutline

            ColumnLayout {
              id: infoColumn
              anchors.fill: parent
              anchors.margins: Style.marginS
              spacing: Style.marginXS

              RowLayout {
                spacing: Style.marginS
                NIcon { icon: BluetoothService.getSignalIcon(modelData); pointSize: Style.fontSizeM; color: Color.mOnSurface }
                NText { text: BluetoothService.getSignalStrength(modelData); pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                NText { visible: modelData.signalStrength > 0; text: (modelData.signalStrength || 0) + "%"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              }

              RowLayout {
                spacing: Style.marginS
                NIcon { icon: "hash"; pointSize: Style.fontSizeM; color: Color.mOnSurface }
                NText { text: I18n.tr("bluetooth.panel.device-address") + ": "; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                NText { text: modelData.address || "-"; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
              }

              RowLayout {
                spacing: Style.marginS
                NIcon { icon: "shield-check"; pointSize: Style.fontSizeM; color: Color.mOnSurface }
                NText { text: I18n.tr("bluetooth.panel.paired") + ": " + (modelData.paired ? I18n.tr("common.yes") : I18n.tr("common.no")); pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                NText { text: "•"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                NText { text: I18n.tr("bluetooth.panel.trusted") + ": " + (modelData.trusted ? I18n.tr("common.yes") : I18n.tr("common.no")); pointSize: Style.fontSizeXS; color: Color.mOnSurface }
              }

              RowLayout {
                visible: modelData.batteryAvailable
                spacing: Style.marginS
                NIcon { icon: "battery"; pointSize: Style.fontSizeM; color: Color.mOnSurface }
                NText { text: BluetoothService.getBattery(modelData); pointSize: Style.fontSizeXS; color: Color.mOnSurface }
              }
            }
          }
        }
      }
    }
  }
}
