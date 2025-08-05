import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Settings
import qs.Components
import qs.Services

Rectangle {
    id: wallpaperOverlay
    anchors.fill: parent
    color: Theme.backgroundPrimary
    visible: false
    z: 1000

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: {
            wallpaperOverlay.visible = false;
        }
    }

    // Content area that stops event propagation
    MouseArea {
        anchors.fill: parent
        anchors.margins: 24
        onClicked: {
            // Stop event propagation
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Wallpaper Grid
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollView {
                    anchors.fill: parent
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    GridView {
                        id: wallpaperGrid
                        anchors.fill: parent
                        cellWidth: Math.max(120, (parent.width / 3) - 12)
                        cellHeight: cellWidth * 0.6
                        model: WallpaperManager.wallpaperList
                        cacheBuffer: 64
                        leftMargin: 8
                        rightMargin: 8
                        topMargin: 8
                        bottomMargin: 8

                        delegate: Item {
                            width: wallpaperGrid.cellWidth - 8
                            height: wallpaperGrid.cellHeight - 8

                            Rectangle {
                                id: wallpaperItem
                                anchors.fill: parent
                                anchors.margins: 4
                                color: Theme.surface
                                radius: 12
                                border.color: Settings.settings.currentWallpaper === modelData ? Theme.accentPrimary : Theme.outline
                                border.width: 2

                                Image {
                                    id: wallpaperImage
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true

                                    sourceSize.width: Math.min(width, 480)
                                    sourceSize.height: Math.min(height, 270)

                                    opacity: (wallpaperImage.status == Image.Ready) ? 1.0 : 0.0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        WallpaperManager.changeWallpaper(modelData);
                                        wallpaperOverlay.visible = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Function to show the overlay and load wallpapers
    function show() {
        // Ensure wallpapers are loaded
        WallpaperManager.loadWallpapers();
        wallpaperOverlay.visible = true;
    }
} 