import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

Item {
  id: builtInLockScreen

  required property var lockContext
  required property var screen
  property bool compactMode: false
  property bool animationsEnabled: false

  Item {
    id: batteryIndicator
    property bool isReady: BatteryService.batteryReady
    property real percent: BatteryService.batteryPercentage
    property bool charging: BatteryService.batteryCharging
    property bool pluggedIn: BatteryService.batteryPluggedIn
    property bool batteryVisible: isReady
    property string icon: BatteryService.batteryIcon
  }

  Item {
    id: keyboardLayout
    property string currentLayout: KeyboardLayoutService.currentLayout
  }

  LockScreenBackground {
    id: backgroundComponent
    screen: screen
  }

  Item {
    anchors.fill: parent

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: {
        if (passwordInput && !passwordInput.activeFocus)
          passwordInput.forceActiveFocus();
      }
    }

    LockScreenHeader {
      id: headerComponent
    }

    // Info notification
    Rectangle {
      width: infoRowLayout.implicitWidth + Style.marginXL * 1.5
      height: 50
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: (compactMode ? 280 : 360) * Style.uiScaleRatio
      radius: Style.radiusL
      color: Color.mTertiary
      visible: lockContext.showInfo && lockContext.infoMessage && !panelComponent.timerActive
      opacity: visible ? 1.0 : 0.0

      RowLayout {
        id: infoRowLayout
        anchors.centerIn: parent
        spacing: Style.marginM

        NIcon {
          icon: Icon.credentials
          pointSize: Style.fontSizeXL
          color: Color.mOnTertiary
        }

        NText {
          text: lockContext.infoMessage
          color: Color.mOnTertiary
          pointSize: Style.fontSizeL
          horizontalAlignment: Text.AlignHCenter
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }
    }

    // Error notification
    Rectangle {
      width: errorRowLayout.implicitWidth + Style.marginXL * 1.5
      height: 50
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: (compactMode ? 280 : 360) * Style.uiScaleRatio
      radius: Style.radiusL
      color: Color.mError
      visible: lockContext.showFailure && lockContext.errorMessage && !panelComponent.timerActive
      opacity: visible ? 1.0 : 0.0

      RowLayout {
        id: errorRowLayout
        anchors.centerIn: parent
        spacing: Style.marginM

        NIcon {
          icon: "alert-circle"
          pointSize: Style.fontSizeXL
          color: Color.mOnError
        }

        NText {
          text: lockContext.errorMessage || "Authentication failed"
          color: Color.mOnError
          pointSize: Style.fontSizeL
          horizontalAlignment: Text.AlignHCenter
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }
    }

    // Countdown notification
    Rectangle {
      width: countdownRowLayout.implicitWidth + Style.marginXL * 1.5
      height: 50
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: (compactMode ? 280 : 360) * Style.uiScaleRatio
      radius: Style.radiusL
      color: Color.mSurface
      visible: panelComponent.timerActive
      opacity: visible ? 1.0 : 0.0

      RowLayout {
        id: countdownRowLayout
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NIcon {
          icon: Icon.clock
          pointSize: Style.fontSizeXL
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("session-menu.action-in-seconds", {
                          "action": I18n.tr("common." + panelComponent.pendingAction),
                          "seconds": Math.ceil(panelComponent.timeRemaining / 1000)
                        })
          color: Color.mOnSurface
          pointSize: Style.fontSizeL
          horizontalAlignment: Text.AlignHCenter
          font.weight: Style.fontWeightBold
        }

        Item {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: Icon.close
          tooltipText: I18n.tr("session-menu.cancel-timer")
          baseSize: 32
          colorBg: Qt.alpha(Color.mPrimary, 0.1)
          colorFg: Color.mPrimary
          colorBgHover: Color.mPrimary
          onClicked: panelComponent.cancelTimer()
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }
    }

    TextInput {
      id: passwordInput
      width: 0
      height: 0
      visible: false
      enabled: !lockContext.unlockInProgress
      echoMode: TextInput.Password
      passwordMaskDelay: 0

      onTextChanged: {
        if (lockContext.passwordText !== text)
          lockContext.passwordText = text;
      }
      Connections {
        target: lockContext
        function onPasswordTextChanged() {
          if (passwordInput.text !== lockContext.passwordText)
            passwordInput.text = lockContext.passwordText;
        }
      }

      Keys.onPressed: function (event) {
        if (Keybinds.checkKey(event, 'enter', Settings)) {
          lockContext.tryUnlock();
          event.accepted = true;
        }
        if (Keybinds.checkKey(event, 'escape', Settings) && panelComponent.timerActive) {
          panelComponent.cancelTimer();
          event.accepted = true;
        }
      }

      Component.onCompleted: forceActiveFocus()
    }

    LockScreenPanel {
      id: panelComponent
      lockControl: lockContext
      batteryIndicator: batteryIndicator
      keyboardLayout: keyboardLayout
      passwordInput: passwordInput
    }
  }
}
