import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
                if (widgetCount === 0) return 120 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (40) + spacing (16) + (rows * widget height) + (rows-1 * spacing) + bottom margin (16)
                return (40 + 16 + (rows * 48) + ((rows - 1) * Style.marginS) + 16) * scaling
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

                  Rectangle {
                    width: 32 * scaling
                    height: 32 * scaling
                    radius: width * 0.5
                    color: Color.mPrimary
                    border.color: Color.mPrimaryContainer
                    border.width: 2 * scaling

                    NIcon {
                      anchors.centerIn: parent
                      text: "add"
                      color: Color.mOnPrimary
                      font.pointSize: Style.fontSizeM * scaling
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        addWidgetDialog.show("left")
                      }
                    }
                  }
                }

                Flow {
                  id: leftWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 52 * scaling
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
                if (widgetCount === 0) return 120 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (40) + spacing (16) + (rows * widget height) + (rows-1 * spacing) + bottom margin (16)
                return (40 + 16 + (rows * 48) + ((rows - 1) * Style.marginS) + 16) * scaling
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

                  Rectangle {
                    width: 32 * scaling
                    height: 32 * scaling
                    radius: width * 0.5
                    color: Color.mPrimary
                    border.color: Color.mPrimaryContainer
                    border.width: 2 * scaling

                    NIcon {
                      anchors.centerIn: parent
                      text: "add"
                      color: Color.mOnPrimary
                      font.pointSize: Style.fontSizeM * scaling
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        addWidgetDialog.show("center")
                      }
                    }
                  }
                }

                Flow {
                  id: centerWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 52 * scaling
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
                if (widgetCount === 0) return 120 * scaling
                
                var availableWidth = scrollView.availableWidth - (Style.marginM * scaling * 2) // Card margins
                var avgWidgetWidth = 150 * scaling // Estimated widget width including spacing
                var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
                var rows = Math.ceil(widgetCount / widgetsPerRow)
                
                // Header (40) + spacing (16) + (rows * widget height) + (rows-1 * spacing) + bottom margin (16)
                return (40 + 16 + (rows * 48) + ((rows - 1) * Style.marginS) + 16) * scaling
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

                  Rectangle {
                    width: 32 * scaling
                    height: 32 * scaling
                    radius: width * 0.5
                    color: Color.mPrimary
                    border.color: Color.mPrimaryContainer
                    border.width: 2 * scaling

                    NIcon {
                      anchors.centerIn: parent
                      text: "add"
                      color: Color.mOnPrimary
                      font.pointSize: Style.fontSizeM * scaling
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        addWidgetDialog.show("right")
                      }
                    }
                  }
                }

                Flow {
                  id: rightWidgetsFlow
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 52 * scaling
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

  // Add Widget Dialog
  Rectangle {
    id: addWidgetDialog
    anchors.fill: parent
    color: Color.applyOpacity(Color.mShadow, "80")
    visible: false
    z: 1000

    property string targetSection: ""

    function show(section) {
      targetSection = section
      visible = true
    }

    function hide() {
      visible = false
      targetSection = ""
    }

    MouseArea {
      anchors.fill: parent
      onClicked: addWidgetDialog.hide()
    }

    Rectangle {
      anchors.centerIn: parent
      width: 400 * scaling
      height: 500 * scaling
      radius: Style.radiusL * scaling
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Math.max(1, Style.borderS * scaling)

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL * scaling
        spacing: Style.marginM * scaling

        NText {
          text: "Add Widget to " + (addWidgetDialog.targetSection === "left" ? "Left" : 
                                   addWidgetDialog.targetSection === "center" ? "Center" : "Right") + " Section"
          font.pointSize: Style.fontSizeL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.marginXS * scaling

          model: ListModel {
            ListElement { name: "SystemMonitor"; icon: "memory"; description: "System statistics" }
            ListElement { name: "ActiveWindow"; icon: "web_asset"; description: "Active window title" }
            ListElement { name: "MediaMini"; icon: "music_note"; description: "Media controls" }
            ListElement { name: "Workspace"; icon: "dashboard"; description: "Workspace switcher" }
            ListElement { name: "ScreenRecorderIndicator"; icon: "videocam"; description: "Recording indicator" }
            ListElement { name: "Tray"; icon: "apps"; description: "System tray" }
            ListElement { name: "NotificationHistory"; icon: "notifications"; description: "Notification history" }
            ListElement { name: "WiFi"; icon: "wifi"; description: "WiFi status" }
            ListElement { name: "Bluetooth"; icon: "bluetooth"; description: "Bluetooth status" }
            ListElement { name: "Battery"; icon: "battery_full"; description: "Battery status" }
            ListElement { name: "Volume"; icon: "volume_up"; description: "Volume control" }
            ListElement { name: "Brightness"; icon: "brightness_6"; description: "Brightness control" }
            ListElement { name: "Clock"; icon: "schedule"; description: "Clock" }
            ListElement { name: "SidePanelToggle"; icon: "widgets"; description: "Side panel toggle" }
          }

          delegate: Rectangle {
            width: ListView.view.width
            height: 48 * scaling
            radius: Style.radiusS * scaling
            color: mouseArea.containsMouse ? Color.mTertiary : Color.mSurfaceVariant
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderS * scaling)

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.marginS * scaling
              spacing: Style.marginS * scaling

              NIcon {
                text: model.icon
                color: Color.mOnSurface
                font.pointSize: Style.fontSizeM * scaling
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                NText {
                  text: model.name
                  font.pointSize: Style.fontSizeS * scaling
                  font.weight: Style.fontWeightBold
                  color: Color.mOnSurface
                }

                NText {
                  text: model.description
                  font.pointSize: Style.fontSizeXS * scaling
                  color: Color.mOnSurfaceVariant
                }
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                addWidgetToSection(model.name, addWidgetDialog.targetSection)
                addWidgetDialog.hide()
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true

          Item { Layout.fillWidth: true }

          NIconButton {
            icon: "close"
            size: 20 * scaling
            color: Color.mOnSurface
            onClicked: addWidgetDialog.hide()
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
}
