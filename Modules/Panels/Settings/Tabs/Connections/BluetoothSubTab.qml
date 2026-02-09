import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Bluetooth

import qs.Commons
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: btprefs
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight

  // Configuration for shared use (e.g. by BluetoothPanel)
  property bool showOnlyLists: false

  property bool isScanningActive: BluetoothService.scanningActive
  property bool isDiscoverable: BluetoothService.discoverable

  // Device lists with local filtering logic
  readonly property var connectedDevices: {
    if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
      return [];
    var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && dev.connected);
    filtered = BluetoothService.dedupeDevices(filtered);
    return BluetoothService.sortDevices(filtered);
  }

  readonly property var pairedDevices: {
    if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
      return [];
    var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.connected && (dev.paired || dev.trusted));
    filtered = BluetoothService.dedupeDevices(filtered);
    return BluetoothService.sortDevices(filtered);
  }

  readonly property var unnamedAvailableDevices: {
    if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
      return [];
    return BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.paired && !dev.trusted);
  }

  readonly property var availableDevices: {
    var list = btprefs.unnamedAvailableDevices;

    if (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) {
      list = list.filter(function (dev) {
        var dn = dev.name || dev.deviceName || "";
        var s = String(dn).trim();
        if (s.length === 0)
          return false;
        var lower = s.toLowerCase();
        if (lower === "unknown" || lower === "unnamed" || lower === "n/a" || lower === "na")
          return false;
        var addr = dev.address || dev.bdaddr || dev.mac || "";
        if (addr.length > 0) {
          var normName = s.toLowerCase().replace(/[^0-9a-z]/g, "");
          var normAddr = String(addr).toLowerCase().replace(/[^0-9a-z]/g, "");
          if (normName.length > 0 && normName === normAddr)
            return false;
        }
        var macColonHex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;
        var macHyphenHex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        var macHyphenAny = /^([0-9A-Za-z]{2}-){5}[0-9A-Za-z]{2}$/;
        var macDotted = /^[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}$/;
        var macBare = /^[0-9A-Fa-f]{12}$/;
        if (macColonHex.test(s) || macHyphenHex.test(s) || macHyphenAny.test(s) || macDotted.test(s) || macBare.test(s))
          return false;
        return true;
      });
    }
    list = BluetoothService.dedupeDevices(list);
    return BluetoothService.sortDevices(list);
  }

  // For managing expanded device details
  property string expandedDeviceKey: ""
  property bool detailsGrid: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothDetailsViewMode !== undefined) ? (Settings.data.network.bluetoothDetailsViewMode === "grid") : true

  // Combined visibility check: tab must be visible AND the window must be visible
  readonly property bool effectivelyVisible: btprefs.visible && Window.window && Window.window.visible

  Connections {
    target: BluetoothService
    function onEnabledChanged() {
      stateChangeDebouncer.restart();
    }
  }

  onEffectivelyVisibleChanged: stateChangeDebouncer.restart()

  Timer {
    id: stateChangeDebouncer
    interval: 100 // 100ms debounce
    repeat: false
    onTriggered: btprefs._updateScanningState()
  }

  function _updateScanningState() {
    if (effectivelyVisible && BluetoothService.enabled && !showOnlyLists) {
      Logger.d("Bluetooth Prefs", "Panel/Tab Active");
      if (!isScanningActive) {
        BluetoothService.setScanActive(true);
      }
      if (!isDiscoverable) {
        BluetoothService.setDiscoverable(true);
      }
    } else {
      Logger.d("Bluetooth Prefs", "Panel/Tab Inactive");
      if (isScanningActive) {
        BluetoothService.setScanActive(false);
      }
      if (isDiscoverable) {
        BluetoothService.setDiscoverable(false);
      }
    }
  }

  Component.onDestruction: {
    // Ensure scanning is stopped when component is closed
    if (isScanningActive) {
      BluetoothService.setScanActive(false);
    }
    // Ensure discoverable is disabled when component is closed
    if (isDiscoverable) {
      BluetoothService.setDiscoverable(false);
    }
    Logger.d("Bluetooth Prefs", "Panel Closed");
  }

  ColumnLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.marginL

    // Master Control Section
    NBox {
      visible: !btprefs.showOnlyLists
      Layout.fillWidth: true
      Layout.preferredHeight: masterControlCol.implicitHeight + Style.marginL * 2
      implicitHeight: Layout.preferredHeight

      ColumnLayout {
        id: masterControlCol
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NIcon {
            icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
            pointSize: Style.fontSizeXXL
            color: BluetoothService.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          ColumnLayout {
            Layout.fillWidth: false
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            NText {
              text: I18n.tr("common.bluetooth")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }
          }

          Item {
            Layout.fillWidth: true
          }

          NToggle {
            checked: BluetoothService.enabled
            onToggled: checked => BluetoothService.setBluetoothEnabled(checked)
            Layout.alignment: Qt.AlignVCenter
          }
        }
        NDivider {
          Layout.fillWidth: true
          visible: BluetoothService.enabled
        }
        NText {
          text: "This device is " + (isDiscoverable ? "discoverable" : "not discoverable") + " as " + HostService.hostName + " while Bluetooth Settings is open."
          // TODO: missing: i18n
          visible: BluetoothService.enabled
        }
      }
    }

    // Device List [1] (Connected)
    NBox {
      id: connectedDevicesBox
      visible: btprefs.connectedDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
      Layout.preferredHeight: connectedDevicesCol.implicitHeight + Style.marginXL

      ColumnLayout {
        id: connectedDevicesCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NText {
          text: I18n.tr("bluetooth.panel.connected-devices")
          pointSize: Style.fontSizeS
          color: Color.mSecondary
          font.weight: Style.fontWeightBold
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: btprefs.connectedDevices
          delegate: nbox_delegate
        }
      }
    }

    NDivider {
      Layout.fillWidth: true
      visible: connectedDevicesBox.visible && !btprefs.showOnlyLists
    }

    // Devices List [2] (Paired)
    NBox {
      id: pairedDevicesBox
      visible: btprefs.pairedDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
      Layout.preferredHeight: pairedDevicesCol.implicitHeight + Style.marginXL

      ColumnLayout {
        id: pairedDevicesCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NText {
          text: I18n.tr("bluetooth.panel.paired-devices")
          pointSize: Style.fontSizeS
          color: Color.mSecondary
          font.weight: Style.fontWeightBold
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: btprefs.pairedDevices
          delegate: nbox_delegate
        }
      }
    }

    NDivider {
      Layout.fillWidth: true
      visible: pairedDevicesBox.visible && !btprefs.showOnlyLists
    }

    // Device List [3] (Available)
    NBox {
      id: availableDevicesBox
      visible: !btprefs.showOnlyLists && btprefs.unnamedAvailableDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
      Layout.preferredHeight: availableDevicesCol.implicitHeight + Style.marginXL

      ColumnLayout {
        id: availableDevicesCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
          spacing: Style.marginS

          NText {
            text: I18n.tr("bluetooth.panel.available-devices") + (BluetoothService.scanningActive ? " (" + I18n.tr("bluetooth.panel.scanning") + ")" : "")
            pointSize: Style.fontSizeS
            color: Color.mSecondary
            font.weight: Style.fontWeightBold
            Layout.fillWidth: true
          }

          NIconButton {
            icon: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) ? "filter-off" : "filter"
            tooltipText: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) ? I18n.tr("tooltips.hide-unnamed-devices") : I18n.tr("tooltips.show-all-devices")
            onClicked: {
              if (Settings.data && Settings.data.ui) {
                Settings.data.network.bluetoothHideUnnamedDevices = !(Settings.data.network.bluetoothHideUnnamedDevices);
              }
            }
          }
        }

        Repeater {
          model: btprefs.availableDevices
          delegate: nbox_delegate
        }

        NText {
          visible: btprefs.availableDevices.length === 0 && btprefs.unnamedAvailableDevices.length > 0
          text: I18n.tr("bluetooth.panel.no-named-devices")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignHCenter
          Layout.fillWidth: true
          Layout.margins: Style.marginL
        }
      }
    }

    NDivider {
      Layout.fillWidth: true
      visible: availableDevicesBox.visible && !btprefs.showOnlyLists
    }

    // RSSI Polling
    NBox {
      visible: !btprefs.showOnlyLists && BluetoothService.enabled
      Layout.fillWidth: true
      Layout.preferredHeight: rssiPollingColumn.implicitHeight + Style.marginL * 2
      implicitHeight: Layout.preferredHeight

      ColumnLayout {
        id: rssiPollingColumn
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            NText {
              text: I18n.tr("panels.network.bluetooth-rssi-polling-label")
              color: Color.mOnSurface
            }
            NText {
              text: I18n.tr("panels.network.bluetooth-rssi-polling-description")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.WordWrap
              visible: true
              Layout.fillWidth: true
            }
          }

          NToggle {
            checked: Settings.data && Settings.data.network && Settings.data.network.bluetoothRssiPollingEnabled
            onToggled: checked => Settings.data.network.bluetoothRssiPollingEnabled = checked
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }

  // Shared Delegate
  Component {
    id: nbox_delegate
    NBox {
      id: device

      readonly property bool canConnect: BluetoothService.canConnect(modelData)
      readonly property bool canDisconnect: BluetoothService.canDisconnect(modelData)
      readonly property bool canPair: BluetoothService.canPair(modelData)
      readonly property bool isBusy: BluetoothService.isDeviceBusy(modelData)
      readonly property bool isExpanded: btprefs.expandedDeviceKey === BluetoothService.deviceKey(modelData)

      function getContentColor(defaultColor = Color.mOnSurface) {
        if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
          return Color.mPrimary;
        if (modelData.blocked || modelData.state === BluetoothDeviceState.Disconnecting)
          return Color.mError;
        return defaultColor;
      }

      Layout.fillWidth: true
      Layout.preferredHeight: deviceColumn.implicitHeight + (Style.marginXL)
      radius: Style.radiusM
      clip: true

      color: (modelData.connected && modelData.state !== BluetoothDeviceState.Disconnecting) ? Qt.alpha(Color.mPrimary, 0.15) : Color.mSurface

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

          NIcon {
            icon: BluetoothService.getDeviceIcon(modelData)
            pointSize: Style.fontSizeXXL
            color: modelData.connected ? Color.mPrimary : device.getContentColor(Color.mOnSurface)
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS

            NText {
              text: modelData.name || modelData.deviceName
              pointSize: Style.fontSizeM
              font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
              elide: Text.ElideRight
              color: device.getContentColor(Color.mOnSurface)
              Layout.fillWidth: true
            }

            NText {
              text: {
                const k = BluetoothService.getStatusKey(modelData);
                if (k === "pairing")
                  return I18n.tr("common.pairing");
                if (k === "blocked")
                  return I18n.tr("bluetooth.panel.blocked");
                if (k === "connecting")
                  return I18n.tr("common.connecting");
                if (k === "disconnecting")
                  return I18n.tr("common.disconnecting");
                return "";
              }
              visible: text !== ""
              pointSize: Style.fontSizeXS
              color: device.getContentColor(Color.mOnSurfaceVariant)
            }

            RowLayout {
              visible: modelData.batteryAvailable
              spacing: Style.marginS
              NIcon {
                icon: {
                  var b = BluetoothService.getBatteryPercent(modelData);
                  return BatteryService.getIcon(b !== null ? b : 0, false, false, b !== null);
                }
                pointSize: Style.fontSizeXS
                color: device.getContentColor(Color.mOnSurface)
              }
              NText {
                text: {
                  var b = BluetoothService.getBatteryPercent(modelData);
                  return b === null ? "-" : (b + "%");
                }
                pointSize: Style.fontSizeXS
                color: device.getContentColor(Color.mOnSurfaceVariant)
              }
            }
          }

          Item {
            Layout.fillWidth: true
          }

          RowLayout {
            spacing: Style.marginS

            NIconButton {
              visible: modelData.connected
              icon: "info"
              tooltipText: I18n.tr("common.info")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                const key = BluetoothService.deviceKey(modelData);
                btprefs.expandedDeviceKey = (btprefs.expandedDeviceKey === key) ? "" : key;
              }
            }

            NIconButton {
              visible: !btprefs.showOnlyLists && (modelData.paired || modelData.trusted) && !modelData.connected && !isBusy && !modelData.blocked
              icon: "trash"
              tooltipText: I18n.tr("common.unpair")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: BluetoothService.unpairDevice(modelData)
            }

            NButton {
              id: button
              visible: (modelData.state !== BluetoothDeviceState.Connecting)
              enabled: (canConnect || canDisconnect || (btprefs.showOnlyLists ? false : canPair)) && !isBusy
              outlined: !button.hovered
              fontSize: Style.fontSizeS
              backgroundColor: modelData.connected ? Color.mError : Color.mPrimary
              text: {
                if (modelData.pairing)
                  return I18n.tr("common.pairing");
                if (modelData.blocked)
                  return I18n.tr("bluetooth.panel.blocked");
                if (modelData.connected)
                  return I18n.tr("common.disconnect");
                if (!btprefs.showOnlyLists && device.canPair)
                  return I18n.tr("common.pair");
                return I18n.tr("common.connect");
              }
              icon: (isBusy ? "busy" : null)
              onClicked: {
                if (modelData.connected) {
                  BluetoothService.disconnectDevice(modelData);
                } else {
                  if (!btprefs.showOnlyLists && device.canPair) {
                    BluetoothService.pairDevice(modelData);
                  } else {
                    BluetoothService.connectDeviceWithTrust(modelData);
                  }
                }
              }
            }
          }
        }

        // Expanded info section
        Rectangle {
          visible: device.isExpanded
          Layout.fillWidth: true
          implicitHeight: infoColumn.implicitHeight + Style.marginS * 2
          radius: Style.radiusS
          color: Color.mSurfaceVariant
          border.width: Style.borderS
          border.color: Color.mOutline
          clip: true

          NIconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.marginS
            icon: btprefs.detailsGrid ? "layout-list" : "layout-grid"
            tooltipText: btprefs.detailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              btprefs.detailsGrid = !btprefs.detailsGrid;
              if (Settings.data && Settings.data.ui) {
                Settings.data.network.bluetoothDetailsViewMode = btprefs.detailsGrid ? "grid" : "list";
              }
            }
            z: 1
          }

          GridLayout {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Style.marginS
            columns: btprefs.detailsGrid ? 2 : 1
            columnSpacing: Style.marginM
            rowSpacing: Style.marginXS

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.marginXS
              NIcon {
                icon: BluetoothService.getSignalIcon(modelData)
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: BluetoothService.getSignalStrength(modelData)
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.marginXS
              NIcon {
                icon: {
                  var b = BluetoothService.getBatteryPercent(modelData);
                  return BatteryService.getIcon(b !== null ? b : 0, false, false, b !== null);
                }
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: {
                  var b = BluetoothService.getBatteryPercent(modelData);
                  return b === null ? "-" : (b + "%");
                }
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginXS
              NIcon {
                icon: "link"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.paired ? I18n.tr("common.yes") : I18n.tr("common.no")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginXS
              NIcon {
                icon: "shield-check"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.trusted ? I18n.tr("common.yes") : I18n.tr("common.no")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }
            RowLayout {
              Layout.fillWidth: true
              Layout.columnSpan: infoColumn.columns === 2 ? 2 : 1
              spacing: Style.marginXS
              NIcon {
                icon: "hash"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.address || "-"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }
          }
        }
      }
    }
  }

  // PIN Authentication Overlay
  Rectangle {
    id: pinOverlay
    visible: !btprefs.showOnlyLists && BluetoothService.pinRequired
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.9, 400)
    height: pinCol.implicitHeight + Style.marginL * 2
    color: Color.mSurface
    radius: Style.radiusM
    border.color: Style.boxBorderColor
    border.width: Style.borderS
    z: 1000

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: mouse => mouse.accepted = true
      onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
      id: pinCol
      anchors.fill: parent
      anchors.margins: Style.marginL
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
        Layout.fillWidth: true
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
        onVisibleChanged: {
          if (visible) {
            text = "";
            inputItem.forceActiveFocus();
          }
        }
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
