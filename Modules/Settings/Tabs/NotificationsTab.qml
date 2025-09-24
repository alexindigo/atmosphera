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
      label: "Do not disturb"
      description: "Disable all notification popups when enabled."
      checked: Settings.data.notifications.doNotDisturb
      onToggled: checked => Settings.data.notifications.doNotDisturb = checked
    }

    NToggle {
      label: "Enable on screen display"
      description: "Show volume and brightness changes in real-time."
      checked: Settings.data.notifications.enableOSD
      onToggled: checked => Settings.data.notifications.enableOSD = checked
    }

    NComboBox {
      label: "Location"
      description: "Where notifications appear on screen."
      model: ListModel {
        ListElement {
          key: "top"
          name: "Top"
        }
        ListElement {
          key: "top_left"
          name: "Top left"
        }
        ListElement {
          key: "top_right"
          name: "Top right"
        }
        ListElement {
          key: "bottom"
          name: "Bottom"
        }
        ListElement {
          key: "bottom_left"
          name: "Bottom left"
        }
        ListElement {
          key: "bottom_right"
          name: "Bottom right"
        }
      }
      currentKey: Settings.data.notifications.location || "top_right"
      onSelected: key => Settings.data.notifications.location = key
    }

    NToggle {
      label: "Always on top"
      description: "Display notifications above fullscreen windows and other layers."
      checked: Settings.data.notifications.alwaysOnTop
      onToggled: checked => Settings.data.notifications.alwaysOnTop = checked
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
      label: "Notification duration"
      description: "Configure how long notifications stay visible based on their urgency level."
    }

    // Respect Expire Timeout (eg. --expire-time flag in notify-send)
    NToggle {
      label: "Respect expire timeout"
      description: "Use the expire timeout set in the notification."
      checked: Settings.data.notifications.respectExpireTimeout
      onToggled: checked => Settings.data.notifications.respectExpireTimeout = checked
    }

    // Low Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Low urgency"
        description: "How long low priority notifications stay visible."
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.lowUrgencyDuration
        onMoved: value => Settings.data.notifications.lowUrgencyDuration = value
        text: Settings.data.notifications.lowUrgencyDuration + "s"
      }
    }

    // Normal Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Normal urgency"
        description: "How long normal priority notifications stay visible."
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.normalUrgencyDuration
        onMoved: value => Settings.data.notifications.normalUrgencyDuration = value
        text: Settings.data.notifications.normalUrgencyDuration + "s"
      }
    }

    // Critical Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: "Critical urgency"
        description: "How long critical priority notifications stay visible."
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.criticalUrgencyDuration
        onMoved: value => Settings.data.notifications.criticalUrgencyDuration = value
        text: Settings.data.notifications.criticalUrgencyDuration + "s"
      }
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
      label: "Monitors display"
      description: "Show notification on specific monitors. Defaults to all if none are chosen."
    }

    Repeater {
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: modelData.name || "Unknown"
        description: `${modelData.model} (${modelData.width}x${modelData.height})`
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
}
