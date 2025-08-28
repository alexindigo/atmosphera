import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL * scaling

  // Brightness Step Section
  ColumnLayout {
    spacing: Style.marginS * scaling
    Layout.fillWidth: true

    NSpinBox {
      Layout.fillWidth: true
      label: "Brightness Step Size"
      description: "Adjust the step size for brightness changes (scroll wheel, keyboard shortcuts)."
      minimum: 1
      maximum: 50
      value: Settings.data.brightness.brightnessStep
      stepSize: 1
      suffix: "%"
      onValueChanged: {
        Settings.data.brightness.brightnessStep = value
      }
    }
  }

  // Monitor Overview Section
  ColumnLayout {
    spacing: Style.marginL * scaling

    NLabel {
      label: "Monitors Brightness Control"
      description: "Current brightness levels for all detected monitors."
    }

    // Single monitor display using the same data source as the bar icon
    Repeater {
      model: BrightnessService.monitors
      Rectangle {
        Layout.fillWidth: true
        radius: Style.radiusM * scaling
        color: Color.mSurface
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        implicitHeight: contentCol.implicitHeight + Style.marginXL * 2 * scaling

        ColumnLayout {
          id: contentCol
          anchors.fill: parent
          anchors.margins: Style.marginL * scaling
          spacing: Style.marginM * scaling

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM * scaling

            NText {
              text: `${model.modelData.name} [${model.modelData.model}]`
              font.pointSize: Style.fontSizeL * scaling
              font.weight: Style.fontWeightBold
              color: Color.mSecondary
            }

            Item {
              Layout.fillWidth: true
            }

            NText {
              text: model.method
              font.pointSize: Style.fontSizeXS * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignRight
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM * scaling

            NText {
              text: "Brightness:"
              font.pointSize: Style.fontSizeM * scaling
              color: Color.mOnSurface
            }

            NSlider {
              Layout.fillWidth: true
              from: 0
              to: 1
              value: model.brightness
              stepSize: 0.05
              onPressedChanged: {
                if (!pressed) {
                  var monitor = BrightnessService.getMonitorForScreen(model.modelData)
                  monitor.setBrightness(value)
                }
              }
            }

            NText {
              text: Math.round(model.brightness * 100) + "%"
              font.pointSize: Style.fontSizeM * scaling
              font.weight: Style.fontWeightBold
              color: Color.mPrimary
              Layout.alignment: Qt.AlignRight
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }
}
