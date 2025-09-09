import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets

// Power Profiles: performance, balanced, eco
NBox {
  Layout.fillWidth: true
  Layout.preferredWidth: 1
  implicitHeight: powerRow.implicitHeight + Style.marginM * 2 * scaling

  // PowerProfiles service
  property var powerProfiles: PowerProfiles
  readonly property bool hasPP: powerProfiles.hasPerformanceProfile
  property real spacing: 0

  RowLayout {
    id: powerRow
    anchors.fill: parent
    anchors.margins: Style.marginS * scaling
    spacing: spacing
    Item {
      Layout.fillWidth: true
    }
    // Performance
    NIconButton {
      icon: "speedometer2"
      tooltipText: "Set performance power profile."
      enabled: hasPP
      opacity: enabled ? Style.opacityFull : Style.opacityMedium
      colorBg: (enabled && powerProfiles.profile === PowerProfile.Performance) ? Color.mPrimary : Color.mSurfaceVariant
      colorFg: (enabled && powerProfiles.profile === PowerProfile.Performance) ? Color.mOnPrimary : Color.mPrimary
      onClicked: {
        if (enabled) {
          powerProfiles.profile = PowerProfile.Performance
          ToastService.showNotice("Power Profile", "Performance")
        }
      }
    }
    // Balanced
    NIconButton {
      icon: "yin-yang"
      tooltipText: "Set balanced power profile."
      enabled: hasPP
      opacity: enabled ? Style.opacityFull : Style.opacityMedium
      colorBg: (enabled && powerProfiles.profile === PowerProfile.Balanced) ? Color.mPrimary : Color.mSurfaceVariant
      colorFg: (enabled && powerProfiles.profile === PowerProfile.Balanced) ? Color.mOnPrimary : Color.mPrimary
      onClicked: {
        if (enabled) {
          powerProfiles.profile = PowerProfile.Balanced
          ToastService.showNotice("Power Profile", "Balanced")
        }
      }
    }
    // Eco
    NIconButton {
      icon: "leaf"
      tooltipText: "Set eco power profile."
      enabled: hasPP
      opacity: enabled ? Style.opacityFull : Style.opacityMedium
      colorBg: (enabled && powerProfiles.profile === PowerProfile.PowerSaver) ? Color.mPrimary : Color.mSurfaceVariant
      colorFg: (enabled && powerProfiles.profile === PowerProfile.PowerSaver) ? Color.mOnPrimary : Color.mPrimary
      onClicked: {
        if (enabled) {
          powerProfiles.profile = PowerProfile.PowerSaver
          ToastService.showNotice("Power Profile", "Power Saver")
        }
      }
    }
    Item {
      Layout.fillWidth: true
    }
  }
}
