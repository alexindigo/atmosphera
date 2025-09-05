import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: 400 * scaling
  panelHeight: 500 * scaling
  panelKeyboardFocus: true

  property string passwordPromptSsid: ""
  property string passwordInput: ""
  property bool showPasswordPrompt: false
  property string expandedNetwork: "" // Track which network shows options

  onOpened: {
    if (Settings.data.network.wifiEnabled) {
      NetworkService.refreshNetworks()
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          text: "wifi"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        NText {
          text: "WiFi"
          font.pointSize: Style.fontSizeL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS * scaling
        }

        // Connection status indicator
        Rectangle {
          visible: NetworkService.hasActiveConnection
          width: 8 * scaling
          height: 8 * scaling
          radius: 4 * scaling
          color: Color.mPrimary
        }

        NIconButton {
          icon: "refresh"
          tooltipText: "Refresh networks"
          sizeRatio: 0.8
          enabled: Settings.data.network.wifiEnabled && !NetworkService.isLoading
          onClicked: NetworkService.refreshNetworks()
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close"
          sizeRatio: 0.8
          onClicked: root.close()
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Error banner
      Rectangle {
        visible: NetworkService.connectStatus === "error" && NetworkService.connectError.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: errorText.implicitHeight + (Style.marginM * scaling * 2)
        color: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.1)
        radius: Style.radiusS * scaling
        border.width: Math.max(1, Style.borderS * scaling)
        border.color: Color.mError

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM * scaling
          spacing: Style.marginS * scaling

          NIcon {
            text: "error"
            font.pointSize: Style.fontSizeL * scaling
            color: Color.mError
          }

          NText {
            id: errorText
            text: NetworkService.connectError
            color: Color.mError
            font.pointSize: Style.fontSizeS * scaling
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            sizeRatio: 0.6
            onClicked: {
              NetworkService.connectStatus = ""
              NetworkService.connectError = ""
            }
          }
        }
      }

      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
          width: parent.width
          spacing: Style.marginM * scaling

          // Loading state
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: Settings.data.network.wifiEnabled && NetworkService.isLoading && Object.keys(
                       NetworkService.networks).length === 0
            spacing: Style.marginM * scaling

            NBusyIndicator {
              running: true
              color: Color.mPrimary
              size: Style.baseWidgetSize * scaling
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: "Scanning for networks..."
              font.pointSize: Style.fontSizeNormal * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }
          }

          // WiFi disabled state
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: !Settings.data.network.wifiEnabled
            spacing: Style.marginM * scaling

            NIcon {
              text: "wifi_off"
              font.pointSize: Style.fontSizeXXXL * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: "WiFi is disabled"
              font.pointSize: Style.fontSizeL * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }

            NButton {
              text: "Enable WiFi"
              icon: "wifi"
              Layout.alignment: Qt.AlignHCenter
              onClicked: {
                Settings.data.network.wifiEnabled = true
                Settings.save()
                NetworkService.setWifiEnabled(true)
              }
            }
          }

          // Network list
          Repeater {
            model: {
              if (!Settings.data.network.wifiEnabled || NetworkService.isLoading)
                return []

              // Sort networks: connected first, then by signal strength
              const nets = Object.values(NetworkService.networks)
              return nets.sort((a, b) => {
                                 if (a.connected && !b.connected)
                                 return -1
                                 if (!a.connected && b.connected)
                                 return 1
                                 return b.signal - a.signal
                               })
            }

            Item {
              Layout.fillWidth: true
              implicitHeight: networkRect.implicitHeight

              Rectangle {
                id: networkRect
                width: parent.width
                implicitHeight: networkContent.implicitHeight + (Style.marginM * scaling * 2)
                radius: Style.radiusM * scaling
                color: modelData.connected ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b,
                                                     0.05) : Color.mSurface
                border.width: Math.max(1, Style.borderS * scaling)
                border.color: modelData.connected ? Color.mPrimary : Color.mOutline
                clip: true

                ColumnLayout {
                  id: networkContent
                  width: parent.width - (Style.marginM * scaling * 2)
                  x: Style.marginM * scaling
                  y: Style.marginM * scaling
                  spacing: Style.marginM * scaling

                  // Main network row
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS * scaling

                    // Signal icon
                    NIcon {
                      text: NetworkService.signalIcon(modelData.signal)
                      font.pointSize: Style.fontSizeXXL * scaling
                      color: modelData.connected ? Color.mPrimary : Color.mOnSurface
                    }

                    // Network info
                    ColumnLayout {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 0

                      NText {
                        text: modelData.ssid || "Unknown Network"
                        font.pointSize: Style.fontSizeNormal * scaling
                        font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                        elide: Text.ElideRight
                        color: Color.mOnSurface
                        Layout.fillWidth: true
                      }

                      NText {
                        text: {
                          const security = modelData.security
                                         && modelData.security !== "--" ? modelData.security : "Open"
                          const signal = `${modelData.signal}%`
                          return `${signal} • ${security}`
                        }
                        font.pointSize: Style.fontSizeXXS * scaling
                        color: Color.mOnSurfaceVariant
                      }
                    }

                    // Right-aligned items container
                    RowLayout {
                      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                      spacing: Style.marginS * scaling

                      // Connected badge
                      Rectangle {
                        visible: modelData.connected
                        color: Color.mPrimary
                        radius: width * 0.5
                        width: connectedLabel.implicitWidth + (Style.marginS * scaling * 2)
                        height: connectedLabel.implicitHeight + (Style.marginXS * scaling * 2)

                        NText {
                          id: connectedLabel
                          anchors.centerIn: parent
                          text: "Connected"
                          font.pointSize: Style.fontSizeXXS * scaling
                          color: Color.mOnPrimary
                        }
                      }

                      // Saved badge - clickable
                      Rectangle {
                        visible: modelData.cached && !modelData.connected
                        color: Color.mSurfaceVariant
                        radius: width * 0.5
                        width: savedLabel.implicitWidth + (Style.marginS * scaling * 2)
                        height: savedLabel.implicitHeight + (Style.marginXS * scaling * 2)
                        border.color: Color.mOutline
                        border.width: Math.max(1, Style.borderS * scaling)

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onEntered: parent.color = Qt.darker(Color.mSurfaceVariant, 1.1)
                          onExited: parent.color = Color.mSurfaceVariant
                          onClicked: {
                            expandedNetwork = expandedNetwork === modelData.ssid ? "" : modelData.ssid
                            showPasswordPrompt = false
                          }
                        }

                        NText {
                          id: savedLabel
                          anchors.centerIn: parent
                          text: "Saved"
                          font.pointSize: Style.fontSizeXXS * scaling
                          color: Color.mOnSurfaceVariant
                        }
                      }

                      // Loading indicator
                      NBusyIndicator {
                        visible: NetworkService.connectingSsid === modelData.ssid
                        running: NetworkService.connectingSsid === modelData.ssid
                        color: Color.mPrimary
                        size: Style.baseWidgetSize * 0.6 * scaling
                      }

                      // Action buttons
                      RowLayout {
                        spacing: Style.marginXS * scaling
                        visible: NetworkService.connectingSsid !== modelData.ssid

                        NButton {
                          visible: !modelData.connected && (expandedNetwork !== modelData.ssid || !showPasswordPrompt)
                          outlined: !hovered
                          fontSize: Style.fontSizeXS * scaling
                          text: modelData.existing ? "Connect" : (NetworkService.isSecured(
                                                                    modelData.security) ? "Password" : "Connect")
                          onClicked: {
                            if (modelData.existing || !NetworkService.isSecured(modelData.security)) {
                              NetworkService.connectNetwork(modelData.ssid, modelData.security)
                            } else {
                              expandedNetwork = modelData.ssid
                              passwordPromptSsid = modelData.ssid
                              showPasswordPrompt = true
                              passwordInput = ""
                              Qt.callLater(() => passwordInputField.forceActiveFocus())
                            }
                          }
                        }

                        NButton {
                          visible: modelData.connected
                          outlined: !hovered
                          fontSize: Style.fontSizeXS * scaling
                          backgroundColor: Color.mError
                          text: "Disconnect"
                          onClicked: NetworkService.disconnectNetwork(modelData.ssid)
                        }
                      }
                    }
                  }

                  // Password input section
                  Rectangle {
                    visible: modelData.ssid === passwordPromptSsid && showPasswordPrompt
                    Layout.fillWidth: true
                    implicitHeight: visible ? 50 * scaling : 0
                    color: Color.mSurfaceVariant
                    radius: Style.radiusS * scaling

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: Style.marginS * scaling
                      spacing: Style.marginS * scaling

                      Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Style.radiusS * scaling
                        color: Color.mSurface
                        border.color: passwordInputField.activeFocus ? Color.mSecondary : Color.mOutline
                        border.width: Math.max(1, Style.borderS * scaling)

                        TextInput {
                          id: passwordInputField
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.leftMargin: Style.marginM * scaling
                          anchors.rightMargin: Style.marginM * scaling
                          height: parent.height
                          text: passwordInput
                          font.pointSize: Style.fontSizeM * scaling
                          color: Color.mOnSurface
                          verticalAlignment: TextInput.AlignVCenter
                          clip: true
                          focus: modelData.ssid === passwordPromptSsid && showPasswordPrompt
                          selectByMouse: true
                          echoMode: TextInput.Password
                          passwordCharacter: "●"
                          onTextChanged: passwordInput = text
                          onAccepted: {
                            if (passwordInput) {
                              NetworkService.submitPassword(passwordPromptSsid, passwordInput)
                              showPasswordPrompt = false
                              expandedNetwork = ""
                            }
                          }

                          Text {
                            visible: parent.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Enter password..."
                            color: Color.mOnSurfaceVariant
                            font.pointSize: Style.fontSizeS * scaling
                          }
                        }
                      }

                      NButton {
                        text: "Connect"
                        icon: "check"
                        fontSize: Style.fontSizeXS * scaling
                        enabled: passwordInput.length > 0
                        outlined: !enabled
                        onClicked: {
                          if (passwordInput) {
                            NetworkService.submitPassword(passwordPromptSsid, passwordInput)
                            showPasswordPrompt = false
                            expandedNetwork = ""
                          }
                        }
                      }

                      NIconButton {
                        icon: "close"
                        tooltipText: "Cancel"
                        sizeRatio: 0.9
                        onClicked: {
                          showPasswordPrompt = false
                          expandedNetwork = ""
                          passwordInput = ""
                        }
                      }
                    }
                  }

                  // Forget network option - appears when saved badge is clicked
                  RowLayout {
                    visible: (modelData.existing || modelData.cached) && expandedNetwork === modelData.ssid
                             && !showPasswordPrompt
                    Layout.fillWidth: true
                    Layout.topMargin: Style.marginXS * scaling
                    spacing: Style.marginS * scaling

                    Item {
                      Layout.fillWidth: true
                    }

                    NButton {
                      id: forgetButton
                      text: "Forget Network"
                      icon: "delete_outline"
                      fontSize: Style.fontSizeXXS * scaling
                      backgroundColor: Color.mError
                      textColor: !forgetButton.hovered ? Color.mError : Color.mOnTertiary
                      outlined: !forgetButton.hovered
                      Layout.preferredHeight: 28 * scaling
                      onClicked: {
                        NetworkService.forgetNetwork(modelData.ssid)
                        expandedNetwork = ""
                      }
                    }
                  }
                }
              }
            }
          }

          // No networks found
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: Settings.data.network.wifiEnabled && !NetworkService.isLoading && Object.keys(
                       NetworkService.networks).length === 0
            spacing: Style.marginM * scaling

            NIcon {
              text: "wifi_find"
              font.pointSize: Style.fontSizeXXXL * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: "No networks found"
              font.pointSize: Style.fontSizeL * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }

            NButton {
              text: "Refresh"
              icon: "refresh"
              Layout.alignment: Qt.AlignHCenter
              onClicked: NetworkService.refreshNetworks()
            }
          }
        }
      }
    }
  }
}
