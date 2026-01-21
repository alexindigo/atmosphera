import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property real warningThreshold: widgetSettings.warningThreshold !== undefined ? widgetSettings.warningThreshold : widgetMetadata.warningThreshold
  readonly property bool hideIfNotDetected: widgetSettings.hideIfNotDetected !== undefined ? widgetSettings.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  readonly property bool hideIfIdle: widgetSettings.hideIfIdle !== undefined ? widgetSettings.hideIfIdle : widgetMetadata.hideIfIdle
  // Only show low battery warning if device is ready (prevents false positive during initialization)
  readonly property bool isLowBattery: isReady && (!charging && !isPluggedIn) && percent <= warningThreshold

  // Visibility: show if hideIfNotDetected is false, or if battery is ready (after initialization)
  readonly property bool shouldShow: !hideIfNotDetected || (isReady && (hideIfIdle ? (!charging && !isPluggedIn) : true))
  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

  // Test mode
  readonly property bool testMode: false
  readonly property int testPercent: 35
  readonly property bool testCharging: false
  readonly property bool testPluggedIn: false
  readonly property string deviceNativePath: widgetSettings.deviceNativePath || ""

  function findBatteryDevice(nativePath) {
    if (!nativePath || !UPower.devices) {
      return UPower.displayDevice;
    }
    var devices = UPower.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.nativePath === nativePath && device.type !== UPowerDeviceType.LinePower && device.percentage !== undefined) {
        return device;
      }
    }
    return UPower.displayDevice;
  }

  function findBluetoothDevice(nativePath) {
    if (!nativePath || !BluetoothService.devices) {
      return null;
    }
    var macMatch = nativePath.match(/([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})/);
    if (!macMatch) {
      return null;
    }
    var macAddress = macMatch[1].toUpperCase();
    var devices = BluetoothService.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.address && device.address.toUpperCase() === macAddress) {
        return device;
      }
    }
    return null;
  }

  readonly property var battery: findBatteryDevice(deviceNativePath)
  readonly property var bluetoothDevice: deviceNativePath ? findBluetoothDevice(deviceNativePath) : null
  readonly property bool hasBluetoothBattery: bluetoothDevice && bluetoothDevice.batteryAvailable && bluetoothDevice.battery !== undefined
  readonly property bool isBluetoothConnected: bluetoothDevice && bluetoothDevice.connected === true

  property bool initializationComplete: false
  Timer {
    interval: 500
    running: true
    onTriggered: root.initializationComplete = true
  }

  readonly property bool isDevicePresent: {
    if (testMode)
      return true;
    if (deviceNativePath) {
      if (bluetoothDevice) {
        return isBluetoothConnected;
      }
      if (battery && battery.nativePath === deviceNativePath) {
        if (battery.type === UPowerDeviceType.Battery && battery.isPresent !== undefined) {
          return battery.isPresent;
        }
        return battery.ready && battery.percentage !== undefined && (battery.percentage > 0 || chargingStatus(battery.state));
      }
      return false;
    }
    if (battery) {
      // For default device, check isPresent if it's a Battery type, otherwise require percentage > 0
      if (battery.type === UPowerDeviceType.Battery && battery.isPresent !== undefined) {
        return battery.isPresent;
      }
      // For non-battery types or when isPresent is undefined, require actual percentage
      return battery.ready && battery.percentage !== undefined && battery.percentage > 0;
    }
    return false;
  }

  readonly property bool isReady: testMode ? true : (initializationComplete && battery && battery.ready && isDevicePresent && (battery.percentage !== undefined || hasBluetoothBattery))
  readonly property real percent: testMode ? testPercent : (isReady ? (hasBluetoothBattery ? (bluetoothDevice.battery * 100) : (battery.percentage * 100)) : 0)
  readonly property bool charging: testMode ? testCharging : (isReady ? chargingStatus(battery.state) : false)  // Assuming not charging if battery is not ready
  readonly property bool isPluggedIn: testMode ? testPluggedIn : (isReady ? getPluggedInStatus(battery.state) : false) // We can be plugged in or charging but can't both.

  property bool hasNotifiedLowBattery: false

  implicitWidth: pill.width
  implicitHeight: pill.height
  // http://upower.freedesktop.org/docs/Device.html#Device.properties
  function chargingStatus(state) {
    switch (state) {
    case UPowerDeviceState.Charging: // 1
      // Logger.e("Battery", "Battery is charging (Battery is charging with " + (Math.floor(battery.changeRate * 10) / 10).toFixed(1) + "W)"); // debug
      return true;
    case UPowerDeviceState.Discharging: // 2
    case UPowerDeviceState.Empty: // 3
    case UPowerDeviceState.PendingDischarge: // 6
      return false;
    default:
      return false; // unknown state 0 Fix #1417
    }
  }
  function getPluggedInStatus(state) {
    // Treat low charge rate (< 5W) as plugged in but not actively charging (grace period)
    if (state === UPowerDeviceState.Charging && battery.changeRate !== undefined && Math.abs(battery.changeRate) < 5) {
      return true;
    }
    switch (state) {
    case UPowerDeviceState.FullyCharged: // 4
    case UPowerDeviceState.PendingCharge: // 5
      // Logger.e("Battery", "Battery is NOT charging (Power rate: " + (Math.floor(battery.changeRate * 10) / 10).toFixed(1) + "W)"); // debug
      return true;
    default:
      return false;
    }
  }
  function maybeNotify(currentPercent, isCharging, isPluggedIn, isReady) {
    if (isReady && (!isCharging && !isPluggedIn) && !hasNotifiedLowBattery && currentPercent <= warningThreshold) {
      hasNotifiedLowBattery = true;
      ToastService.showWarning(I18n.tr("toast.battery.low"), I18n.tr("toast.battery.low-desc", {
                                                                       "percent": Math.round(currentPercent)
                                                                     }));
      // Logger.e("Battery", "Low battery at " + (Math.floor(currentPercent).toFixed(1)) + "%", "isCharging: " + isCharging, "isPluggedIn: " + isPluggedIn, "isReady: " + isReady); // debug
    } else if (hasNotifiedLowBattery && (isCharging || isPluggedIn || currentPercent > warningThreshold + 5)) {
      hasNotifiedLowBattery = false;
    }
  }

  function getCurrentPercent() {
    return hasBluetoothBattery ? (bluetoothDevice.battery * 100) : (battery ? battery.percentage * 100 : 0);
  }

  Connections {
    target: battery
    function onPercentageChanged() {
      if (battery) {
        maybeNotify(getCurrentPercent(), chargingStatus(battery.state), getPluggedInStatus(battery.state), isReady);
      }
    }
    function onStateChanged() {
      if (battery) {
        if (chargingStatus(battery.state) || getPluggedInStatus(battery.state)) {
          hasNotifiedLowBattery = false;
        }
        maybeNotify(getCurrentPercent(), chargingStatus(battery.state), getPluggedInStatus(battery.state), isReady);
      }
    }
  }

  Connections {
    target: bluetoothDevice
    function onBatteryChanged() {
      if (bluetoothDevice && hasBluetoothBattery) {
        maybeNotify(bluetoothDevice.battery * 100, battery ? chargingStatus(battery.state) : false, battery ? getPluggedInStatus(battery.state) : false, true);
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: testMode ? BatteryService.getIcon(testPercent, testCharging, testPluggedIn, true) : BatteryService.getIcon(percent, charging, isPluggedIn, isReady)
    text: (isReady || testMode) ? Math.round(percent) : "-"
    suffix: "%"
    autoHide: false
    forceOpen: isReady && displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide" || (initializationComplete && !isReady)
    customBackgroundColor: !initializationComplete ? "transparent" : (charging ? Color.mPrimary : (isLowBattery ? Color.mError : "transparent"))
    customTextIconColor: !initializationComplete ? "transparent" : (charging ? Color.mOnPrimary : (isLowBattery ? Color.mOnError : "transparent"))

    tooltipText: {
      let lines = [];
      if (testMode) {
        lines.push(`Time left: ${Time.formatVagueHumanReadableDuration(12345)}.`);
        return lines.join("\n");
      }
      if (!isReady || !isDevicePresent) {
        return I18n.tr("battery.no-battery-detected");
      }
      if (battery.timeToEmpty > 0) {
        lines.push(I18n.tr("battery.time-left", {
                             "time": Time.formatVagueHumanReadableDuration(battery.timeToEmpty)
                           }));
      }
      if (battery.timeToFull > 0) {
        lines.push(I18n.tr("battery.time-until-full", {
                             "time": Time.formatVagueHumanReadableDuration(battery.timeToFull)
                           }));
      }
      if (battery.changeRate !== undefined) {
        const rate = Math.abs(battery.changeRate);
        if (charging) {
          lines.push(I18n.tr("battery.charging-rate", {
                               "rate": rate.toFixed(2)
                             }));
        } else if (isPluggedIn) {
          lines.push(I18n.tr("battery.plugged-in"));
        } else {
          lines.push(I18n.tr("battery.discharging-rate", {
                               "rate": rate.toFixed(2)
                             }));
        }
      }
      if (battery.healthPercentage !== undefined && battery.healthPercentage > 0) {
        lines.push(I18n.tr("battery.health", {
                             "percent": Math.round(battery.healthPercentage)
                           }));
      }
      return lines.join("\n");
    }
    onClicked: PanelService.getPanel("batteryPanel", screen)?.toggle(this)
    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        popupMenuWindow.showContextMenu(contextMenu);
        contextMenu.openAtItem(pill, screen);
      }
    }
  }
}
