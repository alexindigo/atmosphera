import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import qs.Bar.Modules
import qs.Settings
import qs.Services
import qs.Components
import qs.Widgets
import qs.Widgets.Sidebar
import qs.Widgets.Sidebar.Panel
import qs.Helpers
import QtQuick.Controls

Scope {
    id: rootScope
    property var shell

    Item {
        id: barRootItem
        anchors.fill: parent

        Variants {
            model: Quickshell.screens

            Item {
                property var modelData

                PanelWindow {
                    id: panel
                    screen: modelData
                    color: "transparent"
                    implicitHeight: barBackground.height + 24
                    anchors.top: true
                    anchors.left: true
                    anchors.right: true

                    visible: true

                    property string lastFocusedWindowTitle: ""
                    property bool activeWindowVisible: false
                    property string displayedWindowTitle: ""

                    onLastFocusedWindowTitleChanged: {
                        displayedWindowTitle = (lastFocusedWindowTitle === "(No active window)") ? "" : lastFocusedWindowTitle
                    }

                    Timer {
                        id: hideTimer
                        interval: 4000
                        repeat: false
                        onTriggered: panel.activeWindowVisible = false
                    }

                    Connections {
                        target: Niri
                        function onFocusedWindowTitleChanged() {
                            var newTitle = Niri.focusedWindowTitle

                            if (newTitle !== panel.lastFocusedWindowTitle) {
                                panel.lastFocusedWindowTitle = newTitle

                                if (newTitle === "(No active window)") {
                                    panel.activeWindowVisible = false
                                    hideTimer.stop()
                                } else {
                                    panel.activeWindowVisible = true
                                    hideTimer.restart()
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: barBackground
                        width: parent.width
                        height: 36
                        color: Theme.backgroundPrimary
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }

                    Row {
                        id: leftWidgetsRow
                        anchors.verticalCenter: barBackground.verticalCenter
                        anchors.left: barBackground.left
                        anchors.leftMargin: 18
                        spacing: 12

                        SystemInfo {
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Media {
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    ActiveWindow {}

                    Workspace {
                        id: workspace
                        screen: modelData
                        anchors.horizontalCenter: barBackground.horizontalCenter
                        anchors.verticalCenter: barBackground.verticalCenter
                    }

                    Row {
                        id: rightWidgetsRow
                        anchors.verticalCenter: barBackground.verticalCenter
                        anchors.right: barBackground.right
                        anchors.rightMargin: 18
                        spacing: 12

                        Brightness {
                            id: widgetsBrightness
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Volume {
                            id: widgetsVolume
                            shell: rootScope.shell
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        SystemTray {
                            id: systemTrayModule
                            shell: rootScope.shell
                            anchors.verticalCenter: parent.verticalCenter
                            bar: panel
                            trayMenu: externalTrayMenu
                        }

                        CustomTrayMenu {
                            id: externalTrayMenu
                        }

                        ClockWidget {
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        PanelPopup {
                            id: sidebarPopup
                        }

                        Button {
                            barBackground: barBackground
                            anchors.verticalCenter: parent.verticalCenter
                            screen: modelData
                            sidebarPopup: sidebarPopup
                        }
                    }

                    Corners {
                        id: topleftCorner
                        position: "bottomleft"
                        size: 1.3
                        fillColor: (Theme.backgroundPrimary !== undefined && Theme.backgroundPrimary !== null) ? Theme.backgroundPrimary : "#222"
                        offsetX: -39
                        offsetY: 0
                        anchors.top: barBackground.bottom
                    }

                    Corners {
                        id: toprightCorner
                        position: "bottomright"
                        size: 1.3
                        fillColor: (Theme.backgroundPrimary !== undefined && Theme.backgroundPrimary !== null) ? Theme.backgroundPrimary : "#222"
                        offsetX: 39
                        offsetY: 0
                        anchors.top: barBackground.bottom
                    }

                    Background {}
                    Overview {}
                }
            }
        }
    }

    // This alias exposes the visual bar's visibility to the outside world
    property alias visible: barRootItem.visible
}
