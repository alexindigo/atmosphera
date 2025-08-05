import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Settings
import qs.Components
import qs.Widgets.SettingsWindow

Item {
    id: root
    width: 22
    height: 22

    property var settingsWindow: null

    Rectangle {
        id: button
        anchors.fill: parent
        color: "transparent"
        radius: width / 2

        Text {
            anchors.centerIn: parent
            text: "settings"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 16
            color: mouseArea.containsMouse ? Theme.accentPrimary : Theme.textPrimary
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (!settingsWindow) {
                    // Create new window
                    settingsWindow = settingsComponent.createObject(null); // No parent to avoid dependency issues
                    if (settingsWindow) {
                        settingsWindow.visible = true;
                        // Handle window closure
                        settingsWindow.visibleChanged.connect(function() {
                            if (settingsWindow && !settingsWindow.visible) {
                                var windowToDestroy = settingsWindow;
                                settingsWindow = null;
                                windowToDestroy.destroy();
                            }
                        });
                    }
                } else if (settingsWindow.visible) {
                    // Close and destroy window
                    var windowToDestroy = settingsWindow;
                    settingsWindow = null;
                    windowToDestroy.visible = false;
                    windowToDestroy.destroy();
                }
            }
        }

        StyledTooltip {
            text: "Settings"
            targetItem: mouseArea
            tooltipVisible: mouseArea.containsMouse
        }
    }

    Component {
        id: settingsComponent
        SettingsWindow {}
    }

    // Clean up on destruction
    Component.onDestruction: {
        if (settingsWindow) {
            var windowToDestroy = settingsWindow;
            settingsWindow = null;
            windowToDestroy.destroy();
        }
    }
}