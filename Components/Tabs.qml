import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import qs.Settings

Item {
    id: root
    property var tabsModel: [] // [{icon: "videocam", label: "Video"}, ...]
    property int currentIndex: 0
    signal tabChanged(int index)

    RowLayout {
        id: tabBar
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16

        Repeater {
            model: root.tabsModel
            delegate: Column {
                width: 56
                spacing: 2
                property bool hovered: false

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.currentIndex !== index) {
                            root.currentIndex = index;
                            root.tabChanged(index);
                        }
                    }
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                }

                // Icon
                Text {
                    text: modelData.icon
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 22
                    color: index === root.currentIndex
                        ? (Theme ? Theme.accentPrimary : "#7C3AED")
                        : parent.hovered
                            ? (Theme ? Theme.accentPrimary : "#7C3AED")
                            : (Theme ? Theme.textSecondary : "#444")
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Label
                Text {
                    text: modelData.label
                    font.pixelSize: 12
                    font.bold: index === root.currentIndex
                    color: index === root.currentIndex
                        ? (Theme ? Theme.accentPrimary : "#7C3AED")
                        : parent.hovered
                            ? (Theme ? Theme.accentPrimary : "#7C3AED")
                            : (Theme ? Theme.textSecondary : "#444")
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Underline for active tab
                Rectangle {
                    width: 24
                    height: 2
                    radius: 1
                    color: index === root.currentIndex
                        ? (Theme ? Theme.accentPrimary : "#7C3AED")
                        : "transparent"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
} 