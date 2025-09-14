import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: contentColumn
  spacing: Style.marginL * scaling
  width: root.width

  NHeader {
    label: "Dock Settings"
    description: "Configure dock behavior, appearance, and monitor settings."
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

  NToggle {
    label: "Auto-hide"
    description: "Automatically hide when not in use."
    checked: Settings.data.dock.autoHide
    onToggled: checked => Settings.data.dock.autoHide = checked
  }

  NToggle {
    label: "Exclusive Zone"
    description: "Ensure windows don't open underneath."
    checked: Settings.data.dock.exclusive
    onToggled: checked => Settings.data.dock.exclusive = checked
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Monitor Configuration
  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Monitor Configuration"
      description: "Choose which monitors should display the dock."
    }

    Repeater {
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: `${modelData.name || "Unknown"}${modelData.model ? `: ${modelData.model}` : ""}`
        description: `${modelData.width}x${modelData.height} at (${modelData.x}, ${modelData.y})`
        checked: (Settings.data.dock.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.dock.monitors = addMonitor(Settings.data.dock.monitors, modelData.name)
                     } else {
                       Settings.data.dock.monitors = removeMonitor(Settings.data.dock.monitors, modelData.name)
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

  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Background Opacity"
      description: "Adjust the background opacity."
    }

    RowLayout {
      NSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        stepSize: 0.01
        value: Settings.data.dock.backgroundOpacity
        onMoved: Settings.data.dock.backgroundOpacity = value
        cutoutColor: Color.mSurface
      }

      NText {
        text: Math.floor(Settings.data.dock.backgroundOpacity * 100) + "%"
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginS * scaling
        color: Color.mOnSurface
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Dock Floating Distance"
      description: "Adjust the floating distance from the screen edge."
    }

    RowLayout {
      NSlider {
        Layout.fillWidth: true
        from: 0
        to: 4
        stepSize: 0.01
        value: Settings.data.dock.floatingRatio
        onMoved: Settings.data.dock.floatingRatio = value
        cutoutColor: Color.mSurface
      }

      NText {
        text: Math.floor(Settings.data.dock.floatingRatio * 100) + "%"
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginS * scaling
        color: Color.mOnSurface
      }
    }
  }
}
