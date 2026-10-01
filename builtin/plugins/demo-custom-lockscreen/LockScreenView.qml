import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  required property var lockContext
  property var pluginApi: null
  property var screen
  property var lockScreenApi: null

  readonly property bool _mediaVisible: (lockScreenApi?.showMediaControls !== false) && (pluginApi?.pluginSettings?.showMediaControls !== false) && MediaService.currentPlayer && MediaService.canPlay

  // Wallpaper background
  AtmoWallpaperBackground {
    screen: root.screen
  }

  // Dark overlay for readability
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.4 + (lockScreenApi?.lockTint ?? 0) * 0.35)
  }

  // TOP-LEFT: Network + Battery + Keyboard status
  ColumnLayout {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: 16
    spacing: 4

    RowLayout {
      id: topLeftRow
      property string hoverLabel: ""
      spacing: Style.marginL

      // Fixed-size icon slots: AtmoIcon's implicit width for svg glyphs
      // doesn't cover the mask spread, so sizing wrappers from implicit
      // metrics lets glyphs paint into their neighbors.
      Item {
        implicitWidth: networkIconBox.implicitWidth
        implicitHeight: networkIconBox.implicitHeight

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = root._networkLabel()
          onExited: topLeftRow.hoverLabel = ""
        }

        Item {
          id: networkIconBox
          implicitWidth: Math.round(Style.fontSizeL * Style.uiScaleRatio * 1.5)
          implicitHeight: implicitWidth

          AtmoIcon {
            anchors.centerIn: parent
            icon: root._networkIcon()
            pointSize: Style.fontSizeL
            color: "white"
          }
        }
      }

      Item {
        implicitWidth: batteryIconBox.implicitWidth
        implicitHeight: batteryIconBox.implicitHeight
        visible: BatteryService.batteryReady

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = root._batteryLabel()
          onExited: topLeftRow.hoverLabel = ""
        }

        Item {
          id: batteryIconBox
          implicitWidth: Math.round(Style.fontSizeL * Style.uiScaleRatio * 1.5)
          implicitHeight: implicitWidth

          AtmoIcon {
            anchors.centerIn: parent
            icon: BatteryService.batteryIcon
            pointSize: Style.fontSizeL
            color: "white"
          }
        }
      }

      Item {
        implicitWidth: keyboardText.implicitWidth
        implicitHeight: keyboardText.implicitHeight
        visible: KeyboardLayoutService.currentLayout !== "Unknown" && KeyboardLayoutService.currentLayout !== ""

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = KeyboardLayoutService.fullLayoutName
          onExited: topLeftRow.hoverLabel = ""
        }

        NText {
          id: keyboardText
          text: KeyboardLayoutService.currentLayout
          color: "white"
          pointSize: Style.fontSizeM
        }
      }
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: true
      Layout.topMargin: Style.marginXS
      horizontalAlignment: Text.AlignHCenter
      text: topLeftRow.hoverLabel
      color: Qt.rgba(1, 1, 1, 0.8)
      font.pointSize: Style.fontSizeS
      opacity: text !== "" ? 1 : 0
      Behavior on opacity {
        enabled: lockScreenApi && lockScreenApi.animationsEnabled !== false
        NumberAnimation {
          duration: 120
        }
      }
    }
  }

  // TOP: Clock + Date (placed high)
  ColumnLayout {
    anchors.top: parent.top
    anchors.topMargin: 80
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.marginM

    // Date first (small, above the clock), clock below — the macOS
    // lock-screen composition.
    Text {
      Layout.alignment: Qt.AlignHCenter
      font.pointSize: Style.fontSizeL
      color: Qt.rgba(1, 1, 1, 0.7)
      text: new Date().toLocaleDateString(Qt.locale(), "dddd, MMMM d")
    }

    Column {
      Layout.alignment: Qt.AlignHCenter
      spacing: 0

      // One NText per line (the built-in clock's pattern): per-line
      // centering, no multi-line alignment surprises.
      Repeater {
        id: clockRepeater
        model: []
        NText {
          text: modelData
          horizontalAlignment: Text.AlignHCenter
          Layout.alignment: Qt.AlignHCenter
          anchors.horizontalCenter: parent.horizontalCenter
          pointSize: (lockScreenApi && lockScreenApi.compactMode) ? Style.fontSizeXXL : Style.fontSizeXXXL * 2.5
          color: "white"
        }
      }

      Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._updateClock()
      }
      Component.onCompleted: root._updateClock()
    }
  }

  // TOP-RIGHT: Close + Session action icons (horizontal row)
  ColumnLayout {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 16
    spacing: 4

    RowLayout {
      id: topRightRow
      property string hoverLabel: ""
      Layout.alignment: Qt.AlignRight
      spacing: 8

      AtmoIconButton {
        icon: Icon.close
        baseSize: 28
        customRadius: 14
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        visible: PanelService.lockScreen?.previewMode ?? false
        onEntered: topRightRow.hoverLabel = "close preview"
        onExited: topRightRow.hoverLabel = ""
        onClicked: root.lockContext.unlocked()
      }

      AtmoIconButton {
        icon: Icon.suspend
        baseSize: 28
        customRadius: 14
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        onEntered: topRightRow.hoverLabel = "suspend session"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.suspend()
      }

      AtmoIconButton {
        icon: Icon.hibernate
        baseSize: 28
        customRadius: 14
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        visible: lockScreenApi?.showHibernate === true
        onEntered: topRightRow.hoverLabel = "hibernate session"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.hibernate()
      }

      AtmoIconButton {
        icon: Icon.reboot
        baseSize: 28
        customRadius: 14
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        onEntered: topRightRow.hoverLabel = "reboot laptop"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.reboot()
      }

      AtmoIconButton {
        icon: Icon.shutdown
        baseSize: 28
        customRadius: 14
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        onEntered: topRightRow.hoverLabel = "shut down laptop"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.shutdown()
      }
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: true
      Layout.topMargin: Style.marginXS
      horizontalAlignment: Text.AlignHCenter
      text: topRightRow.hoverLabel
      color: Qt.rgba(1, 1, 1, 0.8)
      font.pointSize: Style.fontSizeS
      opacity: text !== "" ? 1 : 0
      Behavior on opacity {
        enabled: lockScreenApi && lockScreenApi.animationsEnabled !== false
        NumberAnimation {
          duration: 120
        }
      }
    }
  }

  // BOTTOM: Media info → Media controls → Password → Error
  ColumnLayout {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 24
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.marginM

    // Media info row
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      visible: _mediaVisible
      spacing: Style.marginM

      Rectangle {
        width: 40
        height: 40
        radius: 8
        clip: true
        color: "transparent"
        Image {
          anchors.fill: parent
          source: MediaService.trackArtUrl
          visible: MediaService.trackArtUrl !== ""
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
        }
      }

      ColumnLayout {
        spacing: 1
        Text {
          text: MediaService.trackTitle ?? "No media"
          color: "white"
          font.pointSize: Style.fontSizeS
          elide: Text.ElideRight
          Layout.preferredWidth: 140
        }
        Text {
          text: MediaService.trackArtist ?? ""
          color: Qt.rgba(1, 1, 1, 0.6)
          font.pointSize: Style.fontSizeXS
          elide: Text.ElideRight
          Layout.preferredWidth: 140
        }
      }
    }

    // Media controls row
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      visible: _mediaVisible
      spacing: Style.marginS

      AtmoIconButton {
        icon: Icon.mediaPrev
        colorFg: "white"
        baseSize: 28
        visible: MediaService.canGoPrevious
        onClicked: MediaService.previous()
      }
      AtmoIconButton {
        icon: MediaService.isPlaying ? Icon.mediaPause : Icon.mediaPlay
        colorFg: "white"
        baseSize: 28
        visible: MediaService.canPlay || MediaService.canPause
        onClicked: MediaService.playPause()
      }
      AtmoIconButton {
        icon: Icon.mediaNext
        colorFg: "white"
        baseSize: 28
        visible: MediaService.canGoNext
        onClicked: MediaService.next()
      }
    }

    Item {
      Layout.preferredHeight: Style.marginS
    }

    // Password box
    Rectangle {
      Layout.alignment: Qt.AlignHCenter
      Layout.preferredWidth: 280
      Layout.preferredHeight: 48
      radius: 12
      color: Qt.rgba(1, 1, 1, 0.12)
      border.color: Qt.rgba(1, 1, 1, 0.25)
      border.width: 1

      TextInput {
        id: passInput
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 48
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.pointSize: Style.fontSizeM
        echoMode: TextInput.Password
        passwordCharacter: lockScreenApi?.passwordChars ? "●" : undefined
        passwordMaskDelay: 0
        onAccepted: root.unlock()
        Keys.onEscapePressed: passInput.text = ""
      }

      AtmoIconButton {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 4
        icon: Icon.login
        baseSize: 28
        customRadius: 14
        colorBg: "transparent"
        colorBorder: "transparent"
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.15)
        colorBorderHover: "transparent"
        colorFgHover: "white"
        onClicked: root.unlock()
      }
    }

    // Error feedback (below password)
    Text {
      id: errorText
      Layout.alignment: Qt.AlignHCenter
      text: ""
      color: "#ff5252"
      font.pointSize: Style.fontSizeS
      opacity: root.lockContext.showFailure ? 1 : 0
      Behavior on opacity {
        enabled: lockScreenApi?.animationsEnabled !== false
        NumberAnimation {
          duration: 150
        }
      }
      states: State {
        name: "visible"
        when: root.lockContext.showFailure
        PropertyChanges {
          target: errorText
          text: root.lockContext.errorMessage ?? "Wrong password"
        }
      }
    }
  }

  function unlock() {
    if (passInput.text !== "") {
      root.lockContext.passwordText = passInput.text;
      root.lockContext.tryUnlock();
    }
  }

  function _updateClock() {
    var fmt = (lockScreenApi && lockScreenApi.clockFormat) ? lockScreenApi.clockFormat : "HH:mm";
    clockRepeater.model = Qt.locale().toString(new Date(), fmt.replace(/\\n/g, "\n")).split("\n");
  }

  function _networkIcon() {
    return NetworkService.getIcon();
  }

  function _networkLabel() {
    return NetworkService.getStatusText(true);
  }

  function _batteryLabel() {
    if (!BatteryService.batteryReady)
      return "";
    var pct = Math.round(BatteryService.batteryPercentage) + "%";
    var timeText = BatteryService.getTimeRemainingText(BatteryService.primaryDevice);
    return pct + " — " + timeText;
  }

  Component.onCompleted: {
    _updateClock();
    passInput.forceActiveFocus();
  }

  Connections {
    target: root.lockContext
    function onFailed() {
      passInput.text = "";
      passInput.forceActiveFocus();
    }
  }
}
