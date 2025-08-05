import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.Settings
import qs.Components

ColumnLayout {
    id: root
    spacing: 24

    Component.onCompleted: {
    
        Quickshell.execDetached(["nmcli", "-t", "-f", "WIFI", "radio"])
    }


    ColumnLayout {
        spacing: 16
        Layout.fillWidth: true

        Text {
            text: "Wi-Fi"
            font.pixelSize: 16
            font.bold: true
            color: Theme.textPrimary
        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Enable Wi-Fi"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Turn Wi-Fi radio on or off"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: wifiSwitch
                    width: 52
                    height: 32
                    radius: 16
                    property bool checked: Settings.settings.wifiEnabled
                    color: checked ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: checked ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: wifiThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: wifiSwitch.checked ? wifiSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.wifiEnabled = !Settings.settings.wifiEnabled
                            Quickshell.execDetached(["nmcli", "radio", "wifi", Settings.settings.wifiEnabled ? "on" : "off"])
                        }
                    }
                }
            }
        }
    }


    ColumnLayout {
        spacing: 16
        Layout.fillWidth: true
        Layout.topMargin: 58

        Text {
            text: "Bluetooth"
            font.pixelSize: 16
            font.bold: true
            color: Theme.textPrimary
        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Enable Bluetooth"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Turn Bluetooth radio on or off"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: bluetoothSwitch
                    width: 52
                    height: 32
                    radius: 16
                    property bool checked: Settings.settings.bluetoothEnabled
                    color: checked ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: checked ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: bluetoothThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: bluetoothSwitch.checked ? bluetoothSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Bluetooth.defaultAdapter) {
                                Settings.settings.bluetoothEnabled = !Settings.settings.bluetoothEnabled
                                Bluetooth.defaultAdapter.enabled = Settings.settings.bluetoothEnabled
                                if (Bluetooth.defaultAdapter.enabled) {
                                    Bluetooth.defaultAdapter.discovering = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }
}