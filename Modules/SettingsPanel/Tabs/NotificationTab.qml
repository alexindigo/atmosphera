import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

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

  // General Notification Settings
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Appearance"
      description: "Configure notifications appearance and behavior."
    }

    NToggle {
      label: "Do Not Disturb"
      description: "Disable all notification popups when enabled."
      checked: Settings.data.notifications.doNotDisturb
      onToggled: checked => Settings.data.notifications.doNotDisturb = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Monitor Configuration
  ColumnLayout {
    spacing: Style.marginM * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Monitors Configuration"
      description: "Choose which monitors should display notifications."
    }

    Repeater {
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: `${modelData.name || "Unknown"}${modelData.model ? `: ${modelData.model}` : ""}`
        description: `${modelData.width}x${modelData.height} at (${modelData.x}, ${modelData.y})`
        checked: (Settings.data.notifications.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.notifications.monitors = addMonitor(Settings.data.notifications.monitors, modelData.name)
                     } else {
                       Settings.data.notifications.monitors = removeMonitor(Settings.data.notifications.monitors, modelData.name)
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

  // Notification Duration Settings
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Notification Duration"
      description: "Configure how long notifications stay visible based on their urgency level."
    }

    // Low Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Low Urgency Duration"
        description: "How long low priority notifications stay visible."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 1
          to: 30
          stepSize: 1
          value: Settings.data.notifications.lowUrgencyDuration
          onMoved: Settings.data.notifications.lowUrgencyDuration = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Settings.data.notifications.lowUrgencyDuration + "s"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
        }
      }
    }

    // Normal Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Normal Urgency Duration"
        description: "How long normal priority notifications stay visible."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 1
          to: 30
          stepSize: 1
          value: Settings.data.notifications.normalUrgencyDuration
          onMoved: Settings.data.notifications.normalUrgencyDuration = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Settings.data.notifications.normalUrgencyDuration + "s"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
        }
      }
    }

    // Critical Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Critical Urgency Duration"
        description: "How long critical priority notifications stay visible."
      }

      RowLayout {
        NSlider {
          Layout.fillWidth: true
          from: 1
          to: 30
          stepSize: 1
          value: Settings.data.notifications.criticalUrgencyDuration
          onMoved: Settings.data.notifications.criticalUrgencyDuration = value
          cutoutColor: Color.mSurface
        }

        NText {
          text: Settings.data.notifications.criticalUrgencyDuration + "s"
          Layout.alignment: Qt.AlignVCenter
          Layout.leftMargin: Style.marginS * scaling
          color: Color.mOnSurface
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
