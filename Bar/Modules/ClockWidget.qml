import QtQuick
import qs.Settings

Rectangle {
    width: textItem.paintedWidth
    height: textItem.paintedHeight
    color: "transparent"

    Text {
        id: textItem
        text: Time.time
        font.family: Theme.fontFamily
        font.weight: Font.Bold
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
