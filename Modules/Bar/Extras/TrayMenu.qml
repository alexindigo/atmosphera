import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

PopupWindow {
  id: root
  property QsMenuHandle menu
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property bool isHovered: rootMouseArea.containsMouse
  property ShellScreen screen
  // Properties for adding tray item to favorites
  property var trayItem: null
  property string widgetSection: ""
  property int widgetIndex: -1

  readonly property int menuWidth: 240

  implicitWidth: menuWidth

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(screen ? screen.height * 0.9 : Screen.height * 0.9, flickable.contentHeight + (Style.marginS * 2))
  visible: false
  color: Color.transparent
  anchor.item: anchorItem
  anchor.rect.x: anchorX
  anchor.rect.y: anchorY - (isSubMenu ? 0 : 4)

  function showAt(item, x, y) {
    if (!item) {
      Logger.w("TrayMenu", "anchorItem is undefined, won't show menu.")
      return
    }

    if (!opener.children || opener.children.values.length === 0) {
      //Logger.w("TrayMenu", "Menu not ready, delaying show")
      Qt.callLater(() => showAt(item, x, y))
      return
    }

    anchorItem = item
    anchorX = x
    anchorY = y

    visible = true
    forceActiveFocus()

    // Force update after showing.
    Qt.callLater(() => {
                   root.anchor.updateAnchor()
                 })
  }

  function hideMenu() {
    visible = false

    // Clean up all submenus recursively
    for (var i = 0; i < columnLayout.children.length; i++) {
      const child = columnLayout.children[i]
      if (child?.subMenu) {
        child.subMenu.hideMenu()
        child.subMenu.destroy()
        child.subMenu = null
      }
    }
  }

  // Full-sized, transparent MouseArea to track the mouse.
  MouseArea {
    id: rootMouseArea
    anchors.fill: parent
    hoverEnabled: true
  }

  Item {
    anchors.fill: parent
    Keys.onEscapePressed: root.hideMenu()
  }

  QsMenuOpener {
    id: opener
    menu: root.menu
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Style.borderS
    radius: Style.radiusM
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true

    // Use a ColumnLayout to handle menu item arrangement
    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        model: opener.children ? [...opener.children.values] : []

        delegate: Rectangle {
          id: entry
          required property var modelData

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: {
            if (modelData?.isSeparator) {
              return 8
            } else {
              return 28
            }
          }

          color: Color.transparent
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - (Style.marginM * 2)
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mHover : Color.transparent
            radius: Style.radiusS
            visible: !(modelData?.isSeparator ?? false)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginS

              NText {
                id: text
                Layout.fillWidth: true
                color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface) : Color.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                pointSize: Style.fontSizeS
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              Image {
                Layout.preferredWidth: Style.marginL
                Layout.preferredHeight: Style.marginL
                source: modelData?.icon ?? ""
                visible: (modelData?.icon ?? "") !== ""
                fillMode: Image.PreserveAspectFit
              }

              NIcon {
                icon: modelData?.hasChildren ? "menu" : ""
                pointSize: Style.fontSizeS
                applyUiScale: false
                verticalAlignment: Text.AlignVCenter
                visible: modelData?.hasChildren ?? false
                color: (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false) && root.visible

              onClicked: {
                if (modelData && !modelData.isSeparator && !modelData.hasChildren) {
                  modelData.triggered()
                  root.hideMenu()
                }
              }

              onEntered: {
                if (!root.visible)
                  return

                // Close all sibling submenus
                for (var i = 0; i < columnLayout.children.length; i++) {
                  const sibling = columnLayout.children[i]
                  if (sibling !== entry && sibling?.subMenu) {
                    sibling.subMenu.hideMenu()
                    sibling.subMenu.destroy()
                    sibling.subMenu = null
                  }
                }

                // Create submenu if needed
                if (modelData?.hasChildren) {
                  if (entry.subMenu) {
                    entry.subMenu.hideMenu()
                    entry.subMenu.destroy()
                  }

                  // Need a slight overlap so that menu don't close when moving the mouse to a submenu
                  const submenuWidth = menuWidth // Assuming a similar width as the parent
                  const overlap = 4 // A small overlap to bridge the mouse path

                  // Determine submenu opening direction based on bar position and available space
                  let openLeft = false

                  // Check bar position first
                  const barPosition = Settings.data.bar.position
                  const globalPos = entry.mapToItem(null, 0, 0)

                  if (barPosition === "right") {
                    // Bar is on the right, prefer opening submenus to the left
                    openLeft = true
                  } else if (barPosition === "left") {
                    // Bar is on the left, prefer opening submenus to the right
                    openLeft = false
                  } else {
                    // Bar is horizontal (top/bottom) or undefined, use space-based logic
                    openLeft = (globalPos.x + entry.width + submenuWidth > screen.width)

                    // Secondary check: ensure we don't open off-screen
                    if (openLeft && globalPos.x - submenuWidth < 0) {
                      // Would open off the left edge, force right opening
                      openLeft = false
                    } else if (!openLeft && globalPos.x + entry.width + submenuWidth > screen.width) {
                      // Would open off the right edge, force left opening
                      openLeft = true
                    }
                  }

                  // Position with overlap
                  const anchorX = openLeft ? -submenuWidth + overlap : entry.width - overlap

                  // Create submenu
                  entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                    "menu": modelData,
                                                                                    "anchorItem": entry,
                                                                                    "anchorX": anchorX,
                                                                                    "anchorY": 0,
                                                                                    "isSubMenu": true,
                                                                                    "screen": screen
                                                                                  })

                  if (entry.subMenu) {
                    entry.subMenu.showAt(entry, anchorX, 0)
                  }
                }
              }

              onExited: {
                Qt.callLater(() => {
                               if (entry.subMenu && !entry.subMenu.isHovered) {
                                 entry.subMenu.hideMenu()
                                 entry.subMenu.destroy()
                                 entry.subMenu = null
                               }
                             })
              }
            }
          }

          Component.onDestruction: {
            if (subMenu) {
              subMenu.destroy()
              subMenu = null
            }
          }
        }
      }

      // Separator before custom menu item
      Rectangle {
        visible: !root.isSubMenu && root.trayItem !== null && root.widgetSection !== "" && root.widgetIndex >= 0
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: visible ? 8 : 0
        color: Color.transparent

        NDivider {
          anchors.centerIn: parent
          width: parent.width - (Style.marginM * 2)
          visible: parent.visible
        }
      }

      // Custom "Add/Remove Favorite" menu item (only for non-submenus with tray item info)
      Rectangle {
        id: addToFavoriteEntry
        visible: !root.isSubMenu && root.trayItem !== null && root.widgetSection !== "" && root.widgetIndex >= 0
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: visible ? 28 : 0
        color: Color.transparent

        // Check if item is already a favorite
        readonly property bool isFavorite: {
          if (!root.trayItem || root.widgetSection === "" || root.widgetIndex < 0) return false
          const itemName = root.trayItem.tooltipTitle || root.trayItem.name || root.trayItem.id || ""
          if (!itemName) return false
          
          var widgets = Settings.data.bar.widgets[root.widgetSection]
          if (!widgets || root.widgetIndex >= widgets.length) return false
          var widgetSettings = widgets[root.widgetIndex]
          if (!widgetSettings || widgetSettings.id !== "Tray") return false
          
          var favorites = widgetSettings.favorites || []
          for (var i = 0; i < favorites.length; i++) {
            if (favorites[i] === itemName) return true
          }
          return false
        }

        Rectangle {
          anchors.fill: parent
          color: addToFavoriteMouseArea.containsMouse ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mPrimary, 0.08)
          radius: Style.radiusS
          border.color: Qt.alpha(Color.mPrimary, addToFavoriteMouseArea.containsMouse ? 0.4 : 0.2)
          border.width: Style.borderS

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.marginM
            anchors.rightMargin: Style.marginM
            spacing: Style.marginS

            NIcon {
              icon: addToFavoriteEntry.isFavorite ? "star" : "star-outline"
              pointSize: Style.fontSizeS
              applyUiScale: false
              verticalAlignment: Text.AlignVCenter
              color: Color.mPrimary
            }

            NText {
              Layout.fillWidth: true
              color: Color.mPrimary
              text: addToFavoriteEntry.isFavorite ? I18n.tr("settings.bar.tray.remove-from-favorites") : I18n.tr("settings.bar.tray.add-as-favorite")
              pointSize: Style.fontSizeS
              font.weight: Font.Medium
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: addToFavoriteMouseArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.visible

            onClicked: {
              if (addToFavoriteEntry.isFavorite) {
                root.removeFromFavorites()
              } else {
                root.addToFavorites()
              }
              root.hideMenu()
            }
          }
        }
      }
    }
  }

  function addToFavorites() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot add as favorite: missing tray item or widget info")
      return
    }

    // Get the tray item name
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot add as favorite: tray item has no name")
      return
    }

    // Get current widget settings
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot add as favorite: invalid widget index")
      return
    }

    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot add as favorite: widget is not a Tray widget")
      return
    }

    // Get current favorites list
    var favorites = widgetSettings.favorites || []

    // Add to favorites
    var newFavorites = favorites.slice()
    newFavorites.push(itemName)

    // Update widget settings
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.favorites = newFavorites

    // Update settings
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()

    Logger.i("TrayMenu", "Added", itemName, "as favorite")
  }

  function removeFromFavorites() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot remove from favorites: missing tray item or widget info")
      return
    }

    // Get the tray item name
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot remove from favorites: tray item has no name")
      return
    }

    // Get current widget settings
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot remove from favorites: invalid widget index")
      return
    }

    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot remove from favorites: widget is not a Tray widget")
      return
    }

    // Get current favorites list
    var favorites = widgetSettings.favorites || []

    // Remove from favorites
    var newFavorites = []
    for (var i = 0; i < favorites.length; i++) {
      if (favorites[i] !== itemName) {
        newFavorites.push(favorites[i])
      }
    }

    // Update widget settings
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.favorites = newFavorites

    // Update settings
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()

    Logger.i("TrayMenu", "Removed", itemName, "from favorites")
  }
}
