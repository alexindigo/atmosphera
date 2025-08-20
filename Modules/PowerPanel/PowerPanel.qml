import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: 420 * scaling
  panelHeight: 370 * scaling
  panelAnchorCentered: true

  // Timer properties
  property int timerDuration: 5000 // 5 seconds
  property string pendingAction: ""
  property bool timerActive: false
  property int timeRemaining: 0

  // Cancel timer when panel is closing
  onClosed: {
    cancelTimer()
  }

  // Timer management
  function startTimer(action) {
    if (timerActive && pendingAction === action) {
      // Second click - execute immediately
      executeAction(action)
      return
    }
    
    pendingAction = action
    timeRemaining = timerDuration
    timerActive = true
    countdownTimer.start()
  }

  function cancelTimer() {
    timerActive = false
    pendingAction = ""
    timeRemaining = 0
    countdownTimer.stop()
  }

  function executeAction(action) {
    // Stop timer but don't reset other properties yet
    countdownTimer.stop()
    
    switch(action) {
      case "lock":
        // Access lockScreen directly like IPCManager does
        if (!lockScreen.isLoaded) {
          lockScreen.isLoaded = true
        }
        break
      case "suspend":
        suspendProcess.running = true
        break
      case "reboot":
        rebootProcess.running = true
        break
      case "logout":
        CompositorService.logout()
        break
      case "shutdown":
        shutdownProcess.running = true
        break
    }
    
    // Reset timer state and close panel
    cancelTimer()
    root.close()
  }

  // System processes
  Process {
    id: shutdownProcess
    command: ["shutdown", "-h", "now"]
    running: false
  }

  Process {
    id: rebootProcess
    command: ["reboot"]
    running: false
  }

  Process {
    id: suspendProcess
    command: ["systemctl", "suspend"]
    running: false
  }

  // Countdown timer
  Timer {
    id: countdownTimer
    interval: 100
    repeat: true
    onTriggered: {
      timeRemaining -= interval
      if (timeRemaining <= 0) {
        executeAction(pendingAction)
      }
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.topMargin: Style.marginL * scaling
      anchors.leftMargin: Style.marginL * scaling
      anchors.rightMargin: Style.marginL * scaling
      anchors.bottomMargin: Style.marginM * scaling
      spacing: Style.marginS * scaling

      // Header with title and close button
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.baseWidgetSize * 0.8 * scaling

        NText {
          text: timerActive ? `${pendingAction.charAt(0).toUpperCase() + pendingAction.slice(1)} in ${Math.ceil(timeRemaining / 1000)}s` : "Power Options"
          font.weight: Style.fontWeightBold
          font.pointSize: Style.fontSizeM * scaling
          color: timerActive ? Color.mPrimary : Color.mOnSurface
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        NIconButton {
          icon: timerActive ? "block" : "close"
          tooltipText: timerActive ? "Cancel Timer" : "Close"
          Layout.alignment: Qt.AlignVCenter
          colorBg: timerActive ? Color.applyOpacity(Color.mError, "20") : Color.transparent
          colorFg: timerActive ? Color.mError : Color.mOnSurface
          onClicked: {
            if (timerActive) {
              cancelTimer()
            } else {
              cancelTimer()
              root.close()
            }
          }
        }
      }



      // Power options
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        // Lock Screen
        PowerButton {
          Layout.fillWidth: true
          icon: "lock_outline"
          title: "Lock Screen"
          subtitle: "Lock your session"
          onClicked: startTimer("lock")
          pending: timerActive && pendingAction === "lock"
        }

        // Suspend
        PowerButton {
          Layout.fillWidth: true
          icon: "bedtime"
          title: "Suspend"
          subtitle: "Put the system to sleep"
          onClicked: startTimer("suspend")
          pending: timerActive && pendingAction === "suspend"
        }

        // Reboot
        PowerButton {
          Layout.fillWidth: true
          icon: "refresh"
          title: "Reboot"
          subtitle: "Restart the system"
          onClicked: startTimer("reboot")
          pending: timerActive && pendingAction === "reboot"
        }

        // Logout
        PowerButton {
          Layout.fillWidth: true
          icon: "exit_to_app"
          title: "Logout"
          subtitle: "End your session"
          onClicked: startTimer("logout")
          pending: timerActive && pendingAction === "logout"
        }

        // Shutdown
        PowerButton {
          Layout.fillWidth: true
          icon: "power_settings_new"
          title: "Shutdown"
          subtitle: "Turn off the system"
          onClicked: startTimer("shutdown")
          pending: timerActive && pendingAction === "shutdown"
          isShutdown: true
        }
      }


    }
  }

  // Custom power button component
  component PowerButton: Rectangle {
    id: buttonRoot
    
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool pending: false
    property bool isShutdown: false
    
    signal clicked()

    height: Style.baseWidgetSize * 1.5 * scaling
    radius: Style.radiusS * scaling
    color: {
      if (pending) return Color.applyOpacity(Color.mPrimary, "20")
      if (mouseArea.containsMouse) return Color.mSurfaceVariant
      return Color.transparent
    }
    
    border.width: pending ? 2 * scaling : (mouseArea.containsMouse ? 1 * scaling : 0)
    border.color: pending ? Color.mPrimary : Color.mOutline

    Behavior on color {
      ColorAnimation { duration: 150 }
    }

    Item {
      anchors.fill: parent
      anchors.margins: Style.marginM * scaling

      // Icon on the left
      NIcon {
        id: iconElement
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: buttonRoot.icon
        color: {
          if (buttonRoot.pending) return Color.mPrimary
          if (buttonRoot.isShutdown && mouseArea.containsMouse) return Color.mError
          if (mouseArea.containsMouse) return Color.mPrimary
          return Color.mOnSurface
        }
        font.pointSize: Style.fontSizeL * scaling
        width: Style.baseWidgetSize * 0.6 * scaling
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        
        Behavior on color {
          ColorAnimation { duration: 150 }
        }
      }

      // Text content in the middle
      Column {
        anchors.left: iconElement.right
        anchors.right: pendingIndicator.visible ? pendingIndicator.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.marginM * scaling
        anchors.rightMargin: pendingIndicator.visible ? Style.marginM * scaling : 0
        spacing: 2 * scaling

        NText {
          text: buttonRoot.title
          font.weight: Style.fontWeightMedium
          font.pointSize: Style.fontSizeS * scaling
          color: {
            if (buttonRoot.pending) return Color.mPrimary
            if (buttonRoot.isShutdown && mouseArea.containsMouse) return Color.mError
            if (mouseArea.containsMouse) return Color.mPrimary
            return Color.mOnSurface
          }
          
          Behavior on color {
            ColorAnimation { duration: 150 }
          }
        }

        NText {
          text: {
            if (buttonRoot.pending) {
              return "Click again to execute immediately"
            }
            return buttonRoot.subtitle
          }
          font.pointSize: Style.fontSizeXS * scaling
          color: {
            if (buttonRoot.pending) return Color.mPrimary
            return Color.mOnSurfaceVariant
          }
          opacity: 0.8
          wrapMode: Text.WordWrap
        }
      }

      // Pending indicator on the right
      Rectangle {
        id: pendingIndicator
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 24 * scaling
        height: 24 * scaling
        radius: 12 * scaling
        color: Color.mPrimary
        visible: buttonRoot.pending
        
        NText {
          anchors.centerIn: parent
          text: Math.ceil(timeRemaining / 1000)
          font.pointSize: Style.fontSizeXS * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnPrimary
        }
      }
    }



    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      
      onClicked: buttonRoot.clicked()
    }
  }
}