import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 640
  preferredHeight: 480
  preferredWidthRatio: 0.4
  preferredHeightRatio: 0.5
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true
  panelKeyboardFocus: true

  // Local reactive state
  property list<string> wallpapersList: []
  property string currentWallpaper: ""

  function refreshForScreen() {
    const name = Screen.name
    wallpapersList = WallpaperService.getWallpapersList(name)
    currentWallpaper = WallpaperService.getWallpaper(name)
  }

  onOpened: refreshForScreen()

  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      if (screenName === Screen.name) {
        currentWallpaper = WallpaperService.getWallpaper(Screen.name)
      }
    }
    function onWallpaperDirectoryChanged(screenName, directory) {
      if (screenName === Screen.name) {
        refreshForScreen()
      }
    }
    function onWallpaperListChanged(screenName, count) {
      if (screenName === Screen.name) {
        refreshForScreen()
      }
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          icon: "settings-wallpaper-selector"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        NText {
          text: "Wallpaper Selector"
          font.pointSize: Style.fontSizeL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "refresh"
          tooltipText: "Refresh wallpaper list"
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: WallpaperService.refreshWallpapersList()
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close."
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: root.close()
        }
      }

      NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginXL * scaling
        Layout.bottomMargin: Style.marginXL * scaling
      }

      // Scroll container mirrors SettingsPanel to avoid overflow and keep interactions smooth
      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        pressDelay: 200

        NScrollView {
          id: scrollView
          anchors.fill: parent
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          padding: Style.marginL * 0 * scaling
          clip: true

          ColumnLayout {
            width: scrollView.availableWidth
            spacing: Style.marginM * scaling

            // Selector header removed (title and refresh are redundant here)
            NToggle {
              label: "Apply to all monitors"
              description: "Apply selected wallpaper to all monitors at once."
              checked: Settings.data.wallpaper.setWallpaperOnAllMonitors
              onToggled: checked => Settings.data.wallpaper.setWallpaperOnAllMonitors = checked
              visible: (wallpapersList.length > 0)
            }

            // Grid container
            Item {
              visible: !WallpaperService.scanning
              Layout.fillWidth: true
              Layout.preferredHeight: Math.ceil(wallpapersList.length / wallpaperGridView.columns) * wallpaperGridView.cellHeight

              GridView {
                id: wallpaperGridView
                anchors.fill: parent
                model: wallpapersList
                interactive: false
                clip: true

                property int columns: 5
                property int itemSize: Math.floor((width - leftMargin - rightMargin - (columns * Style.marginS * scaling)) / columns)

                cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
                cellHeight: Math.floor(itemSize * 0.67) + Style.marginS * scaling

                leftMargin: Style.marginS * scaling
                rightMargin: Style.marginS * scaling
                topMargin: Style.marginS * scaling
                bottomMargin: Style.marginS * scaling

                delegate: Rectangle {
                  id: wallpaperItem

                  property string wallpaperPath: modelData
                  property bool isSelected: (wallpaperPath === currentWallpaper)

                  width: wallpaperGridView.itemSize
                  height: Math.round(wallpaperGridView.itemSize * 0.67)
                  color: Color.transparent

                  NImageCached {
                    id: img
                    imagePath: wallpaperPath
                    anchors.fill: parent
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: Color.transparent
                    border.color: isSelected ? Color.mSecondary : Color.mSurface
                    border.width: Math.max(1, Style.borderL * 1.5 * scaling)
                  }

                  Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Style.marginS * scaling
                    width: 28 * scaling
                    height: 28 * scaling
                    radius: width / 2
                    color: Color.mSecondary
                    border.color: Color.mOutline
                    border.width: Math.max(1, Style.borderS * scaling)
                    visible: isSelected

                    NIcon {
                      icon: "check"
                      font.pointSize: Style.fontSizeM * scaling
                      font.weight: Style.fontWeightBold
                      color: Color.mOnSecondary
                      anchors.centerIn: parent
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: Color.mSurface
                    opacity: (mouseArea.containsMouse || isSelected) ? 0 : 0.3
                    radius: parent.radius
                    Behavior on opacity {
                      NumberAnimation {
                        duration: Style.animationFast
                      }
                    }
                  }

                  MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    onPressed: {
                      if (Settings.data.wallpaper.setWallpaperOnAllMonitors) {
                        WallpaperService.changeWallpaper(wallpaperPath, undefined)
                      } else {
                        WallpaperService.changeWallpaper(wallpaperPath, Screen.name)
                      }
                    }
                  }
                }
              }
            }

            // Empty / scanning state
            Rectangle {
              color: Color.mSurface
              radius: Style.radiusM * scaling
              border.color: Color.mOutline
              border.width: Math.max(1, Style.borderS * scaling)
              visible: wallpapersList.length === 0 || WallpaperService.scanning
              Layout.fillWidth: true
              Layout.preferredHeight: 130 * scaling

              ColumnLayout {
                anchors.fill: parent
                visible: WallpaperService.scanning
                NBusyIndicator {
                  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                }
              }

              ColumnLayout {
                anchors.fill: parent
                visible: wallpapersList.length === 0 && !WallpaperService.scanning
                Item {
                  Layout.fillHeight: true
                }
                NIcon {
                  icon: "folder-open"
                  font.pointSize: Style.fontSizeXXL * scaling
                  color: Color.mOnSurface
                  Layout.alignment: Qt.AlignHCenter
                }
                NText {
                  text: "No wallpaper found."
                  color: Color.mOnSurface
                  font.weight: Style.fontWeightBold
                  Layout.alignment: Qt.AlignHCenter
                }
                NText {
                  text: "Configure your wallpaper directory with images."
                  color: Color.mOnSurfaceVariant
                  wrapMode: Text.WordWrap
                  Layout.alignment: Qt.AlignHCenter
                }
                Item {
                  Layout.fillHeight: true
                }
              }
            }

            NDivider {
              Layout.fillWidth: true
              Layout.topMargin: Style.marginXL * scaling
              Layout.bottomMargin: Style.marginXL * scaling
            }
          }
        }
      }
    }
  }
}
