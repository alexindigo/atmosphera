import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  objectName: "trayMenu"

  panelWidth: 180 * scaling
  panelHeight: 220 * scaling
  panelAnchorRight: true

  property QsMenuHandle menu
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property bool isHovered: false

  function showAt(item, x, y) {
    if (!item) {
      Logger.warn("TrayMenu", "anchorItem is undefined, won't show menu.")
      return
    }

    anchorItem = item
    anchorX = x
    anchorY = y

    // Use NPanel's open method instead of PopupWindow's visible
    open(screen)
  }

  function hideMenu() {
    close()

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

  panelContent: Rectangle {
    color: Color.transparent
    anchors.fill: parent
    anchors.margins: Style.marginS * scaling

    // Full-sized, transparent MouseArea to track the mouse.
    MouseArea {
      id: rootMouseArea
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.isHovered = true
      onExited: root.isHovered = false
    }

    QsMenuOpener {
      id: opener
      menu: root.menu
    }

    Component.onCompleted: {
      if (menu && opener.children && opener.children.values.length === 0) {
        // Menu not ready, try again later
        Qt.callLater(() => {
                       if (opener.children && opener.children.values.length > 0) {
                         // Menu is now ready
                         root.menuItemCount = opener.children.values.length
                       }
                     })
      } else if (opener.children && opener.children.values.length > 0) {
        root.menuItemCount = opener.children.values.length
      }
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
                  text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
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

                    // Create submenu using the same TrayMenu component
                    entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                      "menu": modelData,
                                                                                      "anchorItem": entry,
                                                                                      "anchorX": entry.width,
                                                                                      "anchorY": 0,
                                                                                      "isSubMenu": true
                                                                                    })

                    if (entry.subMenu) {
                      entry.subMenu.open(screen)
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
}
