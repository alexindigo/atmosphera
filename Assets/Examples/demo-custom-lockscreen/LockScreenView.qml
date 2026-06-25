import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  // `screen` must be transferred to AtmoWallpaperBackground for the shell
  // to resolve the current wallpaper or apply the background-color fallback.
  required property var lockContext
  property var pluginApi: null
  property var screen
  property bool compactMode: false
  property bool animationsEnabled: true

  AtmoWallpaperBackground {
    screen: root.screen
  }

  Rectangle {
    anchors.fill: parent
    color: "#80000000"
  }

  ColumnLayout {
    anchors.centerIn: parent
    spacing: Style.marginL

    Text {
      text: pluginApi?.pluginSettings?.greeting ?? "Custom Lock Screen"
      color: "white"
      font.pointSize: Style.fontSizeXXXL
      Layout.alignment: Qt.AlignHCenter
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginM

      TextField {
        id: passInput
        placeholderText: "Enter password..."
        echoMode: TextInput.Password
        passwordMaskDelay: 0
        color: "white"
        placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
        background: Rectangle {
          color: Qt.rgba(0, 0, 0, 0.3)
          radius: 6
        }
        onAccepted: unlockBtn.clicked()
      }

      NButton {
        id: unlockBtn
        text: "Unlock"
        icon: "check"
        onClicked: {
          lockContext.passwordText = passInput.text;
          lockContext.tryUnlock();
        }
      }
    }
  }
}
