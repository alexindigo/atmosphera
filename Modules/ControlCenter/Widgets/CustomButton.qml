import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets


Item {
  id: root


  property string widgetId: "CustomButton"
  property var widgetSettings: null


  property string onClickedCommand: ""
  property string onRightClickedCommand: ""
  property string onMiddleClickedCommand: ""
  property string initialIcon: "heart"
  property string onStateIcon: "heart"
  property string onStateCommand: ""
  property string generalTooltipText: "Custom Button"
  property bool enableOnStateLogic: false


  property string _currentIcon: initialIcon
  property bool _isHot: false

  Connections {
    target: root
    function _updatePropertiesFromSettings() {

      if (!widgetSettings) {
        return
      }

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


    function onWidgetSettingsChanged() {
      if (widgetSettings) {
        _updatePropertiesFromSettings()
      }
    }
  }

  Process {
    id: onStateCheckProcess

    running: false
    command: ["sh", "-c", onStateCommand]
    onExited: function(exitCode, stdout, stderr) {
      if (enableOnStateLogic && onStateCommand) {
        if (exitCode === 0) {
          _isHot = true
          _currentIcon = onStateIcon
        } else {
          _isHot = false
          _currentIcon = initialIcon
        }
      } else {
        _isHot = false
        _currentIcon = initialIcon
      }
    }
  }

  Timer {
    id: stateUpdateTimer
    interval: 200
    running: false
    repeat: false
    onTriggered: {
      if (enableOnStateLogic && onStateCommand && !onStateCheckProcess.running) {
        onStateCheckProcess.running = true
      }
    }
  }

  function updateState() {
    if (!enableOnStateLogic || !onStateCommand) {
      _isHot = false;
      _currentIcon = initialIcon;
      return;
    }
    stateUpdateTimer.restart();
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
