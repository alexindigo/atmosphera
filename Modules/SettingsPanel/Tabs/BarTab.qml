import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: 0

  ScrollView {
    id: scrollView

    Layout.fillWidth: true
    Layout.fillHeight: true
    padding: Style.marginM * scaling
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: scrollView.availableWidth
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
      }

      ColumnLayout {
        spacing: Style.marginL * scaling
        Layout.fillWidth: true

        NText {
          text: "Bar & Widgets"
          font.pointSize: Style.fontSizeXXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        ColumnLayout {
          spacing: Style.marginXXS * scaling
          Layout.fillWidth: true

          NText {
            text: "Bar Position"
            font.pointSize: Style.fontSizeL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: "Choose where to place the bar on the screen"
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          NComboBox {
            Layout.fillWidth: true
            model: ListModel {
              ListElement {
                key: "top"
                name: "Top"
              }
              ListElement {
                key: "bottom"
                name: "Bottom"
              }
            }
            currentKey: Settings.data.bar.position
            onSelected: key => {
                          Settings.data.bar.position = key
                        }
          }
        }

        NToggle {
          label: "Show Active Window's Icon"
          description: "Display the app icon next to the title of the currently focused window."
          checked: Settings.data.bar.showActiveWindowIcon
          onToggled: checked => {
                       Settings.data.bar.showActiveWindowIcon = checked
                     }
        }

        NToggle {
          label: "Show Battery Percentage"
          description: "Show battery percentage at all times."
          checked: Settings.data.bar.alwaysShowBatteryPercentage
          onToggled: checked => {
                       Settings.data.bar.alwaysShowBatteryPercentage = checked
                     }
        }

        ColumnLayout {
          spacing: Style.marginXXS * scaling
          Layout.fillWidth: true

          NText {
            text: "Background Opacity"
            font.pointSize: Style.fontSizeL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: "Adjust the background opacity of the bar"
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          RowLayout {
            NSlider {
              Layout.fillWidth: true
              from: 0
              to: 1
              stepSize: 0.01
              value: Settings.data.bar.backgroundOpacity
              onMoved: Settings.data.bar.backgroundOpacity = value
              cutoutColor: Color.mSurface
            }

            NText {
              text: Math.floor(Settings.data.bar.backgroundOpacity * 100) + "%"
              Layout.alignment: Qt.AlignVCenter
              Layout.leftMargin: Style.marginS * scaling
              color: Color.mOnSurface
            }
          }
        }

        // Widget Management Section
        ColumnLayout {
          spacing: Style.marginXXS * scaling
          Layout.fillWidth: true

          NText {
            text: "Widget Management"
            font.pointSize: Style.fontSizeL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: "Configure which widgets appear in each section of the bar. Use the arrow buttons to reorder widgets, or the add/remove buttons to manage them."
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Bar Sections
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.marginM * scaling

            // Left Section
            NCard {
              Layout.fillWidth: true
              Layout.minimumHeight: {
                var widgetCount = Settings.data.bar.widgets.left.length
                if (widgetCount === 0) return 140 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (50) + spacing (20) + (rows * widget height) + (rows-1 * spacing) + bottom margin (20)
                return (50 + 20 + (rows * 48) + ((rows - 1) * Style.marginS) + 20) * scaling
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginM * scaling
                spacing: Style.marginM * scaling

                RowLayout {
                  Layout.fillWidth: true

                  NText {
                    text: "Left Section"
                    font.pointSize: Style.fontSizeL * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                  }

                  Item { Layout.fillWidth: true }

                  NComboBox {
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to left section"
                    onSelected: key => {
                      addWidgetToSection(key, "left")
                    }
                  }
                }

                Flow {
                  id: leftWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 65 * scaling
                  spacing: Style.marginS * scaling
                  flow: Flow.LeftToRight

                  Repeater {
                    model: Settings.data.bar.widgets.left
                    delegate: Rectangle {
                      width: widgetContent.implicitWidth + 16 * scaling
                      height: 48 * scaling
                      radius: Style.radiusS * scaling
                      color: Color.mPrimary
                      border.color: Color.mOutline
                      border.width: Math.max(1, Style.borderS * scaling)

                      RowLayout {
                        id: widgetContent
                        anchors.centerIn: parent
                        spacing: Style.marginXS * scaling

                        NIconButton {
                          icon: "chevron_left"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index > 0
                          onClicked: {
                            if (index > 0) {
                              reorderWidgetInSection("left", index, index - 1)
                            }
                          }
                        }

                        NText {
                          text: modelData
                          font.pointSize: Style.fontSizeS * scaling
                          color: Color.mOnPrimary
                          horizontalAlignment: Text.AlignHCenter
                        }

                        NIconButton {
                          icon: "chevron_right"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index < Settings.data.bar.widgets.left.length - 1
                          onClicked: {
                            if (index < Settings.data.bar.widgets.left.length - 1) {
                              reorderWidgetInSection("left", index, index + 1)
                            }
                          }
                        }

                        NIconButton {
                          icon: "close"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          onClicked: {
                            removeWidgetFromSection("left", index)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Center Section
            NCard {
              Layout.fillWidth: true
              Layout.minimumHeight: {
                var widgetCount = Settings.data.bar.widgets.center.length
                if (widgetCount === 0) return 140 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (50) + spacing (20) + (rows * widget height) + (rows-1 * spacing) + bottom margin (20)
                return (50 + 20 + (rows * 48) + ((rows - 1) * Style.marginS) + 20) * scaling
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginM * scaling
                spacing: Style.marginM * scaling

                RowLayout {
                  Layout.fillWidth: true

                  NText {
                    text: "Center Section"
                    font.pointSize: Style.fontSizeL * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                  }

                  Item { Layout.fillWidth: true }

                  NComboBox {
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to center section"
                    onSelected: key => {
                      addWidgetToSection(key, "center")
                    }
                  }
                }

                Flow {
                  id: centerWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 65 * scaling
                  spacing: Style.marginS * scaling
                  flow: Flow.LeftToRight

                  Repeater {
                    model: Settings.data.bar.widgets.center
                    delegate: Rectangle {
                      width: widgetContent.implicitWidth + 16 * scaling
                      height: 48 * scaling
                      radius: Style.radiusS * scaling
                      color: Color.mPrimary
                      border.color: Color.mOutline
                      border.width: Math.max(1, Style.borderS * scaling)

                      RowLayout {
                        id: widgetContent
                        anchors.centerIn: parent
                        spacing: Style.marginXS * scaling

                        NIconButton {
                          icon: "chevron_left"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index > 0
                          onClicked: {
                            if (index > 0) {
                              reorderWidgetInSection("center", index, index - 1)
                            }
                          }
                        }

                        NText {
                          text: modelData
                          font.pointSize: Style.fontSizeS * scaling
                          color: Color.mOnPrimary
                          horizontalAlignment: Text.AlignHCenter
                        }

                        NIconButton {
                          icon: "chevron_right"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index < Settings.data.bar.widgets.center.length - 1
                          onClicked: {
                            if (index < Settings.data.bar.widgets.center.length - 1) {
                              reorderWidgetInSection("center", index, index + 1)
                            }
                          }
                        }

                        NIconButton {
                          icon: "close"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          onClicked: {
                            removeWidgetFromSection("center", index)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Right Section
            NCard {
              Layout.fillWidth: true
              Layout.minimumHeight: {
                var widgetCount = Settings.data.bar.widgets.right.length
                if (widgetCount === 0) return 140 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (50) + spacing (20) + (rows * widget height) + (rows-1 * spacing) + bottom margin (20)
                return (50 + 20 + (rows * 48) + ((rows - 1) * Style.marginS) + 20) * scaling
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginM * scaling
                spacing: Style.marginM * scaling

                RowLayout {
                  Layout.fillWidth: true

                  NText {
                    text: "Right Section"
                    font.pointSize: Style.fontSizeL * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                  }

                  Item { Layout.fillWidth: true }

                  NComboBox {
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to right section"
                    onSelected: key => {
                      addWidgetToSection(key, "right")
                    }
                  }
                }

                Flow {
                  id: rightWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 65 * scaling
                  spacing: Style.marginS * scaling
                  flow: Flow.LeftToRight

                  Repeater {
                    model: Settings.data.bar.widgets.right
                    delegate: Rectangle {
                      width: widgetContent.implicitWidth + 16 * scaling
                      height: 48 * scaling
                      radius: Style.radiusS * scaling
                      color: Color.mPrimary
                      border.color: Color.mOutline
                      border.width: Math.max(1, Style.borderS * scaling)

                      RowLayout {
                        id: widgetContent
                        anchors.centerIn: parent
                        spacing: Style.marginXS * scaling

                        NIconButton {
                          icon: "chevron_left"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index > 0
                          onClicked: {
                            if (index > 0) {
                              reorderWidgetInSection("right", index, index - 1)
                            }
                          }
                        }

                        NText {
                          text: modelData
                          font.pointSize: Style.fontSizeS * scaling
                          color: Color.mOnPrimary
                          horizontalAlignment: Text.AlignHCenter
                        }

                        NIconButton {
                          icon: "chevron_right"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          enabled: index < Settings.data.bar.widgets.right.length - 1
                          onClicked: {
                            if (index < Settings.data.bar.widgets.right.length - 1) {
                              reorderWidgetInSection("right", index, index + 1)
                            }
                          }
                        }

                        NIconButton {
                          icon: "close"
                          size: 20 * scaling
                          colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
                          colorFg: Color.mOnPrimary
                          colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                          colorFgHover: Color.mOnPrimary
                          onClicked: {
                            removeWidgetFromSection("right", index)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }



  // Helper functions
  function addWidgetToSection(widgetName, section) {
    console.log("Adding widget", widgetName, "to section", section)
    var sectionArray = Settings.data.bar.widgets[section]
    if (sectionArray) {
      // Create a new array to avoid modifying the original
      var newArray = sectionArray.slice()
      newArray.push(widgetName)
      console.log("Widget added. New array:", JSON.stringify(newArray))
      
      // Assign the new array
      Settings.data.bar.widgets[section] = newArray
    }
  }

  function removeWidgetFromSection(section, index) {
    console.log("Removing widget from section", section, "at index", index)
    var sectionArray = Settings.data.bar.widgets[section]
    if (sectionArray && index >= 0 && index < sectionArray.length) {
      // Create a new array to avoid modifying the original
      var newArray = sectionArray.slice()
      newArray.splice(index, 1)
      console.log("Widget removed. New array:", JSON.stringify(newArray))
      
      // Assign the new array
      Settings.data.bar.widgets[section] = newArray
    }
  }

  function reorderWidgetInSection(section, fromIndex, toIndex) {
    console.log("Reordering widget in section", section, "from", fromIndex, "to", toIndex)
    var sectionArray = Settings.data.bar.widgets[section]
    if (sectionArray && fromIndex >= 0 && fromIndex < sectionArray.length && 
        toIndex >= 0 && toIndex < sectionArray.length) {
      
      // Create a new array to avoid modifying the original
      var newArray = sectionArray.slice()
      var item = newArray[fromIndex]
      newArray.splice(fromIndex, 1)
      newArray.splice(toIndex, 0, item)
      console.log("Widget reordered. New array:", JSON.stringify(newArray))
      
      // Assign the new array
      Settings.data.bar.widgets[section] = newArray
    }
  }

  // Dynamic widget discovery using FolderListModel
  FolderListModel {
    id: widgetFolderModel
    folder: Qt.resolvedUrl("../../Bar/Widgets/")
    nameFilters: ["*.qml"]
    showDirs: false
    showFiles: true
  }
  
  ListModel {
    id: availableWidgets
  }
  
  Component.onCompleted: {
    discoverWidgets()
  }
  
  // Automatically discover available widgets from the Widgets directory
  function discoverWidgets() {
    console.log("Discovering widgets...")
    console.log("FolderListModel count:", widgetFolderModel.count)
    console.log("FolderListModel folder:", widgetFolderModel.folder)
    
    availableWidgets.clear()
    
    // Process each .qml file found in the directory
    for (let i = 0; i < widgetFolderModel.count; i++) {
      const fileName = widgetFolderModel.get(i, "fileName")
      console.log("Found file:", fileName)
      const widgetName = fileName.replace('.qml', '')
      
      // Skip TrayMenu as it's not a standalone widget
      if (widgetName !== 'TrayMenu') {
        console.log("Adding widget:", widgetName)
        availableWidgets.append({
          key: widgetName,
          name: widgetName,
          icon: getDefaultIcon(widgetName)
        })
      }
    }
    
    console.log("Total widgets added:", availableWidgets.count)
    
    // If FolderListModel didn't find anything, use fallback
    if (availableWidgets.count === 0) {
      console.log("FolderListModel failed, using fallback list")
      const fallbackWidgets = [
        "ActiveWindow", "Battery", "Bluetooth", "Brightness", "Clock", 
        "MediaMini", "NotificationHistory", "ScreenRecorderIndicator", 
        "SidePanelToggle", "SystemMonitor", "Tray", "Volume", "WiFi", "Workspace"
      ]
      
      fallbackWidgets.forEach(widgetName => {
        availableWidgets.append({
          key: widgetName,
          name: widgetName,
          icon: getDefaultIcon(widgetName)
        })
      })
    }
    
    // Sort alphabetically by name
    sortWidgets()
  }
  
  // Sort widgets alphabetically
  function sortWidgets() {
    const widgets = []
    for (let i = 0; i < availableWidgets.count; i++) {
      widgets.push({
        key: availableWidgets.get(i).key,
        name: availableWidgets.get(i).name,
        icon: availableWidgets.get(i).icon
      })
    }
    
    widgets.sort((a, b) => a.name.localeCompare(b.name))
    
    availableWidgets.clear()
    widgets.forEach(widget => {
      availableWidgets.append(widget)
    })
  }
  
  // Get default icon for widget (can be overridden in widget files)
  function getDefaultIcon(widgetName) {
    const iconMap = {
      "ActiveWindow": "web_asset",
      "Battery": "battery_full",
      "Bluetooth": "bluetooth",
      "Brightness": "brightness_6",
      "Clock": "schedule",
      "MediaMini": "music_note",
      "NotificationHistory": "notifications",
      "ScreenRecorderIndicator": "videocam",
      "SidePanelToggle": "widgets",
      "SystemMonitor": "memory",
      "Tray": "apps",
      "Volume": "volume_up",
      "WiFi": "wifi",
      "Workspace": "dashboard"
    }
    return iconMap[widgetName] || "widgets"
  }



  // Helper function to get widget icons
  function getWidgetIcon(widgetKey) {
    switch(widgetKey) {
      case "SystemMonitor": return "memory"
      case "ActiveWindow": return "web_asset"
      case "MediaMini": return "music_note"
      case "Workspace": return "dashboard"
      case "ScreenRecorderIndicator": return "videocam"
      case "Tray": return "apps"
      case "NotificationHistory": return "notifications"
      case "WiFi": return "wifi"
      case "Bluetooth": return "bluetooth"
      case "Battery": return "battery_full"
      case "Volume": return "volume_up"
      case "Brightness": return "brightness_6"
      case "Clock": return "schedule"
      case "SidePanelToggle": return "widgets"
      default: return "widgets"
    }
  }
}
