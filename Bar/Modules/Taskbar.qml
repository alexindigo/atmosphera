import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Settings
import qs.Components

Item {
    id: taskbar
    width: runningAppsRow.width
    height: Settings.settings.taskbarIconSize

    function getAppIcon(toplevel: Toplevel): string {
        if (!toplevel)
            return "";

        // Try different icon resolution strategies
        let icon = Quickshell.iconPath(toplevel.appId?.toLowerCase(), true);
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.appId, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.title?.toLowerCase(), true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.title, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath("application-x-executable", true);
        }

        return icon || "";
    }

    Row {
        id: runningAppsRow
        spacing: 8
        height: parent.height

        Repeater {
            model: ToplevelManager ? ToplevelManager.toplevels : null

            delegate: Rectangle {

                id: appButton
                width: Settings.settings.taskbarIconSize
                height: Settings.settings.taskbarIconSize
                radius: Math.max(4, Settings.settings.taskbarIconSize * 0.25)
                color: isActive ? Theme.accentPrimary : (hovered ? Theme.surfaceVariant : "transparent")
                border.color: isActive ? Qt.darker(Theme.accentPrimary, 1.2) : "transparent"
                border.width: 1



                property bool isActive: ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData
                property bool hovered: mouseArea.containsMouse
                property string appId: modelData ? modelData.appId : ""
                property string appTitle: modelData ? modelData.title : ""

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                // App icon
                IconImage {
                    id: appIcon
                    width: Math.max(12, Settings.settings.taskbarIconSize * 0.625)  // 62.5% of button size (20/32 = 0.625)
                    height: Math.max(12, Settings.settings.taskbarIconSize * 0.625)
                    anchors.centerIn: parent
                    source: getAppIcon(modelData)
                    smooth: true

                    // Fallback to first letter if no icon
                    visible: source.toString() !== ""
                }

                // Fallback text if no icon available
                Text {
                    anchors.centerIn: parent
                    visible: !appIcon.visible
                    text: appButton.appId ? appButton.appId.charAt(0).toUpperCase() : "?"
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(10, Settings.settings.taskbarIconSize * 0.4375)  // 43.75% of button size (14/32 = 0.4375)
                    font.bold: true
                    color: appButton.isActive ? Theme.onAccent : Theme.textPrimary
                }

                // Tooltip
                ToolTip {
                    id: tooltip
                    visible: mouseArea.containsMouse && !mouseArea.pressed
                    delay: 800
                    text: appTitle || appId

                    background: Rectangle {
                        color: Theme.backgroundPrimary
                        border.color: Theme.outline
                        border.width: 1
                        radius: 8
                    }

                    contentItem: Text {
                        text: tooltip.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        color: Theme.textPrimary
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: function(mouse) {
                        console.log("[Taskbar] Clicked on", appButton.appId, "- Active:", appButton.isActive);

                        if (mouse.button === Qt.MiddleButton) {
                            console.log("[Taskbar] Middle-clicked on", appButton.appId);

                            // Example: Close the window with middle click
                            if (modelData && modelData.close) {
                                modelData.close();
                            } else {
                                console.log("[Taskbar] No close method available for:", modelData);
                            }
                        }

                        if (mouse.button === Qt.LeftButton) {
                            // Left click: Focus/activate the window
                            if (modelData && modelData.activate) {
                                modelData.activate();
                            } else {
                                console.log("[Taskbar] No activate method available for:", modelData);
                            }
                        }
                    }

                    // Right-click for additional actions
                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            console.log("[Taskbar] Right-clicked on", appButton.appId);

                            // Example actions you can add:
                            // 1. Close window
                            // if (modelData && modelData.close) {
                            //     modelData.close();
                            // }

                            // 2. Minimize window
                            // if (modelData && modelData.minimize) {
                            //     modelData.minimize();
                            // }

                            // 3. Show context menu (needs Menu component)
                            // contextMenu.popup();
                        }
                    }
                }

                // Active indicator dot
                Rectangle {
                    visible: isActive
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.onAccent
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: -6
                }
            }
        }
    }
}
