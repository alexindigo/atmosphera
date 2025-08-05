import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Settings
import qs.Widgets.SettingsWindow.Tabs

PanelWindow {
    id: panelMain
    implicitHeight: screen.height / 2
    implicitWidth: screen.width / 2
    color: "transparent"

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand


    Component {
        id: generalSettings
        General {}
    }

    Component {
        id: barSettings
        Bar {}
    }

    Component {
        id: timeWeatherSettings
        TimeWeather {}
    }

    Component {
        id: recordingSettings
        Recording {}
    }

    Component {
        id: networkSettings
        Network {}
    }

    Component {
        id: miscSettings
        Misc {}
    }

    Component {
        id: aboutSettings
        About {}
    }

    Component {
        id: displaySettings
        Display {}
    }


    Rectangle {
        id: background
        color: Theme.backgroundPrimary
        anchors.fill: parent
        radius: 20
        border.color: Theme.outline
        border.width: 1

        MultiEffect {
            source: background
            anchors.fill: background
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.3
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 2
            shadowBlur: 12
        }
    }


    Rectangle {
        id: settings
        color: Theme.backgroundTertiary
        anchors {
            left: tabs.right
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            margins: 12
        }
        topRightRadius: 20
        bottomRightRadius: 20


        Rectangle {
            id: headerArea
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            height: 48
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: 12

    
                Text {
                    id: tabName
                    text: "General"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.fillWidth: true
                }


                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                        font.pixelSize: 18
                        color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                    }

                    MouseArea {
                        id: closeButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panelMain.visible = false
                    }
                }
            }
        }


        Rectangle {
            anchors {
                top: headerArea.bottom
                left: parent.left
                right: parent.right
                margins: 16
            }
            height: 1
            color: Theme.outline
            opacity: 0.3
        }

        Item {
            id: settingsContainer
            anchors {
                top: headerArea.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 24
                topMargin: 32
            }

    
            Loader {
                id: settingsLoader
                anchors.fill: parent
                sourceComponent: generalSettings
                opacity: 1
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.InOutQuad
                    }
                }
            }

    
            Loader {
                id: settingsLoader2
                anchors.fill: parent
                opacity: 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    
    Rectangle {
        id: tabs
        color: Theme.surface
        width: screen.width / 9
        height: panelMain.height
        topLeftRadius: 20
        bottomLeftRadius: 20
        border.color: Theme.outline
        border.width: 1

        Column {
            width: parent.width
            spacing: 0
            topPadding: 8

            Repeater {
                id: repeater
                model: [
                    { icon: "tune", text: "General" },
                    { icon: "space_dashboard", text: "Bar" },
                    { icon: "schedule", text: "Time & Weather" },
                    { icon: "photo_camera", text: "Recording" },
                    { icon: "wifi", text: "Network" },
                    { icon: "monitor", text: "Display" },
                    { icon: "settings_suggest", text: "Misc" },
                    { icon: "info", text: "About" }
                ]

                delegate: Column {
                    width: tabs.width
                    height: 40

                    Item {
                        width: parent.width
                        height: 39

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                
                            Rectangle {
                                id: activeIndicator
                                Layout.leftMargin: 8
                                Layout.preferredWidth: 3
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                radius: 2
                                color: Theme.accentPrimary
                                opacity: index === 0 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                
                            Label {
                                id: icon
                                text: modelData.icon
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 24
                                color: index === 0 ? Theme.accentPrimary : Theme.textPrimary
                                opacity: index === 0 ? 1 : 0.8
                                Layout.leftMargin: 20
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                
                            Label {
                                id: label
                                text: modelData.text
                                font.pixelSize: 12
                                color: index === 0 ? Theme.accentPrimary : Theme.textSecondary
                                font.weight: index === 0 ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                Layout.leftMargin: 4
                                Layout.rightMargin: 16
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                                onClicked: {
                        
                                    const newComponent = {
                                        0: generalSettings,
                                        1: barSettings,
                                        2: timeWeatherSettings,
                                        3: recordingSettings,
                                        4: networkSettings,
                                        5: displaySettings,
                                        6: miscSettings,
                                        7: aboutSettings
                                    }[index];

                        
                                    const tabNames = [
                                        "General",
                                        "Bar",
                                        "Time & Weather", 
                                        "Recording",
                                        "Network",
                                        "Display",
                                        "Misc",
                                        "About"
                                    ];
                                    tabName.text = tabNames[index];

                        
                                    if (settingsLoader.opacity === 1) {
                            
                                        settingsLoader2.sourceComponent = newComponent;
                                        settingsLoader.opacity = 0;
                                        settingsLoader2.opacity = 1;
                                    } else {
                            
                                        settingsLoader.sourceComponent = newComponent;
                                        settingsLoader2.opacity = 0;
                                        settingsLoader.opacity = 1;
                                    }

                        
                                    for (let i = 0; i < repeater.count; i++) {
                                        let item = repeater.itemAt(i);
                                        if (item) {
                                
                                            let containerItem = item.children[0];
                                
                                            let rowLayout = containerItem.children[0];
                                
                                            let indicator = rowLayout.children[0];
                                            let icon = rowLayout.children[1];
                                            let label = rowLayout.children[2];
                                            
                                            indicator.opacity = i === index ? 1 : 0;
                                            icon.color = i === index ? Theme.accentPrimary : Theme.textPrimary;
                                            icon.opacity = i === index ? 1 : 0.8;
                                            label.color = i === index ? Theme.accentPrimary : Theme.textSecondary;
                                            label.font.weight = i === index ? Font.Bold : Font.Normal;
                                        }
                                    }
                                }
                            }
                        }

                
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outline
                        opacity: 0.6
                        visible: index < (repeater.count - 1)
                    }
                }
            }
        }
    }
}