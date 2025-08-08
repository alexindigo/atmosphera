import QtQuick
import QtQuick.Controls
import qs.Settings

// Reusable themed slider styled like the sliders in Wallpaper.qml
Slider {
    id: slider

    // Optional monitor screen for scaling context
    property var screen
    // Convenience flag mirroring Wallpaper sliders
    property bool snapAlways: true

    snapMode: snapAlways ? Slider.SnapAlways : Slider.SnapOnRelease

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        implicitWidth: 200
        implicitHeight: 4 * Theme.scale(screen)
        width: slider.availableWidth
        height: implicitHeight
        radius: height / 2
        color: Theme.surfaceVariant

        Rectangle {
            width: slider.visualPosition * parent.width
            height: parent.height
            color: Theme.accentPrimary
            radius: parent.radius
        }
    }

    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        implicitWidth: 20 * Theme.scale(screen)
        implicitHeight: 20 * Theme.scale(screen)
        radius: width / 2
        color: slider.pressed ? Theme.surfaceVariant : Theme.surface
        border.color: Theme.accentPrimary
        border.width: 2 * Theme.scale(screen)
    }
}

