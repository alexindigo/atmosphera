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
      label: I18n.tr("settings.notifications.settings.section.label")
      description: I18n.tr("settings.notifications.settings.section.description")
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.do-not-disturb.label")
      description: I18n.tr("settings.notifications.settings.do-not-disturb.description")
      checked: Settings.data.notifications.doNotDisturb
      onToggled: checked => Settings.data.notifications.doNotDisturb = checked
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.enable-osd.label")
      description: I18n.tr("settings.notifications.settings.enable-osd.description")
      checked: Settings.data.notifications.enableOSD
      onToggled: checked => Settings.data.notifications.enableOSD = checked
    }

    NComboBox {
      label: I18n.tr("settings.notifications.settings.location.label")
      description: I18n.tr("settings.notifications.settings.location.description")
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
    // Low Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS * scaling
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.notifications.settings.low-urgency.label")
        description: I18n.tr("settings.notifications.settings.low-urgency.description")
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
        label: I18n.tr("settings.notifications.settings.normal-urgency.label")
        description: I18n.tr("settings.notifications.settings.normal-urgency.description")
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
        label: I18n.tr("settings.notifications.settings.critical-urgency.label")
        description: I18n.tr("settings.notifications.settings.critical-urgency.description")
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
    // Monitor Configuration
    NLabel {
      label: I18n.tr("settings.notifications.settings.monitors-display.label")
      description: I18n.tr("settings.notifications.settings.monitors-display.description")
    }

    Repeater {
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: modelData.name || "Unknown"
        description: I18n.tr("system.monitor-description", {
                               "model": modelData.model,
                               "width": modelData.width,
                               "height": modelData.height
                             })
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
