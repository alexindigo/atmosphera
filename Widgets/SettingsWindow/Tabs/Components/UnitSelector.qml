import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings


Rectangle {
    id: root
    width: 64 * Theme.uiScale
    height: 32 * Theme.uiScale
    radius: 16 * Theme.uiScale
    color: Theme.surfaceVariant
    border.color: Theme.outline
    border.width: 1 * Theme.uiScale

    property bool useFahrenheit: Settings.settings.useFahrenheit
    
    Rectangle {
        id: slider
        width: parent.width / 2 - 4 * Theme.uiScale
        height: parent.height - 4 * Theme.uiScale
        radius: 14 * Theme.uiScale
        color: Theme.accentPrimary
        x: 2 + (useFahrenheit ? parent.width / 2 : 0)
        y: 2

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    
    Row {
        anchors.fill: parent
        spacing: 0

        
        Item {
            width: parent.width / 2
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: "°C"
                font.pixelSize: 13 * Theme.uiScale
                font.bold: !useFahrenheit
                color: !useFahrenheit ? Theme.onAccent : Theme.textPrimary
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (useFahrenheit) {
                        Settings.settings.useFahrenheit = false;
                    }
                }
            }
        }

        
        Item {
            width: parent.width / 2
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: "°F"
                font.pixelSize: 13 * Theme.uiScale
                font.bold: useFahrenheit
                color: useFahrenheit ? Theme.onAccent : Theme.textPrimary
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!useFahrenheit) {
                        Settings.settings.useFahrenheit = true;
                    }
                }
            }
        }
    }
}