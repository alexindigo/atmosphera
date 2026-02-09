import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Bluetooth

import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets
import qs.Modules.Panels.Bluetooth

Item {
  id: btprefs
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight // Do i hate locating qml Items? - Absolutely yes

  property bool isScanningActive: BluetoothService.scanningActive
  property bool isDiscoverable: BluetoothService.discoverable

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
    if (effectivelyVisible && BluetoothService.enabled) {
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
          } // Spacer to push toggle to the right

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
    BluetoothDevicesList {
      id: connectedDevicesList
      label: I18n.tr("bluetooth.panel.connected-devices")
      headerMode: "layout"
      property var connectedDevices: {
        if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
          return [];
        var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && dev.connected);
        filtered = BluetoothService.dedupeDevices(filtered);
        return BluetoothService.sortDevices(filtered);
      }
      model: connectedDevices
      visible: connectedDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
      visible: connectedDevicesList.visible
    }

    // Devices List [2] (Paired)
    BluetoothDevicesList {
      id: pairedDevicesList
      label: I18n.tr("bluetooth.panel.paired-devices")
      headerMode: "layout"
      property var pairedDevices: {
        if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
          return [];
        var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.connected && (dev.paired || dev.trusted));
        filtered = BluetoothService.dedupeDevices(filtered);
        return BluetoothService.sortDevices(filtered);
      }
      model: pairedDevices
      visible: pairedDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
      visible: pairedDevicesList.visible
    }

    // Device List [3] (Ready to pair // discovered)
    BluetoothDevicesList {
      id: availableDevicesList
      label: I18n.tr("bluetooth.panel.available-devices") + (BluetoothService.scanningActive ? " (" + I18n.tr("bluetooth.panel.scanning") + ")" : "")  // I would prefered something animated here but as far as im aware there is no such thing.
      headerMode: "filter"
      property var availableDevices: {
        if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
          return [];
        var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.paired && !dev.trusted);

        // Optionally hide devices without a meaningful name when the filter is enabled
        if (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) {
          filtered = filtered.filter(function (dev) {
            // Extract device name
            var dn = dev.name || dev.deviceName || "";
            // 1) Hide empty or whitespace-only
            var s = String(dn).trim();
            if (s.length === 0)
              return false;

            // 2) Hide common placeholders
            var lower = s.toLowerCase();
            if (lower === "unknown" || lower === "unnamed" || lower === "n/a" || lower === "na") {
              return false;
            }

            // 3) Hide if the name equals the device address (ignoring separators)
            var addr = dev.address || dev.bdaddr || dev.mac || "";
            if (addr.length > 0) {
              var normName = s.toLowerCase().replace(/[^0-9a-z]/g, "");
              var normAddr = String(addr).toLowerCase().replace(/[^0-9a-z]/g, "");
              if (normName.length > 0 && normName === normAddr)
                return false;
            }
            // 4) Hide address-like strings
            //   - Colon-separated hex: 00:11:22:33:44:55
            var macColonHex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;
            //   - Hyphen-separated hex: 00-11-22-33-44-55
            var macHyphenHex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
            //   - Hyphen-separated alnum pairs (to catch non-hex variants like AB-CD-EF-GH-01-23)
            var macHyphenAny = /^([0-9A-Za-z]{2}-){5}[0-9A-Za-z]{2}$/;
            //   - Cisco dotted hex: 0011.2233.4455
            var macDotted = /^[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}$/;
            //   - Bare hex: 001122334455
            var macBare = /^[0-9A-Fa-f]{12}$/;
            if (macColonHex.test(s) || macHyphenHex.test(s) || macHyphenAny.test(s) || macDotted.test(s) || macBare.test(s)) {
              return false;
            }

            // Keep device otherwise (has a meaningful user-facing name)
            return true;
          });
        }
        filtered = BluetoothService.dedupeDevices(filtered);
        return BluetoothService.sortDevices(filtered);
      }
      model: availableDevices
      visible: availableDevices.length > 0 && BluetoothService.adapter && BluetoothService.adapter.enabled
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
      visible: availableDevicesList.visible
    }

    // RSSI Polling
    NBox {
      Layout.fillWidth: true
      visible: BluetoothService.enabled
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

  // PIN Authentication Overlay
  Rectangle {
    id: pinOverlay
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.9, 400)
    height: pinCol.implicitHeight + Style.marginL * 2
    color: Color.mSurface
    radius: Style.radiusM
    border.color: Style.boxBorderColor
    border.width: Style.borderS
    visible: BluetoothService.pinRequired
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
        text: I18n.tr("common.authentication-required") // TODO: missing: i18n
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
      }

      NText {
        text: I18n.tr("bluetooth.panel.pin-instructions")  // TODO: missing: i18n
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
          text: I18n.tr("common.confirm") // TODO: i18n
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
