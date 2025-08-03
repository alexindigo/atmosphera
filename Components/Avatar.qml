import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs.Settings

Item {
    anchors.fill: parent

    IconImage {
        id: avatarImage
        anchors.fill: parent
        anchors.margins: 2
        source: "file://" + Settings.settings.profileImage
        visible: false
        asynchronous: true
        backer.fillMode: Image.PreserveAspectCrop
    }

    OpacityMask {
        anchors.fill: avatarImage
        source: avatarImage
        maskSource: Rectangle {
            width: avatarImage.width
            height: avatarImage.height
            radius: avatarImage.width / 2
            visible: false
        }
        visible: Settings.settings.profileImage !== ""
    }

    // Fallback icon
    Text {
        anchors.centerIn: parent
        text: "person"
        font.family: "Material Symbols Outlined"
        font.pixelSize: 24
        color: Theme.onAccent
        visible: Settings.settings.profileImage === undefined || Settings.settings.profileImage === ""
        z: 0
    }
}

