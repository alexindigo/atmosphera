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

  implicitWidth: 200 * scaling

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(Screen.height * 0.9, flickable.contentHeight + (Style.marginM * 2 * scaling))
  visible: false
  color: Color.transparent
  anchor.item: anchorItem
  anchor.rect.x: anchorX
  anchor.rect.y: anchorY - (isSubMenu ? 0 : 4)

  function showAt(item, x, y) {
    if (!item) {
      Logger.warn("TrayMenu", "anchorItem is undefined, won't show menu.")
      return
    }

    if (!opener.children || opener.children.values.length === 0) {
      //Logger.warn("TrayMenu", "Menu not ready, delaying show")
      Qt.callLater(() => showAt(item, x, y))
      return
    }

    anchorItem = item
    anchorX = x
    anchorY = y

    visible = true
    forceActiveFocus()

    // Force update after showing. This should now be more reliable.
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
    border.width: Math.max(1, Style.borderS * scaling)
    radius: Style.radiusM * scaling
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS * scaling
    contentHeight: columnLayout.implicitHeight
    interactive: true
    clip: true

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
              return 8 * scaling
            } else {
              // Calculate based on text content
              const textHeight = text.contentHeight || (Style.fontSizeS * scaling * 1.2)
              return Math.max(28 * scaling, textHeight + (Style.marginS * 2 * scaling))
            }
          }

          color: Color.transparent
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - (Style.marginM * scaling * 2)
            color: Color.mPrimary
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mTertiary : Color.transparent
            radius: Style.radiusS * scaling
            visible: !(modelData?.isSeparator ?? false)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM * scaling
              anchors.rightMargin: Style.marginM * scaling
              spacing: Style.marginS * scaling

              NText {
                id: text
                Layout.fillWidth: true
                color: (modelData?.enabled
                        ?? true) ? (mouseArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface) : Color.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text : "..."
                font.pointSize: Style.fontSizeS * scaling
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
              }

              Image {
                Layout.preferredWidth: Style.marginL * scaling
                Layout.preferredHeight: Style.marginL * scaling
                source: modelData?.icon ?? ""
                visible: (modelData?.icon ?? "") !== ""
                fillMode: Image.PreserveAspectFit
              }

              NIcon {
                text: modelData?.hasChildren ? "menu" : ""
                font.pointSize: Style.fontSizeS * scaling
                verticalAlignment: Text.AlignVCenter
                visible: modelData?.hasChildren ?? false
                color: Color.mOnSurface
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

                  const globalPos = entry.mapToGlobal(0, 0)
                  const submenuWidth = Style.baseWidgetSize * 5.625 * scaling
                  const gap = 12 * scaling
                  const openLeft = (globalPos.x + entry.width + submenuWidth > Screen.width)
                  const anchorX = openLeft ? -submenuWidth - gap : entry.width + gap

                  // Create submenu
                  entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                    "menu": modelData,
                                                                                    "anchorItem": entry,
                                                                                    "anchorX": anchorX,
                                                                                    "anchorY": 0,
                                                                                    "isSubMenu": true
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
    }
  }
}
