import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow.Tabs.Components

ColumnLayout {
    id: root

    spacing: 0
    anchors.fill: parent
    anchors.margins: 0

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
    }

    ColumnLayout {
        spacing: 4
        Layout.fillWidth: true

        Text {
            text: "Time"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textPrimary
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Use 12 Hour Clock"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display time in 12-hour format (e.g., 2:30 PM) instead of 24-hour format"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                Rectangle {
                    id: use12HourClockSwitch

                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.use12HourClock ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.use12HourClock ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: use12HourClockThumb

                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.use12HourClock ? use12HourClockSwitch.width - width - 2 : 2

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
                            Settings.settings.use12HourClock = !Settings.settings.use12HourClock;
                        }
                    }

                }

            }

        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "US Style Date"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display dates in MM/DD/YYYY format instead of DD/MM/YYYY"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                Rectangle {
                    id: reverseDayMonthSwitch

                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.reverseDayMonth ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.reverseDayMonth ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: reverseDayMonthThumb

                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.reverseDayMonth ? reverseDayMonthSwitch.width - width - 2 : 2

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
                            Settings.settings.reverseDayMonth = !Settings.settings.reverseDayMonth;
                        }
                    }

                }

            }

        }

    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 26
        Layout.bottomMargin: 18
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    ColumnLayout {
        spacing: 4
        Layout.fillWidth: true

        Text {
            text: "Weather"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textPrimary
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "City"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                text: "Your city name for weather information"
                font.pixelSize: 12
                color: Theme.textSecondary
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 16
                color: Theme.surfaceVariant
                border.color: cityInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                TextInput {
                    id: cityInput

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    text: Settings.settings.weatherCity
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    selectByMouse: true
                    activeFocusOnTab: true
                    inputMethodHints: Qt.ImhNone
                    onTextChanged: {
                        Settings.settings.weatherCity = text;
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            cityInput.forceActiveFocus();
                        }
                    }

                }

            }

        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Temperature Unit"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Choose between Celsius and Fahrenheit"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                UnitSelector {
                }

            }

        }

    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

}
