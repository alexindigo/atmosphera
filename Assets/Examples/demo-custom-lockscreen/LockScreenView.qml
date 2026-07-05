import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Media
import qs.Services.Compositor
import qs.Services.UI
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Networking
import Quickshell.Io
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

  // Network fallback detection (independent of NetworkManager)
  QtObject {
    id: networkFallback
    property string state: "disconnected"
    property string iface: ""
    property string type: ""
    property string ssid: ""
  }

  Timer {
    id: networkProbeTimer
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: networkProbe.running = true
  }

  Process {
    id: networkProbe
    command: ["sh", "-c",
      "IFACE=$(ip -4 route show default | awk '/default/ {print $5; exit}'); if [ -z \"$IFACE\" ]; then echo \"STATE=disconnected\"; exit 0; fi; case \"$IFACE\" in wl*) TYPE=wifi;; en*|eth*) TYPE=ethernet;; *) TYPE=other;; esac; SSID=\"\"; if [ \"$TYPE\" = \"wifi\" ]; then for probe in iwgetid iw nmcli iwctl; do command -v \"$probe\" >/dev/null 2>&1 || continue; case \"$probe\" in iwgetid) SSID=$(iwgetid -r 2>/dev/null);; iw) SSID=$(iw dev \"$IFACE\" link 2>/dev/null | sed -n 's/^\\s*SSID: //p');; nmcli) SSID=$(nmcli -t -f active,ssid device wifi 2>/dev/null | awk -F: '/^yes/ {print $2; exit}');; iwctl) SSID=$(iwctl station \"$IFACE\" show 2>/dev/null | awk -F': +' '/Connected network/ {print $2; exit}');; esac; [ -n \"$SSID\" ] && break; done; fi; echo \"STATE=connected\"; echo \"IFACE=$IFACE\"; echo \"TYPE=$TYPE\"; echo \"SSID=$SSID\""]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("=", 2);
          if (parts.length === 2) {
            var key = parts[0].trim();
            var val = parts[1].trim();
            if (key === "STATE")
              networkFallback.state = val;
            else if (key === "IFACE")
              networkFallback.iface = val;
            else if (key === "TYPE")
              networkFallback.type = val;
            else if (key === "SSID")
              networkFallback.ssid = val;
          }
        }
      }
    }
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

      Item {
        width: networkRow.implicitWidth
        height: networkRow.implicitHeight

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = root._networkLabel()
          onExited: topLeftRow.hoverLabel = ""
        }

        RowLayout {
          id: networkRow
          spacing: Style.marginS

          NIcon {
            icon: root._networkIcon()
            pointSize: 15
            color: "white"
          }
        }
      }

      Item {
        width: batteryRow.implicitWidth
        height: batteryRow.implicitHeight
        visible: BatteryService.batteryReady

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = root._batteryLabel()
          onExited: topLeftRow.hoverLabel = ""
        }

        RowLayout {
          id: batteryRow
          spacing: Style.marginS

          NIcon {
            icon: BatteryService.batteryIcon
            pointSize: 15
            color: "white"
          }
        }
      }

      Item {
        width: keyboardRow.implicitWidth
        height: keyboardRow.implicitHeight
        visible: KeyboardLayoutService.currentLayout !== "Unknown" && KeyboardLayoutService.currentLayout !== ""

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: topLeftRow.hoverLabel = KeyboardLayoutService.fullLayoutName
          onExited: topLeftRow.hoverLabel = ""
        }

        RowLayout {
          id: keyboardRow
          spacing: Style.marginS

          NText {
            text: KeyboardLayoutService.currentLayout
            color: "white"
            pointSize: 13
          }
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

    Text {
      id: clockText
      Layout.alignment: Qt.AlignHCenter
      font.pointSize: (lockScreenApi && lockScreenApi.compactMode) ? Style.fontSizeXXL : Style.fontSizeXXXL * 2
      font.weight: Style.fontWeightLight
      color: "white"
      Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._updateClock()
      }
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      font.pointSize: Style.fontSizeL
      color: Qt.rgba(1, 1, 1, 0.7)
      text: new Date().toLocaleDateString(Qt.locale(), "dddd, MMMM d")
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

      NIconButton {
        icon: Icon.close
        baseSize: 32
        customRadius: 16
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

      NIconButton {
        icon: Icon.suspend
        baseSize: 32
        customRadius: 16
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        onEntered: topRightRow.hoverLabel = "suspend session"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.suspend()
      }

      NIconButton {
        icon: Icon.hibernate
        baseSize: 32
        customRadius: 16
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

      NIconButton {
        icon: Icon.reboot
        baseSize: 32
        customRadius: 16
        colorBg: Qt.rgba(1, 1, 1, 0.12)
        colorBorder: Qt.rgba(1, 1, 1, 0.25)
        colorFg: "white"
        colorBgHover: Qt.rgba(1, 1, 1, 0.25)
        colorBorderHover: Qt.rgba(1, 1, 1, 0.4)
        onEntered: topRightRow.hoverLabel = "reboot laptop"
        onExited: topRightRow.hoverLabel = ""
        onClicked: CompositorService.reboot()
      }

      NIconButton {
        icon: Icon.shutdown
        baseSize: 32
        customRadius: 16
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

      NIconButton {
        icon: Icon.mediaPrev
        colorFg: "white"
        baseSize: 32
        visible: MediaService.canGoPrevious
        onClicked: MediaService.previous()
      }
      NIconButton {
        icon: MediaService.isPlaying ? Icon.mediaPause : Icon.mediaPlay
        colorFg: "white"
        baseSize: 32
        visible: MediaService.canPlay || MediaService.canPause
        onClicked: MediaService.playPause()
      }
      NIconButton {
        icon: Icon.mediaNext
        colorFg: "white"
        baseSize: 32
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

      NIconButton {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 4
        icon: Icon.login
        baseSize: 32
        customRadius: 16
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
    clockText.text = Qt.locale().toString(new Date(), fmt.replace(/\\n/g, "\n"));
  }

  function _networkIcon() {
    if (NetworkService.wifiConnected || NetworkService.ethernetConnected)
      return NetworkService.getIcon();
    if (networkFallback.state === "connected") {
      if (networkFallback.type === "wifi")
        return "wifi";
      if (networkFallback.type === "ethernet")
        return "ethernet";
      return "wifi";
    }
    return "wifi-off";
  }

  function _networkLabel() {
    if (NetworkService.wifiConnected || NetworkService.ethernetConnected) {
      if (NetworkService.ethernetConnected)
        return "Ethernet connected";
      var ssid = NetworkService.getStatusText(false);
      return ssid !== "" ? "WiFi: " + ssid : "WiFi connected";
    }
    if (networkFallback.state === "connected") {
      if (networkFallback.type === "wifi")
        return networkFallback.ssid !== "" ? "WiFi: " + networkFallback.ssid : "WiFi connected";
      if (networkFallback.type === "ethernet")
        return "Ethernet connected";
      return "Connected (" + networkFallback.iface + ")";
    }
    return "WiFi disconnected";
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
