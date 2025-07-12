import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import qs.Settings

Rectangle {
    id: wallpaperSettingsCard
    Layout.fillWidth: true
    Layout.preferredHeight: 100
    color: Theme.surface
    radius: 18

    // Property for binding
    property string wallpaperFolder: ""
    signal wallpaperFolderEdited(string folder)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                text: "image"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                color: Theme.accentPrimary
            }
            Text {
                text: "Wallpaper Folder"
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }
        }

        // Folder Path Input
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 8
            color: Theme.surfaceVariant
            border.color: folderInput.activeFocus ? Theme.accentPrimary : Theme.outline
            border.width: 1
            TextInput {
                id: folderInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                text: wallpaperFolder
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textPrimary
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                activeFocusOnTab: true
                inputMethodHints: Qt.ImhUrlCharactersOnly
                onTextChanged: {
                    wallpaperFolderEdited(text)
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: folderInput.forceActiveFocus()
                }
            }
        }
    }
} 