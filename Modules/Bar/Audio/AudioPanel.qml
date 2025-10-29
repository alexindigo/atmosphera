import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  property real localOutputVolume: AudioService.volume || 0
  property bool localOutputVolumeChanging: false

  property real localInputVolume: AudioService.inputVolume || 0
  property bool localInputVolumeChanging: false

  preferredWidth: 380 * Style.uiScaleRatio
  preferredHeight: 500 * Style.uiScaleRatio
  panelKeyboardFocus: true

  // Connections to update local volumes when AudioService changes
  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      if (!localOutputVolumeChanging) {
        localOutputVolume = AudioService.volume
      }
    }
  }

  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onVolumeChanged() {
      if (!localInputVolumeChanging) {
        localInputVolume = AudioService.inputVolume
      }
    }
  }

  // Timer to debounce volume changes
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (Math.abs(localOutputVolume - AudioService.volume) >= 0.01) {
        AudioService.setVolume(localOutputVolume)
      }
      if (Math.abs(localInputVolume - AudioService.inputVolume) >= 0.01) {
        AudioService.setInputVolume(localInputVolume)
      }
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "settings-audio"
          pointSize: Style.fontSizeXXL
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("settings.audio.title")
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: AudioService.getOutputIcon()
          tooltipText: I18n.tr("tooltips.output-muted")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            AudioService.setOutputMuted(!AudioService.muted)
          }
        }

        NIconButton {
          icon: AudioService.getInputIcon()
          tooltipText: I18n.tr("tooltips.input-muted")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            AudioService.setInputMuted(!AudioService.inputMuted)
          }
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("tooltips.close")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            root.close()
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        clip: true
        contentWidth: availableWidth

        // AudioService Devices
        ColumnLayout {
          spacing: Style.marginS
          Layout.fillWidth: true

          // -------------------------------
          // Output Devices
          ButtonGroup {
            id: sinks
          }

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Layout.bottomMargin: Style.marginL

            RowLayout {
              spacing: Style.spacingM * Style.uiScaling
              Layout.bottomMargin: Style.marginL

              NText {
                text: I18n.tr("settings.audio.devices.output-device.label")
                pointSize: Style.fontSizeL
                color: Color.mPrimary
                Layout.preferredWidth: root.preferredWidth * 0.3
              }

              // Output Volume Slider
              NValueSlider {
                Layout.fillWidth: true
                Layout.maximumWidth: root.preferredWidth * 0.6
                from: 0
                to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                value: localOutputVolume
                stepSize: 0.01
                heightRatio: 0.5
                onMoved: value => localOutputVolume = value
                onPressedChanged: (pressed, value) => localOutputVolumeChanging = pressed
                text: Math.round(localOutputVolume * 100) + "%"
              }
            }

            Repeater {
              model: AudioService.sinks
              NRadioButton {
                ButtonGroup.group: sinks
                required property PwNode modelData
                pointSize: Style.fontSizeS
                text: modelData.description
                checked: AudioService.sink?.id === modelData.id
                onClicked: {
                  AudioService.setAudioSink(modelData)
                  localOutputVolume = AudioService.volume
                }
                Layout.fillWidth: true
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
          }

          // -------------------------------
          // Input Devices
          ButtonGroup {
            id: sources
          }

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true

            RowLayout {
              spacing: Style.spacingM * Style.uiScaling
              Layout.bottomMargin: Style.marginL

              NText {
                text: I18n.tr("settings.audio.devices.input-device.label")
                pointSize: Style.fontSizeL
                color: Color.mPrimary
                Layout.preferredWidth: root.preferredWidth * 0.3
              }

              // Input Volume Slider
              NValueSlider {
                Layout.fillWidth: true
                Layout.maximumWidth: root.preferredWidth * 0.6
                from: 0
                to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                value: localInputVolume
                stepSize: 0.01
                heightRatio: 0.5
                onMoved: value => localInputVolume = value
                onPressedChanged: (pressed, value) => localInputVolumeChanging = pressed
                text: Math.round(localInputVolume * 100) + "%"
              }
            }

            Repeater {
              model: AudioService.sources
              //Layout.fillWidth: true
              NRadioButton {
                ButtonGroup.group: sources
                required property PwNode modelData
                pointSize: Style.fontSizeS
                text: modelData.description
                checked: AudioService.source?.id === modelData.id
                onClicked: AudioService.setAudioSource(modelData)
                Layout.fillWidth: true
              }
            }
          }
          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
