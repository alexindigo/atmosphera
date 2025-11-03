import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

// Dummy comment to force re-evaluation
Item {
  id: root

  // Widget properties
  property string widgetId: "CustomButton"
  property var widgetSettings

  // Use settings or provide defaults
  property string onClickedCommand: ""
  property string onRightClickedCommand: ""
  property string onMiddleClickedCommand: ""
  property string initialIcon: "heart"
  property string onStateIcon: "heart"
  property string onStateCommand: ""
  property string generalTooltipText: "Custom Button"
  property bool enableOnStateLogic: false

  // Internal state
  property string _currentIcon: initialIcon
  property bool _isHot: false

  Connections {
    target: root
    function _updatePropertiesFromSettings() {
      onClickedCommand = widgetSettings.onClicked || ""
      onRightClickedCommand = widgetSettings.onRightClicked || ""
      onMiddleClickedCommand = widgetSettings.onMiddleClicked || ""
      initialIcon = (widgetSettings.icon && widgetSettings.icon !== "") ? widgetSettings.icon : "heart"
      onStateIcon = (widgetSettings.onStateIcon && widgetSettings.onStateIcon !== "") ? widgetSettings.onStateIcon : "heart"
      onStateCommand = widgetSettings.onStateCommand || ""
      generalTooltipText = widgetSettings.generalTooltipText || "Custom Button"
      enableOnStateLogic = widgetSettings.enableOnStateLogic || false

      updateState()
    }
    function onWidgetSettingsChanged() { _updatePropertiesFromSettings() }
  }

  Process {
    id: onStateCheckProcess
    running: false
    command: ["sh", "-c", onStateCommand]
    onExited: function(exitCode, stdout, stderr) {
      if (exitCode === 0) {
        _isHot = true
        _currentIcon = onStateIcon || initialIcon
      } else {
        _isHot = false
        _currentIcon = initialIcon
      }

    }
  }

  function updateState() {
    if (enableOnStateLogic && onStateCommand) {
      onStateCheckProcess.running = true // Start the process
    } else {
      _isHot = false
      _currentIcon = initialIcon
    }
  }

  function _buildTooltipText() {
    let tooltip = generalTooltipText
    if (onClickedCommand) {
      tooltip += `\nLeft click: ${onClickedCommand}`
    }
    if (onRightClickedCommand) {
      tooltip += `\nRight click: ${onRightClickedCommand}`
    }
    if (onMiddleClickedCommand) {
      tooltip += `\nMiddle click: ${onMiddleClickedCommand}`
    }

    return tooltip
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  NIconButtonHot {
    id: button
    icon: _currentIcon
    hot: _isHot
    tooltipText: _buildTooltipText()
    onClicked: {
      if (onClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onClickedCommand])
        updateState()
      }
    }
    onRightClicked: {
      if (onRightClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onRightClickedCommand])
        updateState()
      }
    }
    onMiddleClicked: {
      if (onMiddleClickedCommand) {
        Quickshell.execDetached(["sh", "-c", onMiddleClickedCommand])
        updateState()
      }
    }
  }
}
