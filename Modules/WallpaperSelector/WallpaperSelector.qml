import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets
import "../../Helpers/FuzzySort.js" as FuzzySort

NPanel {
  id: root

  preferredWidth: 640
  preferredHeight: 480
  preferredWidthRatio: 0.4
  preferredHeightRatio: 0.52
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true
  panelKeyboardFocus: true
  draggable: true

  panelContent: Rectangle {
    // Local reactive state
    property list<string> wallpapersList: []
    property string currentWallpaper: ""
    property string filterText: ""
    property list<string> filteredWallpapers: []

    Component.onCompleted: {
      refreshWallpaperScreenData()
    }

    Connections {
      target: WallpaperService
      function onWallpaperChanged(screenName, path) {
        if (screen !== null && screenName === screen.name) {
          currentWallpaper = WallpaperService.getWallpaper(screen.name)
        }
      }
      function onWallpaperDirectoryChanged(screenName, directory) {
        if (screen !== null && screenName === screen.name) {
          refreshWallpaperScreenData()
        }
      }
      function onWallpaperListChanged(screenName, count) {
        if (screen !== null && screenName === screen.name) {
          refreshWallpaperScreenData()
        }
      }
    }

    function refreshWallpaperScreenData() {
      if (screen === null) {
        return
      }
      wallpapersList = WallpaperService.getWallpapersList(screen.name)
      currentWallpaper = WallpaperService.getWallpaper(screen.name)
      updateFiltered()
    }

    function updateFiltered() {
      if (!filterText || filterText.trim().length === 0) {
        filteredWallpapers = wallpapersList
        return
      }
      // Build objects with basename for ranking
      const items = wallpapersList.map(function (p) {
        return {
          "path": p,
          "name": p.split('/').pop()
        }
      })
      const results = FuzzySort.go(filterText.trim(), items, {
                                     "key": 'name',
                                     "limit": 200
                                   })
      // Map back to path list
      filteredWallpapers = results.map(function (r) {
        return r.obj.path
      })
    }

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
          tooltipText: "Refresh wallpaper list."
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
      }

      NToggle {
        label: "Apply to all monitors"
        description: "Apply selected wallpaper to all monitors at once."
        checked: Settings.data.wallpaper.setWallpaperOnAllMonitors
        onToggled: checked => Settings.data.wallpaper.setWallpaperOnAllMonitors = checked
        visible: (wallpapersList.length > 0)
        Layout.fillWidth: true
      }

      // Filter input
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NText {
          text: "Search:"
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeM * scaling
          Layout.preferredWidth: implicitWidth
        }

        NTextInput {
          id: searchInput
          placeholderText: "Type to filter wallpapers..."
          text: filterText
          onTextChanged: {
            filterText = text
            updateFiltered()
          }
          Layout.fillWidth: true
          Component.onCompleted: {
            if (searchInput.inputItem && searchInput.inputItem.visible) {
              searchInput.inputItem.forceActiveFocus()
            }
          }
        }
      }

      // Scroll container for wallpaper grid only
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

            // Grid container
            Item {
              visible: !WallpaperService.scanning
              Layout.fillWidth: true
              Layout.preferredHeight: Math.ceil(filteredWallpapers.length / wallpaperGridView.columns) * wallpaperGridView.cellHeight

              GridView {
                id: wallpaperGridView
                anchors.fill: parent
                model: filteredWallpapers
                interactive: false

                property int columns: 4
                property int itemSize: Math.floor((width - leftMargin - rightMargin - (columns * Style.marginS * scaling)) / columns)

                cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
                cellHeight: Math.floor(itemSize * 0.7) + Style.marginXS * scaling + Style.fontSizeXS * scaling + Style.marginM * scaling

                leftMargin: Style.marginS * scaling
                rightMargin: Style.marginS * scaling
                topMargin: Style.marginS * scaling
                bottomMargin: Style.marginS * scaling

                delegate: ColumnLayout {
                  id: wallpaperItem

                  property string wallpaperPath: modelData
                  property bool isSelected: (wallpaperPath === currentWallpaper)
                  property string filename: wallpaperPath.split('/').pop()

                  width: wallpaperGridView.itemSize
                  spacing: Style.marginXS * scaling

                  Rectangle {
                    id: imageContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(wallpaperGridView.itemSize * 0.67)
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

                  NText {
                    text: filename
                    color: Color.mOnSurfaceVariant
                    opacity: 0.5
                    font.pointSize: Style.fontSizeXS * scaling
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.marginS * scaling
                    Layout.rightMargin: Style.marginS * scaling
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
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
              visible: (filteredWallpapers.length === 0 && !WallpaperService.scanning) || WallpaperService.scanning
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
                visible: filteredWallpapers.length === 0 && !WallpaperService.scanning
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
                  text: (filterText && filterText.length > 0) ? "No match found." : "No wallpaper found."
                  color: Color.mOnSurface
                  font.weight: Style.fontWeightBold
                  Layout.alignment: Qt.AlignHCenter
                }
                NText {
                  text: (filterText && filterText.length > 0) ? "Try a different search query." : "Configure your wallpaper directory with images."
                  color: Color.mOnSurfaceVariant
                  wrapMode: Text.WordWrap
                  Layout.alignment: Qt.AlignHCenter
                }
                Item {
                  Layout.fillHeight: true
                }
              }
            }
          }
        }
      }
    }
  }
}
