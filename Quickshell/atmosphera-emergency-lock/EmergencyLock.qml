import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Services.Locker

// Deliberately independent of Commons, settings, icons, media and plugins.
// Every output has an opaque surface and an ordinary PAM password entry.
Scope {
  id: root

  LockAuth {
    id: lockAuth
    username: Quickshell.env("USER")
    enabled: lock.secure && !client.terminal
    onFailed: passwordText = ""
  }

  LockClient {
    id: client
    endpoint: lock
    auth: lockAuth
    prepared: lockAuth.pamReady
  }

  WlSessionLock {
    id: lock
    WlSessionLockSurface {
      color: "black"

      Rectangle {
        anchors.fill: parent
        color: "black"
        ColumnLayout {
          anchors.centerIn: parent
          width: Math.min(360, parent.width - 48)
          spacing: 16

          Text {
            Layout.fillWidth: true
            text: "Screen locked"
            color: "white"
            font.pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            color: "#181818"
            border.color: input.activeFocus ? "white" : "#808080"
            radius: 4

            TextInput {
              id: input
              anchors.fill: parent
              anchors.margins: 12
              color: "white"
              font.pixelSize: 18
              echoMode: TextInput.Password
              passwordMaskDelay: 0
              clip: true
              readOnly: lockAuth.unlockInProgress
              selectByMouse: true
              activeFocusOnPress: true
              onTextChanged: if (lockAuth.passwordText !== text)
                               lockAuth.passwordText = text
              onAccepted: lockAuth.tryUnlock()
              Component.onCompleted: forceActiveFocus()

              Text {
                anchors.fill: parent
                visible: input.text === ""
                text: "Password"
                font: input.font
                color: "#b0b0b0"
                elide: Text.ElideRight
              }

              Connections {
                target: lockAuth
                function onPasswordTextChanged() {
                  if (input.text !== lockAuth.passwordText)
                    input.text = lockAuth.passwordText;
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: lockAuth.showFailure ? lockAuth.errorMessage : lockAuth.infoMessage
            color: lockAuth.showFailure ? "#ffaaaa" : "white"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
