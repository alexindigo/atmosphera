import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  readonly property real scaling: ScalingService.scale(screen)
  readonly property string tabIcon: "monitor"
  readonly property string tabLabel: "Display"
  readonly property int tabIndex: 5

  // Time dropdown options (00:00 .. 23:30)
  ListModel {
    id: timeOptions
  }
  Component.onCompleted: {
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        var hh = ("0" + h).slice(-2)
        var mm = ("0" + m).slice(-2)
        var key = hh + ":" + mm
        timeOptions.append({
                             "key": key,
                             "name": key
                           })
      }
    }
  }

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice()
    if (!arr.includes(name))
      arr.push(name)
    return arr
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name
    })
  }

  NText {
    text: "Monitor-specific configuration"
    font.pointSize: Style.fontSizeL * scaling
    font.weight: Style.fontWeightBold
  }

  NText {
    text: "Bars and notifications appear on all displays by default. Choose specific displays below to limit where they're shown."
    font.pointSize: Style.fontSizeM * scaling
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.preferredWidth: parent.width - (Style.marginL * 2 * scaling)
  }

  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.topMargin: Style.marginL * scaling

    Repeater {
      model: Quickshell.screens || []
      delegate: Rectangle {
        Layout.fillWidth: true
        Layout.minimumWidth: 550 * scaling
        radius: Style.radiusM * scaling
        color: Color.mSurface
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        implicitHeight: contentCol.implicitHeight + Style.marginXL * 2 * scaling

        ColumnLayout {
          id: contentCol
          anchors.fill: parent
          anchors.margins: Style.marginL * scaling
          spacing: Style.marginXXS * scaling

          NText {
            text: (modelData.name || "Unknown")
            font.pointSize: Style.fontSizeXL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mSecondary
          }

          NText {
            text: `Resolution: ${modelData.width}x${modelData.height} - Position: (${modelData.x}, ${modelData.y})`
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          ColumnLayout {
            spacing: Style.marginL * scaling
            Layout.fillWidth: true

            NToggle {
              Layout.fillWidth: true
              label: "Bar"
              description: "Enable the bar on this monitor."
              checked: (Settings.data.bar.monitors || []).indexOf(modelData.name) !== -1
              onToggled: checked => {
                           if (checked) {
                             Settings.data.bar.monitors = addMonitor(Settings.data.bar.monitors, modelData.name)
                           } else {
                             Settings.data.bar.monitors = removeMonitor(Settings.data.bar.monitors, modelData.name)
                           }
                         }
            }

            NToggle {
              Layout.fillWidth: true
              label: "Notifications"
              description: "Enable notifications on this monitor."
              checked: (Settings.data.notifications.monitors || []).indexOf(modelData.name) !== -1
              onToggled: checked => {
                           if (checked) {
                             Settings.data.notifications.monitors = addMonitor(Settings.data.notifications.monitors,
                                                                               modelData.name)
                           } else {
                             Settings.data.notifications.monitors = removeMonitor(Settings.data.notifications.monitors,
                                                                                  modelData.name)
                           }
                         }
            }

            NToggle {
              Layout.fillWidth: true
              label: "Dock"
              description: "Enable the dock on this monitor."
              checked: (Settings.data.dock.monitors || []).indexOf(modelData.name) !== -1
              onToggled: checked => {
                           if (checked) {
                             Settings.data.dock.monitors = addMonitor(Settings.data.dock.monitors, modelData.name)
                           } else {
                             Settings.data.dock.monitors = removeMonitor(Settings.data.dock.monitors, modelData.name)
                           }
                         }
            }

            ColumnLayout {
              spacing: Style.marginS * scaling
              Layout.fillWidth: true

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginL * scaling

                ColumnLayout {
                  spacing: Style.marginXXS * scaling
                  Layout.fillWidth: true

                  NText {
                    text: "Scale"
                    font.pointSize: Style.fontSizeM * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                  }
                  NText {
                    text: "Scale the user interface on this monitor."
                    font.pointSize: Style.fontSizeS * scaling
                    color: Color.mOnSurfaceVariant
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }

                NText {
                  text: `${Math.round(ScalingService.scaleByName(modelData.name) * 100)}%`
                  Layout.alignment: Qt.AlignVCenter
                  Layout.minimumWidth: 50 * scaling
                  horizontalAlignment: Text.AlignRight
                }
              }

              RowLayout {
                spacing: Style.marginS * scaling
                Layout.fillWidth: true

                NSlider {
                  id: scaleSlider
                  from: 0.7
                  to: 1.8
                  stepSize: 0.01
                  value: ScalingService.scaleByName(modelData.name)
                  onPressedChanged: {
                    var data = Settings.data.monitorsScaling || {}
                    data[modelData.name] = value
                    Settings.data.monitorsScaling = data
                  }
                  Layout.fillWidth: true
                  Layout.minimumWidth: 150 * scaling
                }

                NIconButton {
                  icon: "refresh"
                  tooltipText: "Reset Scaling"
                  onClicked: {
                    var data = Settings.data.monitorsScaling || {}
                    data[modelData.name] = 1.0
                    Settings.data.monitorsScaling = data
                  }
                }
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

    // Night Light Section
    ColumnLayout {
      spacing: Style.marginXS * scaling
      NText {
        text: "Night Light"
        font.pointSize: Style.fontSizeXXL * scaling
        font.weight: Style.fontWeightBold
        color: Color.mSecondary
      }

      NText {
        text: "Reduce blue light emission to help you sleep better and reduce eye strain."
        font.pointSize: Style.fontSizeM * scaling
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.preferredWidth: parent.width - (Style.marginL * 2 * scaling)
      }
    }

    NToggle {
      label: "Enable Night Light"
      description: "Apply a warm color filter to reduce blue light emission."
      checked: Settings.data.nightLight.enabled
      onToggled: checked => Settings.data.nightLight.enabled = checked
    }

    NToggle {
      label: "Auto Schedule"
      description: "Automatically enable night light based on time schedule."
      checked: Settings.data.nightLight.autoSchedule
      onToggled: checked => Settings.data.nightLight.autoSchedule = checked
    }

    // Intensity settings
    ColumnLayout {
      NLabel {
        label: "Intensity"
        description: "Higher values create warmer light."
      }
      RowLayout {
        spacing: Style.marginS * scaling

        NSlider {
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.nightLight.intensity
          onMoved: Settings.data.nightLight.intensity = value
          Layout.fillWidth: true
          Layout.minimumWidth: 150 * scaling
        }

        NText {
          text: `${Math.round(Settings.data.nightLight.intensity * 100)}%`
          Layout.alignment: Qt.AlignVCenter
          Layout.minimumWidth: 60 * scaling
          horizontalAlignment: Text.AlignRight
        }
      }
    }

    // Schedule settings
    ColumnLayout {
      spacing: Style.marginXS * scaling

      NLabel {
        label: "Schedule"
        description: "Set a start and end time for automatic schedule."
      }

      RowLayout {
        Layout.fillWidth: false
        spacing: Style.marginM * scaling

        NText {
          text: "Start Time"
          font.pointSize: Style.fontSizeM * scaling
          color: Color.mOnSurfaceVariant
        }

        NComboBox {
          model: timeOptions
          currentKey: Settings.data.nightLight.startTime
          placeholder: "Select start time"
          onSelected: key => Settings.data.nightLight.startTime = key
          preferredWidth: 120 * scaling
        }

        Item {// add a little more spacing
        }

        NText {
          text: "Stop Time"
          font.pointSize: Style.fontSizeM * scaling
          color: Color.mOnSurfaceVariant
        }
        NComboBox {
          model: timeOptions
          currentKey: Settings.data.nightLight.stopTime
          placeholder: "Select stop time"
          onSelected: key => Settings.data.nightLight.stopTime = key
          preferredWidth: 120 * scaling
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
