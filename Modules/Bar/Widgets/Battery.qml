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
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property real warningThreshold: widgetSettings.warningThreshold !== undefined ? widgetSettings.warningThreshold : widgetMetadata.warningThreshold
  readonly property bool hideIfNotDetected: widgetSettings.hideIfNotDetected !== undefined ? widgetSettings.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  readonly property bool hideIfIdle: widgetSettings.hideIfIdle !== undefined ? widgetSettings.hideIfIdle : widgetMetadata.hideIfIdle
  // Only show low battery warning if device is ready (prevents false positive during initialization)
  readonly property bool isLowBattery: isReady && (!isCharging && !isPluggedIn) && percent <= warningThreshold

  // Visibility: show if hideIfNotDetected is false, or if battery is ready (after initialization)
  readonly property bool shouldShow: !hideIfNotDetected || (isReady && (hideIfIdle ? (!isCharging && !isPluggedIn) : true))

  // Test mode
  readonly property bool testMode: false
  readonly property int testPercent: 35
  readonly property bool testCharging: false
  readonly property bool testPluggedIn: false
  readonly property string deviceNativePath: widgetSettings.deviceNativePath || ""

  readonly property var battery: BatteryService.findUPowerDevice(deviceNativePath)
  readonly property var bluetoothDevice: deviceNativePath ? BatteryService.findBluetoothDevice(deviceNativePath) : null
  readonly property var device: {
    if (deviceNativePath)
      return bluetoothDevice || battery;
    return BatteryService.primaryDevice;
  }
  readonly property bool hasBluetoothBattery: BatteryService.isBluetoothDevice(device)

  readonly property bool isReady: testMode ? true : (initializationComplete && BatteryService.isDeviceReady(device))
  readonly property real percent: testMode ? testPercent : (isReady ? BatteryService.getPercentage(device) : 0)
  readonly property bool isCharging: testMode ? testCharging : (isReady ? BatteryService.isCharging(device) : false)
  readonly property bool isPluggedIn: testMode ? testPluggedIn : (isReady ? BatteryService.isPluggedIn(device) : false)

  property bool initializationComplete: false
  property bool hasNotifiedLowBattery: false

  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

  Timer {
    interval: 500
    running: true
    onTriggered: root.initializationComplete = true
  }

  readonly property bool isDevicePresent: {
    if (testMode)
      return true;
    return BatteryService.isDevicePresent(device);
  }

  implicitWidth: pill.width
  implicitHeight: pill.height

  function maybeNotify(currentPercent, charging, pluggedIn, isReady) {
    if (isReady && (!charging && !pluggedIn) && !hasNotifiedLowBattery && currentPercent <= warningThreshold) {
      hasNotifiedLowBattery = true;
      ToastService.showWarning(I18n.tr("toast.battery.low"), I18n.tr("toast.battery.low-desc", {
                                                                       "percent": Math.round(currentPercent)
                                                                     }), "battery-exclamation", "warning", 4000, "", null);
    } else if (hasNotifiedLowBattery && (charging || pluggedIn || currentPercent > warningThreshold + 5)) {
      hasNotifiedLowBattery = false;
    }
  }

  function getCurrentPercent() {
    return BatteryService.getPercentage(device);
  }

  Connections {
    target: device
    function onPercentageChanged() {
      if (device) {
        maybeNotify(getCurrentPercent(), isCharging, isPluggedIn, isReady);
      }
    }

    function onStateChanged() {
      if (device) {
        if (isCharging || isPluggedIn) {
          hasNotifiedLowBattery = false;
        }
        maybeNotify(getCurrentPercent(), isCharging, isPluggedIn, isReady);
      }
    }
  }

  Connections {
    target: (device && BatteryService.isBluetoothDevice(device)) ? device : null
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
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: testMode ? BatteryService.getIcon(testPercent, testCharging, testPluggedIn, true) : BatteryService.getIcon(percent, isCharging, isPluggedIn, isReady)
    text: (isReady || testMode) ? Math.round(percent) : "-"
    suffix: "%"
    autoHide: false
    forceOpen: isReady && displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide" || (initializationComplete && !isReady)
    customBackgroundColor: !initializationComplete ? "transparent" : (isCharging ? Color.mPrimary : (isLowBattery ? Color.mError : "transparent"))
    customTextIconColor: !initializationComplete ? "transparent" : (isCharging ? Color.mOnPrimary : (isLowBattery ? Color.mOnError : "transparent"))

    tooltipText: {
      let lines = [];
      if (testMode) {
        lines.push("Time left: " + Time.formatVagueHumanReadableDuration(12345) + ".");
        return lines.join("\n");
      }
      if (!isReady || !isDevicePresent) {
        return I18n.tr("battery.no-battery-detected");
      }
      const isInternal = device === BatteryService.primaryDevice && BatteryService.isLaptopBattery;

      if (isInternal) {
        let timeText = BatteryService.getTimeRemainingText(device);
        if (timeText && timeText !== I18n.tr("common.idle") && timeText !== I18n.tr("battery.no-battery-detected") && timeText !== I18n.tr("battery.plugged-in")) {
          lines.push(timeText);
        }

        let rateText = BatteryService.getRateText(device);
        if (rateText) {
          lines.push(rateText);
        }
      } else if (device) {
        // External / Peripheral Device (Phone, Keyboard, Mouse, Gamepad, Headphone etc.)
        let name = BatteryService.getDeviceName(device);
        let pct = Math.round(BatteryService.getPercentage(device));
        lines.push(name + ": " + pct + suffix);
      }

      // If we are showing the main laptop battery, append external devices
      if (isInternal) {
        var external = BatteryService.externalBatteries;
        if (external.length > 0) {
          if (lines.length > 0)
            lines.push(""); // Separator
          for (var j = 0; j < external.length; j++) {
            var dev = external[j];
            var dName = BatteryService.getDeviceName(dev);
            var dPct = Math.round(BatteryService.getPercentage(dev));
            lines.push(dName + ": " + dPct + suffix);
          }
        }
      }
      return lines.join("\n");
    }

    onClicked: PanelService.getPanel("batteryPanel", screen)?.toggle(this)
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
  }
}
