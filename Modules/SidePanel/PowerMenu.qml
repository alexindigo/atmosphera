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
import qs.Modules.LockScreen

PanelWindow {
  id: root
  readonly property real scaling: ScalingService.scale(screen)

  
  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "#3300FF00"
  screen: screen

  onVisibleChanged: {
    if (visible) {
      console.log("Oh Yeah")
      // Focus the menu rectangle instead of root
      menuRect.forceActiveFocus()
    }
  }

  function open() {
    visible = true
  }

  function close() {
    visible = false
  }

  // // Clicking outside of the rectangle to close
  // MouseArea {
  //   anchors.fill: parent
  //   onClicked: root.close()
  //   // Prevent this MouseArea from interfering with child elements
  //   propagateComposedEvents: true
  //   z: -1  // Put it behind the menu
  // }

  // ----------------------------------
  // System functions
  function logout() {
    CompositorService.logout()
  }

  function suspend() {
    suspendProcess.running = true
  }

  function shutdown() {
    shutdownProcess.running = true
  }

  function reboot() {
    rebootProcess.running = true
  }

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

  Process {
    id: logoutProcess
    command: ["loginctl", "terminate-user", Quickshell.env("USER")]
    running: false
  }

  property var entriesCount: 5
  property var entryHeight: Style.baseWidgetSize * scaling

  Rectangle {
    id: menuRect
    width: 160 * scaling
    height: (entryHeight * entriesCount) + (Style.marginS * entriesCount * scaling)
    radius: Style.radiusM * scaling
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS * scaling)
    color: Color.mSurface
    visible: true
    z: 9999
    
    // Add focus properties
    focus: true
    activeFocusOnTab: true

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.rightMargin: Style.marginL * scaling
    anchors.topMargin: 86 * scaling

    Component.onCompleted: {
      console.log("oncompleted")
      forceActiveFocus()
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginS * scaling
      spacing: Style.marginXS * scaling

      // --------------
      // Lock
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: entryHeight
        radius: Style.radiusS * scaling
        color: lockButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginM * scaling
          anchors.rightMargin: Style.marginM * scaling

          Row {
            id: lockRow
            spacing: Style.marginS * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "lock_outline"
              color: lockButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            NText {
              text: "Lock Screen"
              color: lockButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              font.pointSize: Style.fontSizeS * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: lockButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Add acceptedButtons to ensure proper click handling
          acceptedButtons: Qt.LeftButton
          
          onClicked: {
            Logger.log("PowerMenu", "Lock screen requested")
            // // Lock the screen
            // lockScreen.isLoaded = true
            root.close()
          }
        }
      }

      // --------------
      // Suspend
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: entryHeight
        radius: Style.radiusS * scaling
        color: suspendButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginM * scaling
          anchors.rightMargin: Style.marginM * scaling

          Row {
            id: suspendRow
            spacing: Style.marginS * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "bedtime"
              color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            NText {
              text: "Suspend"
              color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              font.pointSize: Style.fontSizeS * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: suspendButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          
          onClicked: {
            suspend()
            root.close()
          }
        }
      }

      // --------------
      // Reboot
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: entryHeight
        radius: Style.radiusS * scaling
        color: rebootButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginM * scaling
          anchors.rightMargin: Style.marginM * scaling

          Row {
            id: rebootRow
            spacing: Style.marginS * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "refresh"
              color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            NText {
              text: "Reboot"
              color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              font.pointSize: Style.fontSizeS * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: rebootButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          
          onClicked: {
            reboot()
            root.close()
          }
        }
      }

      // --------------
      // Logout
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: entryHeight
        radius: Style.radiusS * scaling
        color: logoutButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginM * scaling
          anchors.rightMargin: Style.marginM * scaling

          Row {
            id: logoutRow
            spacing: Style.marginS * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "exit_to_app"
              color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            NText {
              text: "Logout"
              color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              font.pointSize: Style.fontSizeS * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: logoutButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          
          onClicked: {
            logout()
            root.close()
          }
        }
      }

      // --------------
      // Shutdown
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: entryHeight
        radius: Style.radiusS * scaling
        color: shutdownButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginM * scaling
          anchors.rightMargin: Style.marginM * scaling

          Row {
            id: shutdownRow
            spacing: Style.marginS * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "power_settings_new"
              color: shutdownButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            NText {
              text: "Shutdown"
              color: shutdownButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              font.pointSize: Style.fontSizeS * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: shutdownButtonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          
          onClicked: {
            shutdown()
            root.close()
          }
        }
      }
    }
  }
}