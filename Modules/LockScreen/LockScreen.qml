import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Audio

Loader {
  id: lockScreen
  active: false

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: lockScreen.active = false
  }

  function formatTime() {
    return Settings.data.location.use12hourFormat ? Qt.locale().toString(new Date(), "h:mm A") : Qt.locale().toString(new Date(), "HH:mm")
  }

  function formatDate() {
    return Qt.locale().toString(new Date(), "dddd, MMMM d")
  }

  function scheduleUnloadAfterUnlock() {
    unloadAfterUnlockTimer.start()
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      LockContext {
        id: lockContext
        onUnlocked: {
          lockSession.locked = false
          lockScreen.scheduleUnloadAfterUnlock()
          lockContext.currentText = ""
        }
      }

      WlSessionLock {
        id: lockSession
        locked: lockScreen.active

        WlSessionLockSurface {
          readonly property real scaling: ScalingService.dynamicScale(screen)

          Item {
            id: batteryIndicator
            property var battery: UPower.displayDevice
            property bool isReady: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
            property real percent: isReady ? (battery.percentage * 100) : 0
            property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
            property bool batteryVisible: isReady && percent > 0
          }

          Item {
            id: keyboardLayout
            property string currentLayout: (typeof KeyboardLayoutService !== 'undefined' && KeyboardLayoutService.currentLayout) ? KeyboardLayoutService.currentLayout : "Unknown"
          }

          Image {
            id: lockBgImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: screen ? WallpaperService.getWallpaper(screen.name) : ""
            cache: true
            smooth: true
            mipmap: false
          }

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.rgba(0, 0, 0, 0.6)
              }
              GradientStop {
                position: 0.3
                color: Qt.rgba(0, 0, 0, 0.3)
              }
              GradientStop {
                position: 0.7
                color: Qt.rgba(0, 0, 0, 0.4)
              }
              GradientStop {
                position: 1.0
                color: Qt.rgba(0, 0, 0, 0.7)
              }
            }
          }

          Item {
            anchors.fill: parent

            // Time and Date
            ColumnLayout {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 80 * scaling
              spacing: 8 * scaling

              NText {
                id: timeText
                text: lockScreen.formatTime()
                Layout.alignment: Qt.AlignHCenter
                pointSize: 64 * scaling
                font.weight: Font.Medium
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.95

                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation {
                    to: 0.7
                    duration: 3000
                    easing.type: Easing.InOutQuad
                  }
                  NumberAnimation {
                    to: 0.95
                    duration: 3000
                    easing.type: Easing.InOutQuad
                  }
                }
              }

              NText {
                id: dateText
                text: lockScreen.formatDate()
                Layout.alignment: Qt.AlignHCenter
                pointSize: Style.fontSizeL * scaling
                font.weight: Font.Medium
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.9
              }
            }

            // User Profile
            ColumnLayout {
              anchors.centerIn: parent
              spacing: 6 * scaling
              Layout.alignment: Qt.AlignHCenter

              Rectangle {
                Layout.preferredWidth: 130 * scaling
                Layout.preferredHeight: 130 * scaling
                Layout.alignment: Qt.AlignHCenter
                radius: width * 0.5
                color: Color.transparent

                Rectangle {
                  anchors.fill: parent
                  radius: parent.radius
                  color: Color.transparent
                  border.color: Qt.alpha(Color.mPrimary, 0.8)
                  border.width: 3

                  SequentialAnimation on border.color {
                    loops: Animation.Infinite
                    ColorAnimation {
                      to: Qt.alpha(Color.mPrimary, 1.0)
                      duration: 2000
                      easing.type: Easing.InOutQuad
                    }
                    ColorAnimation {
                      to: Qt.alpha(Color.mPrimary, 0.8)
                      duration: 2000
                      easing.type: Easing.InOutQuad
                    }
                  }
                }

                NImageCircled {
                  anchors.centerIn: parent
                  width: 120 * scaling
                  height: 120 * scaling
                  imagePath: Settings.data.general.avatarImage
                  fallbackIcon: "person"

                  SequentialAnimation on scale {
                    loops: Animation.Infinite
                    NumberAnimation {
                      to: 1.02
                      duration: 4000
                      easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                      to: 1.0
                      duration: 4000
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }

              NText {
                text: I18n.tr("lock-screen.welcome-back")
                Layout.alignment: Qt.AlignHCenter
                pointSize: Style.fontSizeL * scaling
                font.weight: Font.Medium
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.9
              }

              NText {
                text: Quickshell.env("USER")
                Layout.alignment: Qt.AlignHCenter
                pointSize: Style.fontSizeXXXL * scaling
                font.weight: Font.Medium
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.9
              }
            }

            // Bottom container with weather, password input and controls
            Rectangle {
              width: 700 * scaling
              height: 200 * scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 80 * scaling
              radius: 30 * scaling
              color: Qt.alpha(Color.mSurfaceContainerHighest, 0.9)
              border.color: Qt.alpha(Color.mOutline, 0.2)
              border.width: 1

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12 * scaling
                spacing: 12 * scaling

                // Weather section
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 60 * scaling
                  spacing: 16 * scaling
                  visible: LocationService.coordinatesReady && LocationService.data.weather !== null

                  // Media widget with visualizer
                  Rectangle {
                    Layout.preferredWidth: 220 * scaling
                    Layout.preferredHeight: 50 * scaling
                    radius: 25 * scaling
                    color: Color.transparent
                    clip: true
                    visible: MediaService.currentPlayer && MediaService.canPlay

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4 * scaling
                      active: Settings.data.audio.visualizerType === "linear"
                      z: 0
                      sourceComponent: LinearSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4 * scaling
                      active: Settings.data.audio.visualizerType === "mirrored"
                      z: 0
                      sourceComponent: MirroredSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4 * scaling
                      active: Settings.data.audio.visualizerType === "wave"
                      z: 0
                      sourceComponent: WaveSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: 8 * scaling
                      spacing: 8 * scaling
                      z: 1

                      Rectangle {
                        Layout.preferredWidth: 34 * scaling
                        Layout.preferredHeight: 34 * scaling
                        radius: width * 0.5
                        color: Color.transparent
                        clip: true

                        NImageCircled {
                          anchors.fill: parent
                          anchors.margins: 2 * scaling
                          imagePath: MediaService.trackArtUrl
                          fallbackIcon: "disc"
                          fallbackIconSize: Style.fontSizeM * scaling
                          borderColor: Color.mOutline
                          borderWidth: Math.max(1, Style.borderS * scaling)
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2 * scaling

                        NText {
                          text: MediaService.trackTitle || "No media"
                          pointSize: Style.fontSizeS * scaling
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        NText {
                          text: MediaService.trackArtist || ""
                          pointSize: Style.fontSizeXS * scaling
                          color: Color.mOnSurfaceVariant
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }

                  Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.rightMargin: 4 * scaling
                    color: Qt.alpha(Color.mOutline, 0.3)
                    visible: MediaService.currentPlayer && MediaService.canPlay
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                    visible: !(MediaService.currentPlayer && MediaService.canPlay)
                  }

                  // Current weather
                  RowLayout {
                    Layout.preferredWidth: 180 * scaling
                    spacing: 8 * scaling

                    NIcon {
                      Layout.alignment: Qt.AlignVCenter
                      icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode)
                      pointSize: Style.fontSizeXXXL * scaling
                      color: Color.mPrimary
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2 * scaling

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 12 * scaling

                        NText {
                          text: Math.round(LocationService.data.weather.current_weather.temperature) + "°"
                          pointSize: Style.fontSizeXL * scaling
                          font.weight: Style.fontWeightBold
                          color: Color.mOnSurface
                        }

                        NText {
                          text: LocationService.data.weather.current_weather.windspeed + " km/h"
                          pointSize: Style.fontSizeXS * scaling
                          color: Color.mOnSurfaceVariant
                          font.weight: Font.Normal
                        }
                      }

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * scaling

                        NText {
                          text: Settings.data.location.name.split(",")[0]
                          pointSize: Style.fontSizeXS * scaling
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: (LocationService.data.weather.current && LocationService.data.weather.current.relativehumidity_2m) ? LocationService.data.weather.current.relativehumidity_2m + "% humidity" : ""
                          pointSize: Style.fontSizeXS * scaling
                          color: Color.mOnSurfaceVariant
                        }
                      }
                    }
                  }

                  // 3-day forecast
                  RowLayout {
                    Layout.preferredWidth: 260 * scaling
                    Layout.rightMargin: 8 * scaling
                    spacing: 4 * scaling

                    Repeater {
                      model: 3
                      delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3 * scaling

                        NText {
                          text: Qt.locale().toString(new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/")), "ddd")
                          pointSize: Style.fontSizeXS * scaling
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }

                        NIcon {
                          Layout.alignment: Qt.AlignHCenter
                          icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
                          pointSize: Style.fontSizeXL * scaling
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: Math.round(LocationService.data.weather.daily.temperature_2m_max[index]) + "°/" + Math.round(LocationService.data.weather.daily.temperature_2m_min[index]) + "°"
                          pointSize: Style.fontSizeXS * scaling
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurface
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }
                      }
                    }
                  }

                  // Battery and Keyboard Layout
                  ColumnLayout {
                    Layout.preferredWidth: 60 * scaling
                    spacing: 4 * scaling

                    RowLayout {
                      Layout.preferredWidth: 60 * scaling
                      Layout.preferredHeight: 22 * scaling
                      spacing: 4 * scaling
                      visible: UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent

                      NIcon {
                        icon: BatteryService.getIcon(Math.round(UPower.displayDevice.percentage * 100), UPower.displayDevice.state === UPowerDeviceState.Charging, true)
                        pointSize: Style.fontSizeS * scaling
                        color: UPower.displayDevice.state === UPowerDeviceState.Charging ? Color.mPrimary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS * scaling
                        font.weight: Font.Medium
                      }
                    }

                    RowLayout {
                      Layout.preferredWidth: 60 * scaling
                      Layout.preferredHeight: 22 * scaling
                      spacing: 4 * scaling

                      NIcon {
                        icon: "keyboard"
                        pointSize: Style.fontSizeS * scaling
                        color: Color.mOnSurfaceVariant
                      }

                      NText {
                        text: keyboardLayout.currentLayout
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS * scaling
                        font.weight: Font.Medium
                      }
                    }
                  }
                }

                // Password input
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44 * scaling
                    radius: 22 * scaling
                    color: Qt.alpha(Color.mSurfaceContainerHighest, 0.6)
                    border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
                    border.width: passwordInput.activeFocus ? 2 : 1

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 16 * scaling
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 12 * scaling

                      NIcon {
                        icon: "lock"
                        pointSize: Style.fontSizeM * scaling
                        color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      // Hidden input that receives actual text
                      TextInput {
                        id: passwordInput
                        width: 0
                        height: 0
                        visible: false
                        enabled: !lockContext.unlockInProgress
                        font.pointSize: Style.fontSizeM * scaling
                        color: Color.mOnSurface
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        text: lockContext.currentText
                        onTextChanged: lockContext.currentText = text

                        Keys.onPressed: function (event) {
                          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            lockContext.tryUnlock()
                          }
                        }

                        Component.onCompleted: forceActiveFocus()
                      }

                      NText {
                        text: passwordInput.text.length > 0 ? "•".repeat(passwordInput.text.length) : I18n.tr("lock-screen.password")
                        color: passwordInput.text.length > 0 ? Color.mOnSurface : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeL * scaling
                        width: 560 * scaling
                        opacity: passwordInput.text.length > 0 ? 1.0 : 0.6
                      }
                    }

                    Rectangle {
                      anchors.right: parent.right
                      anchors.rightMargin: 8 * scaling
                      anchors.verticalCenter: parent.verticalCenter
                      width: 32 * scaling
                      height: 32 * scaling
                      radius: width * 0.5
                      color: submitButtonArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.8)
                      border.color: Color.mPrimary
                      border.width: 1
                      enabled: !lockContext.unlockInProgress

                      NIcon {
                        anchors.centerIn: parent
                        icon: "arrow-forward"
                        pointSize: Style.fontSizeS * scaling
                        color: Color.mOnPrimary
                      }

                      MouseArea {
                        id: submitButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: lockContext.tryUnlock()
                      }
                    }

                    Behavior on border.color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }
                }

                // System control buttons
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 44 * scaling
                  spacing: 8 * scaling

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44 * scaling
                    radius: 22 * scaling
                    color: logoutButtonArea.containsMouse ? Color.mTertiary : "transparent"

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "logout"
                        pointSize: Style.fontSizeL * scaling
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.logout")
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
                        font.weight: Font.Medium
                      }
                    }

                    MouseArea {
                      id: logoutButtonArea
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: CompositorService.logout()
                    }

                    Behavior on color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44 * scaling
                    radius: 22 * scaling
                    color: rebootButtonArea.containsMouse ? Color.mTertiary : "transparent"

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "reboot"
                        pointSize: Style.fontSizeL * scaling
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.reboot")
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
                        font.weight: Font.Medium
                      }
                    }

                    MouseArea {
                      id: rebootButtonArea
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: CompositorService.reboot()
                    }

                    Behavior on color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44 * scaling
                    radius: 22 * scaling
                    color: shutdownButtonArea.containsMouse ? Color.mError : "transparent"
                    border.color: shutdownButtonArea.containsMouse ? Color.mError : Color.transparent
                    border.width: 1

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "shutdown"
                        pointSize: Style.fontSizeL * scaling
                        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.shutdown")
                        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
                        font.weight: Font.Medium
                      }
                    }

                    MouseArea {
                      id: shutdownButtonArea
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: CompositorService.shutdown()
                    }

                    Behavior on color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on border.color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }
                }
              }
            }

            // Status message
            NText {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 150 * scaling
              text: {
                if (lockContext.unlockInProgress)
                  return lockContext.infoMessage || "Authenticating..."
                if (lockContext.showFailure && lockContext.errorMessage)
                  return lockContext.errorMessage
                if (lockContext.showFailure)
                  return "Authentication failed. Please try again."
                return ""
              }
              color: lockContext.unlockInProgress ? Color.mPrimary : (lockContext.showFailure ? Color.mError : Color.transparent)
              pointSize: Style.fontSizeS * scaling
              horizontalAlignment: Text.AlignHCenter
              opacity: text.length > 0 ? 1.0 : 0.0

              SequentialAnimation on opacity {
                running: lockContext.unlockInProgress
                loops: Animation.Infinite
                NumberAnimation {
                  to: 0.6
                  duration: 1000
                  easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                  to: 1.0
                  duration: 1000
                  easing.type: Easing.InOutQuad
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: 300
                  easing.type: Easing.OutCubic
                }
              }
            }
          }
        }
      }
    }
  }
}
