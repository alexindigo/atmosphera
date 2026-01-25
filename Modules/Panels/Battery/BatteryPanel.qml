import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(460 * Style.uiScaleRatio)

  onOpened: {
    BatteryService.refreshHealth();
  }

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainLayout.implicitHeight + Style.marginL * 2

    // Get device selection from Battery widget settings (check right section first, then any Battery widget)
    function getBatteryDevicePath() {
      var widget = BarService.lookupWidget("Battery");
      if (widget !== undefined && widget.deviceNativePath !== undefined) {
        return widget.deviceNativePath;
      }
      return "";
    }

    readonly property string deviceNativePath: getBatteryDevicePath()
    readonly property var battery: BatteryService.findUPowerDevice(deviceNativePath)
    readonly property var bluetoothDevice: deviceNativePath ? BatteryService.findBluetoothDevice(deviceNativePath) : null
    readonly property var device: bluetoothDevice || battery

    // Check if device is actually present/connected
    readonly property bool isDevicePresent: BatteryService.isDevicePresent(device)
    readonly property bool isReady: BatteryService.isDeviceReady(device)

    readonly property bool hasBluetoothBattery: BatteryService.isBluetoothDevice(device)
    readonly property int percent: isReady ? Math.round(BatteryService.getPercentage(device)) : -1
    readonly property bool isCharging: BatteryService.isCharging(device)
    readonly property bool isPluggedIn: BatteryService.isPluggedIn(device)
    readonly property bool healthAvailable: (isReady && battery && battery.healthSupported) || BatteryService.healthAvailable
    readonly property int healthPercent: (isReady && battery && battery.healthSupported) ? Math.round(battery.healthPercentage) : BatteryService.healthPercent

    readonly property string deviceName: BatteryService.getDeviceName(device)
    readonly property string panelTitle: deviceName ? `${I18n.tr("common.battery")} - ${deviceName}` : I18n.tr("common.battery")

    readonly property string timeText: {
      if (!isReady || !isDevicePresent)
        return I18n.tr("battery.no-battery-detected");
      if (isPluggedIn) {
        return I18n.tr("battery.plugged-in");
      }
      if (battery) {
        if (battery.timeToFull > 0) {
          return I18n.tr("battery.time-until-full", {
                           "time": Time.formatVagueHumanReadableDuration(battery.timeToFull)
                         });
        }
        if (battery.timeToEmpty > 0) {
          return I18n.tr("battery.time-left", {
                           "time": Time.formatVagueHumanReadableDuration(battery.timeToEmpty)
                         });
        }
      }
      return I18n.tr("common.idle");
    }
    readonly property string iconName: BatteryService.getIcon(percent, isCharging, isPluggedIn, isReady)

    property var batteryWidgetInstance: BarService.lookupWidget("Battery", screen ? screen.name : null)
    readonly property var batteryWidgetSettings: batteryWidgetInstance ? batteryWidgetInstance.widgetSettings : null
    readonly property var batteryWidgetMetadata: BarWidgetRegistry.widgetMetadata["Battery"]
    readonly property bool powerProfileAvailable: PowerProfileService.available
    readonly property var powerProfiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    readonly property bool profilesAvailable: PowerProfileService.available
    property int profileIndex: profileToIndex(PowerProfileService.profile)
    readonly property bool showPowerProfiles: resolveWidgetSetting("showPowerProfiles", false)
    readonly property bool showNoctaliaPerformance: resolveWidgetSetting("showNoctaliaPerformance", false)

    function profileToIndex(p) {
      return powerProfiles.indexOf(p) ?? 1;
    }

    function indexToProfile(idx) {
      return powerProfiles[idx] ?? PowerProfile.Balanced;
    }

    function setProfileByIndex(idx) {
      var prof = indexToProfile(idx);
      profileIndex = idx;
      PowerProfileService.setProfile(prof);
    }

    function resolveWidgetSetting(key, defaultValue) {
      if (batteryWidgetSettings && batteryWidgetSettings[key] !== undefined)
        return batteryWidgetSettings[key];
      if (batteryWidgetMetadata && batteryWidgetMetadata[key] !== undefined)
        return batteryWidgetMetadata[key];
      return defaultValue;
    }

    Connections {
      target: PowerProfileService
      function onProfileChanged() {
        panelContent.profileIndex = panelContent.profileToIndex(PowerProfileService.profile);
      }
    }

    Connections {
      target: BarService
      function onActiveWidgetsChanged() {
        panelContent.batteryWidgetInstance = BarService.lookupWidget("Battery", screen ? screen.name : null);
      }
    }

    ColumnLayout {
      id: mainLayout
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginXL)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            pointSize: Style.fontSizeXXL
            color: (isCharging || isPluggedIn) ? Color.mPrimary : Color.mOnSurface
            icon: iconName
          }

          ColumnLayout {
            spacing: Style.marginXXS
            Layout.fillWidth: true

            NText {
              text: panelTitle
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            NText {
              text: timeText
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }

      // Charge level + health/time
      NBox {
        Layout.fillWidth: true
        implicitHeight: chargeLayout.implicitHeight + Style.marginL * 2
        visible: isReady

        ColumnLayout {
          id: chargeLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            ColumnLayout {
              NText {
                text: I18n.tr("battery.battery-level")
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
              }

              Rectangle {
                Layout.fillWidth: true
                height: Math.round(8 * Style.uiScaleRatio)
                radius: Math.min(Style.radiusL, height / 2)
                color: Color.mSurfaceVariant

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height
                  radius: parent.radius
                  width: {
                    var ratio = Math.max(0, Math.min(1, percent / 100));
                    return parent.width * ratio;
                  }
                  color: Color.mPrimary
                }
              }
            }

            NText {
              text: percent >= 0 ? `${percent}%` : "--"
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightBold
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: healthAvailable

            ColumnLayout {
              RowLayout {
                spacing: Style.marginXS

                NText {
                  text: I18n.tr("battery.battery-health")
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeS
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: Math.round(8 * Style.uiScaleRatio)
                radius: Math.min(Style.radiusL, height / 2)
                color: Color.mSurfaceVariant

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height
                  radius: parent.radius
                  width: {
                    if (!healthAvailable || healthPercent <= 0)
                      return 0;
                    var ratio = Math.max(0, Math.min(1, healthPercent / 100));
                    return parent.width * ratio;
                  }
                  color: healthPercent >= 80 ? Color.mPrimary : (healthPercent >= 50 ? Color.mTertiary : Color.mError)
                }
              }
            }

            NText {
              text: healthPercent >= 0 ? `${healthPercent}%` : "--"
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightBold
            }
          }
        }
      }

      NBox {
        Layout.fillWidth: true
        height: controlsLayout.implicitHeight + Style.marginL * 2
        visible: showPowerProfiles || showNoctaliaPerformance

        ColumnLayout {
          id: controlsLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          ColumnLayout {
            visible: powerProfileAvailable && showPowerProfiles

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NText {
                text: I18n.tr("battery.power-profile")
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
              NText {
                text: PowerProfileService.getName(profileIndex)
                color: Color.mOnSurfaceVariant
              }
            }

            NValueSlider {
              Layout.fillWidth: true
              from: 0
              to: 2
              stepSize: 1
              snapAlways: true
              heightRatio: 0.5
              value: profileIndex
              enabled: profilesAvailable
              onPressedChanged: (pressed, v) => {
                                  if (!pressed) {
                                    setProfileByIndex(v);
                                  }
                                }
              onMoved: v => {
                         profileIndex = v;
                       }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NIcon {
                icon: "powersaver"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "powersaver" ? Color.mPrimary : Color.mOnSurfaceVariant
              }
              NIcon {
                icon: "balanced"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "balanced" ? Color.mPrimary : Color.mOnSurfaceVariant
                Layout.fillWidth: true
              }
              NIcon {
                icon: "performance"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "performance" ? Color.mPrimary : Color.mOnSurfaceVariant
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
            visible: showPowerProfiles && showNoctaliaPerformance
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: showNoctaliaPerformance

            NText {
              text: I18n.tr("toast.noctalia-performance.label")
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
            NIcon {
              icon: PowerProfileService.noctaliaPerformanceMode ? "rocket" : "rocket-off"
              pointSize: Style.fontSizeL
              color: PowerProfileService.noctaliaPerformanceMode ? Color.mPrimary : Color.mOnSurfaceVariant
            }
            NToggle {
              checked: PowerProfileService.noctaliaPerformanceMode
              onToggled: checked => PowerProfileService.noctaliaPerformanceMode = checked
            }
          }
        }
      }
    }
  }
}
