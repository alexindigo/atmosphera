import QtQuick
import Quickshell
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import qs.Services
import qs.Settings

ShellRoot {
    property string wallpaperSource: WallpaperManager.currentWallpaper !== "" && !Settings.settings.useSWWW ? WallpaperManager.currentWallpaper : ""

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData

            visible: wallpaperSource !== ""
            anchors {
                top: true
                bottom: true
                right: true
                left: true
            }
            color: "transparent"
            screen: modelData
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell-overview"
            Image {
                id: bgImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: wallpaperSource
                cache: true
                smooth: true
                visible: wallpaperSource !== "" // Show the original for FastBlur input
            }
            FastBlur {
                anchors.fill: parent
                visible: wallpaperSource !== ""
                source: bgImage
                radius: 18 // Adjust blur strength as needed
                transparentBorder: true
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(
                    Theme.backgroundPrimary.r,
                    Theme.backgroundPrimary.g,
                    Theme.backgroundPrimary.b, 0.6)
            }
        }
    }
}