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

  panelWidth: 380 * scaling
  panelHeight: 500 * scaling

  // Enable keyboard focus for WiFi panel (needed for password input)
  panelKeyboardFocus: true

  property string passwordPromptSsid: ""
  property string passwordInput: ""
  property bool showPasswordPrompt: false

  onOpened: {
    if (Settings.data.network.wifiEnabled && wifiPanel.visible) {
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

        NIconButton {
          icon: "refresh"
          tooltipText: "Refresh networks"
          sizeRatio: 0.8
          enabled: Settings.data.network.wifiEnabled && !NetworkService.isLoading
          onClicked: {
            NetworkService.refreshNetworks()
          }
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close"
          sizeRatio: 0.8
          onClicked: {
            root.close()
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
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
          spacing: Style.marginS * scaling

          // Show errors at the very top
          NText {
            visible: NetworkService.connectStatus === "error" && NetworkService.connectError.length > 0
            text: NetworkService.connectError
            color: Color.mError
            font.pointSize: Style.fontSizeXS * scaling
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          // Scanning... - Now properly centered
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: Settings.data.network.wifiEnabled && NetworkService.isLoading
            spacing: Style.marginM * scaling

            NBusyIndicator {
              running: NetworkService.isLoading
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

          // WiFi disabled message
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

            NText {
              text: "Enable WiFi to see available networks"
              font.pointSize: Style.fontSizeNormal * scaling
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }
          }

          // Network list
          Repeater {
            model: Settings.data.network.wifiEnabled && !NetworkService.isLoading ? Object.values(
                                                                                      NetworkService.networks) : []

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: networkLayout.implicitHeight + (Style.marginM * scaling * 2)
              radius: Style.radiusM * scaling
              color: Color.mSurface
              border.width: Math.max(1, Style.borderS * scaling)
              border.color: modelData.connected ? Color.mOnSurface : Color.mOutline

              ColumnLayout {
                id: networkLayout
                anchors.fill: parent
                anchors.margins: Style.marginM * scaling
                spacing: 0

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS * scaling

                  NIcon {
                    text: NetworkService.signalIcon(modelData.signal)
                    font.pointSize: Style.fontSizeXXL * scaling
                    color: Color.mOnSurface
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    // SSID
                    NText {
                      Layout.fillWidth: true
                      text: modelData.ssid || "Unknown Network"
                      font.pointSize: Style.fontSizeNormal * scaling
                      elide: Text.ElideRight
                      color: Color.mOnSurface
                    }

                    // Security Protocol
                    NText {
                      text: modelData.security && modelData.security !== "--" ? modelData.security : "Open"
                      font.pointSize: Style.fontSizeXXS * scaling
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                      color: Color.mOnSurfaceVariant
                    }
                  }

                  Item {
                    Layout.preferredWidth: Style.baseWidgetSize * 0.7 * scaling
                    Layout.preferredHeight: Style.baseWidgetSize * 0.7 * scaling
                    visible: NetworkService.connectStatusSsid === modelData.ssid
                             && (NetworkService.connectStatus !== ""
                                 || NetworkService.connectingSsid === modelData.ssid)

                    NBusyIndicator {
                      visible: NetworkService.connectingSsid === modelData.ssid
                      running: NetworkService.connectingSsid === modelData.ssid
                      color: Color.mOnSurface
                      anchors.centerIn: parent
                      size: Style.baseWidgetSize * 0.7 * scaling
                    }
                  }
                  // Call to action
                  NButton {
                    id: button
                    outlined: !button.hovered
                    fontSize: Style.fontSizeXS * scaling
                    fontWeight: Style.fontWeightMedium
                    backgroundColor: {
                      if (modelData.connected) {
                        return Color.mError
                      }
                      return Color.mPrimary
                    }
                    text: {
                      if (modelData.connected) {
                        return "Disconnect"
                      }
                      if (modelData.existing) {
                        return "Connect"
                      }
                      return ""
                    }
                    icon: (modelData.connected ? "cancel" : "wifi")
                    onClicked: {
                      if (modelData.connected) {
                        NetworkService.disconnectNetwork(modelData.ssid)
                        showPasswordPrompt = false
                      } else if (NetworkService.isSecured(modelData.security) && !modelData.existing) {
                        showPasswordPrompt = !showPasswordPrompt
                        if (showPasswordPrompt) {
                          passwordPromptSsid = modelData.ssid
                          passwordInput = "" // Clear previous input
                          Qt.callLater(function () {
                            passwordInputField.forceActiveFocus()
                          })
                        }
                      } else {
                        NetworkService.connectNetwork(modelData.ssid, modelData.security)
                      }
                    }
                  }
                }

                // Password prompt section
                Rectangle {
                  visible: modelData.ssid === passwordPromptSsid && showPasswordPrompt
                  Layout.fillWidth: true
                  Layout.preferredHeight: modelData.ssid === passwordPromptSsid && showPasswordPrompt ? 60 * scaling : 0
                  Layout.margins: Style.marginS * scaling

                  color: Color.mSurfaceVariant
                  radius: Style.radiusS * scaling

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.marginS * scaling
                    spacing: Style.marginS * scaling

                    Item {
                      Layout.fillWidth: true
                      Layout.preferredHeight: Math.round(Style.barHeight * scaling)

                      Rectangle {
                        anchors.fill: parent
                        radius: Style.radiusXS * scaling
                        color: Color.transparent
                        border.color: passwordInputField.activeFocus ? Color.mPrimary : Color.mOutline
                        border.width: Math.max(1, Style.borderS * scaling)

                        TextInput {
                          id: passwordInputField
                          anchors.fill: parent
                          anchors.margins: Style.marginM * scaling
                          text: passwordInput
                          font.pointSize: Style.fontSizeS * scaling
                          color: Color.mOnSurface
                          verticalAlignment: TextInput.AlignVCenter
                          clip: true
                          focus: true
                          selectByMouse: true
                          activeFocusOnTab: true
                          inputMethodHints: Qt.ImhNone
                          echoMode: TextInput.Password
                          onTextChanged: passwordInput = text
                          onAccepted: {
                            if (passwordInput !== "") {
                              NetworkService.submitPassword(passwordPromptSsid, passwordInput)
                              showPasswordPrompt = false
                            }
                          }
                        }
                      }
                    }

                    // Connect button
                    NButton {
                      id: connectButton
                      outlined: !connectButton.hovered
                      fontSize: Style.fontSizeXS * scaling
                      fontWeight: Style.fontWeightMedium
                      backgroundColor: Color.mPrimary
                      text: "Connect"
                      icon: "check"
                      enabled: passwordInput !== ""
                      onClicked: {
                        if (passwordInput !== "") {
                          NetworkService.submitPassword(passwordPromptSsid, passwordInput)
                          showPasswordPrompt = false
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
