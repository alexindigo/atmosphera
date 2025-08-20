import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

import "../../Helpers/FuzzySort.js" as Fuzzysort

NPanel {
  id: root
  panelWidth: Math.min(700 * scaling, screen?.width * 0.75)
  panelHeight: Math.min(550 * scaling, screen?.height * 0.8)
  panelAnchorCentered: true

  // Import modular components
  Calculator {
    id: calculator
  }

  ClipboardHistory {
    id: clipboardHistory
  }

  // Properties
  property var desktopEntries: DesktopEntries.applications.values
  property string searchText: ""
  property int selectedIndex: 0

  // Refresh clipboard when user starts typing clipboard commands
  onSearchTextChanged: {
    if (searchText.startsWith(">clip")) {
      clipboardHistory.refresh()
    }
  }

  // Main filtering logic
  property var filteredEntries: {
    Logger.log("AppLauncher", "Total desktop entries:", desktopEntries ? desktopEntries.length : 0)
    if (!desktopEntries || desktopEntries.length === 0) {
      Logger.log("AppLauncher", "No desktop entries available")
      return []
    }

    // Filter out entries that shouldn't be displayed
    var visibleEntries = desktopEntries.filter(entry => {
                                                 if (!entry || entry.noDisplay) {
                                                   return false
                                                 }
                                                 return true
                                               })

    Logger.log("AppLauncher", "Visible entries:", visibleEntries.length)

    var query = searchText ? searchText.toLowerCase() : ""
    var results = []

    // Handle special commands
    if (query === ">") {
      results.push({
                     "isCommand": true,
                     "name": ">calc",
                     "content": "Calculator - evaluate mathematical expressions",
                     "icon": "calculate",
                     "execute": executeCalcCommand
                   })

      results.push({
                     "isCommand": true,
                     "name": ">clip",
                     "content": "Clipboard history - browse and restore clipboard items",
                     "icon": "content_paste",
                     "execute": executeClipCommand
                   })

      return results
    }

    // Handle clipboard history
    if (query.startsWith(">clip")) {
      return clipboardHistory.processQuery(query)
    }

    // Handle calculator
    if (query.startsWith(">calc")) {
      return calculator.processQuery(query, "calc")
    }

    // Handle direct math expressions after ">"
    if (query.startsWith(">") && query.length > 1 && !query.startsWith(">clip") && !query.startsWith(">calc")) {
      const mathResults = calculator.processQuery(query, "direct")
      if (mathResults.length > 0) {
        return mathResults
      }
      // If math evaluation fails, fall through to regular search
    }

    // Regular app search
    if (!query) {
      results = results.concat(visibleEntries.sort(function (a, b) {
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
      }))
    } else {
      var fuzzyResults = Fuzzysort.go(query, visibleEntries, {
                                        "keys": ["name", "comment", "genericName"]
                                      })
      results = results.concat(fuzzyResults.map(function (r) {
        return r.obj
      }))
    }

    Logger.log("AppLauncher", "Filtered entries:", results.length)
    return results
  }

  // Command execution functions
  function executeCalcCommand() {
    searchText = ">calc "
    searchInput.cursorPosition = searchText.length
  }

  function executeClipCommand() {
    searchText = ">clip "
    searchInput.cursorPosition = searchText.length
  }

  // Navigation functions
  function selectNext() {
    if (filteredEntries.length > 0) {
      selectedIndex = Math.min(selectedIndex + 1, filteredEntries.length - 1)
    }
  }

  function selectPrev() {
    if (filteredEntries.length > 0) {
      selectedIndex = Math.max(selectedIndex - 1, 0)
    }
  }

  function activateSelected() {
    if (filteredEntries.length === 0)
      return

    var modelData = filteredEntries[selectedIndex]
    if (modelData && modelData.execute) {
      if (modelData.isCommand) {
        modelData.execute()
        return
      } else {
        modelData.execute()
      }
      root.close()
    }
  }

  Component.onCompleted: {
    Logger.log("AppLauncher", "Component completed")
    Logger.log("AppLauncher", "DesktopEntries available:", typeof DesktopEntries !== 'undefined')
    if (typeof DesktopEntries !== 'undefined') {
      Logger.log("AppLauncher", "DesktopEntries.entries:",
                 DesktopEntries.entries ? DesktopEntries.entries.length : 'undefined')
    }
    // Start clipboard refresh immediately on open
    clipboardHistory.refresh()
  }

  // Main content container
  panelContent: Rectangle {

    // Subtle gradient background
    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: Qt.lighter(Color.mSurface, 1.02)
      }
      GradientStop {
        position: 1.0
        color: Qt.darker(Color.mSurface, 1.1)
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Search bar
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        Layout.bottomMargin: Style.marginM * scaling
        radius: Style.radiusM * scaling
        color: Color.mSurface
        border.color: searchInput.activeFocus ? Color.mPrimary : Color.mOutline
        border.width: Math.max(1, searchInput.activeFocus ? Style.borderM * scaling : Style.borderS * scaling)

        Item {
          anchors.fill: parent
          anchors.margins: Style.marginM * scaling

          NIcon {
            id: searchIcon
            text: "search"
            font.pointSize: Style.fontSizeXL * scaling
            color: searchInput.activeFocus ? Color.mPrimary : Color.mOnSurface
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          TextField {
            id: searchInput
            placeholderText: searchText === "" ? "Search applications... (use > to view commands)" : "Search applications..."
            color: Color.mOnSurface
            placeholderTextColor: Color.mOnSurfaceVariant
            background: null
            font.pointSize: Style.fontSizeL * scaling
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.marginS * scaling
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onTextChanged: {
              searchText = text
              // Defer selectedIndex reset to avoid binding loops
              Qt.callLater(() => selectedIndex = 0)
            }
            selectedTextColor: Color.mOnSurface
            selectionColor: Color.mPrimary
            padding: 0
            verticalAlignment: TextInput.AlignVCenter
            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0
            font.bold: true
            Component.onCompleted: {
            
              // contentItem.cursorColor = Color.mOnSurface
              // contentItem.verticalAlignment = TextInput.AlignVCenter
              // Focus the search bar by default
              Qt.callLater(() => {
                             searchInput.forceActiveFocus()
                           })
            }
            //onActiveFocusChanged: contentItem.cursorColor = Color.mOnSurface

            Keys.onDownPressed: selectNext()
            Keys.onUpPressed: selectPrev()
            Keys.onEnterPressed: activateSelected()
            Keys.onReturnPressed: activateSelected()
            Keys.onEscapePressed: root.close()
          }
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on border.width {
          NumberAnimation {
            duration: Style.animationFast
          }
        }
      }

      // Applications list
      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ListView {
          id: appsList
          anchors.fill: parent
          spacing: Style.marginXXS * scaling
          model: filteredEntries
          currentIndex: selectedIndex

          delegate: Rectangle {
            width: appsList.width - Style.marginS * scaling
            height: 65 * scaling
            radius: Style.radiusM * scaling
            property bool isSelected: index === selectedIndex
            color: (appCardArea.containsMouse || isSelected) ? Qt.darker(Color.mPrimary, 1.1) : Color.mSurface
            border.color: (appCardArea.containsMouse || isSelected) ? Color.mPrimary : Color.transparent
            border.width: Math.max(1, (appCardArea.containsMouse || isSelected) ? Style.borderM * scaling : 0)

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            Behavior on border.color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            Behavior on border.width {
              NumberAnimation {
                duration: Style.animationFast
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.marginM * scaling
              spacing: Style.marginM * scaling

              // App icon with background
              Rectangle {
                Layout.preferredWidth: Style.baseWidgetSize * 1.25 * scaling
                Layout.preferredHeight: Style.baseWidgetSize * 1.25 * scaling
                radius: Style.radiusS * scaling
                color: appCardArea.containsMouse ? Qt.darker(Color.mPrimary, 1.1) : Color.mSurfaceVariant
                property bool iconLoaded: (modelData.isCalculator || modelData.isClipboard || modelData.isCommand)
                                          || (iconImg.status === Image.Ready && iconImg.source !== ""
                                              && iconImg.status !== Image.Error && iconImg.source !== "")
                visible: !searchText.startsWith(">calc") // Hide icon when in calculator mode

                // Clipboard image display
                Image {
                  id: clipboardImage
                  anchors.fill: parent
                  anchors.margins: Style.marginXS * scaling
                  visible: modelData.type === 'image'
                  source: modelData.data || ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                }

                IconImage {
                  id: iconImg
                  anchors.fill: parent
                  anchors.margins: Style.marginXS * scaling
                  asynchronous: true
                  source: modelData.isCalculator ? "" : modelData.isClipboard ? "" : modelData.isCommand ? modelData.icon : (modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : "")
                  visible: (modelData.isCalculator || modelData.isClipboard || modelData.isCommand || parent.iconLoaded)
                           && modelData.type !== 'image'
                }

                // Fallback icon container
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.marginXS * scaling
                  radius: Style.radiusXS * scaling
                  color: Color.mPrimary
                  opacity: Style.opacityMedium
                  visible: !parent.iconLoaded
                }

                NText {
                  anchors.centerIn: parent
                  visible: !parent.iconLoaded && !(modelData.isCalculator || modelData.isClipboard
                                                   || modelData.isCommand)
                  text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                  font.pointSize: Style.fontSizeXXL * scaling
                  font.weight: Font.Bold
                  color: Color.mPrimary
                }

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              // App info
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS * scaling

                NText {
                  text: modelData.name || "Unknown"
                  font.pointSize: Style.fontSizeL * scaling
                  font.weight: Font.Bold
                  color: (appCardArea.containsMouse || isSelected) ? Color.mOnPrimary : Color.mOnSurface
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                NText {
                  text: modelData.isCalculator ? (modelData.expr + " = " + modelData.result) : modelData.isClipboard ? modelData.content : modelData.isCommand ? modelData.content : (modelData.genericName || modelData.comment || "")
                  font.pointSize: Style.fontSizeM * scaling
                  color: (appCardArea.containsMouse || isSelected) ? Color.mOnPrimary : Color.mOnSurface
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              id: appCardArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor

              onClicked: {
                selectedIndex = index
                activateSelected()
              }
            }
          }
        }
      }

      // No results message
      NText {
        text: searchText.trim() !== "" ? "No applications found" : "No applications available"
        font.pointSize: Style.fontSizeL * scaling
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
        visible: filteredEntries.length === 0
      }

      // Results count
      NText {
        text: searchText.startsWith(
                ">clip") ? `${filteredEntries.length} clipboard item${filteredEntries.length
                           !== 1 ? 's' : ''}` : searchText.startsWith(
                                     ">calc") ? `${filteredEntries.length} result${filteredEntries.length
                                                !== 1 ? 's' : ''}` : `${filteredEntries.length} application${filteredEntries.length
                                                        !== 1 ? 's' : ''}`
        font.pointSize: Style.fontSizeXS * scaling
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
        visible: searchText.trim() !== ""
      }
    }
  }
}
