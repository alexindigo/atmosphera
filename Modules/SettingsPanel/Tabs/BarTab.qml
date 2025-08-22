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


        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginL * scaling
          Layout.bottomMargin: Style.marginL * scaling
        }

        // Widgets Management Section
        ColumnLayout {
          spacing: Style.marginXXS * scaling
          Layout.fillWidth: true

          NText {
            text: "Widgets Positioning"
            font.pointSize: Style.fontSizeL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: "Add, remove, or reorder widgets in each section of the bar using the control buttons."
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Bar Sections
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Style.marginM * scaling
            spacing: Style.marginM * scaling

            // Left Section
            NCard {
              Layout.fillWidth: true
              Layout.minimumHeight: {
                var widgetCount = Settings.data.bar.widgets.left.length
                if (widgetCount === 0)
                  return 140 * scaling

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

                  Item {
                    Layout.fillWidth: true
                  }

                  NComboBox {
                    id: leftComboBox
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to left section"
                    onSelected: key => {
                                  addWidgetToSection(key, "left")
                                  reset() // Reset selection
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
                if (widgetCount === 0)
                  return 140 * scaling

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

                  Item {
                    Layout.fillWidth: true
                  }

                  NComboBox {
                    id: centerComboBox
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to center section"
                    onSelected: key => {
                                  addWidgetToSection(key, "center")
                                  reset() // Reset selection
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
                if (widgetCount === 0)
                  return 140 * scaling

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

                  Item {
                    Layout.fillWidth: true
                  }

                  NComboBox {
                    id: rightComboBox
                    width: 120 * scaling
                    model: availableWidgets
                    label: ""
                    description: ""
                    placeholder: "Add widget to right section"
                    onSelected: key => {
                                  addWidgetToSection(key, "right")
                                  reset() // Reset selection
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
    if (sectionArray && fromIndex >= 0 && fromIndex < sectionArray.length && toIndex >= 0
        && toIndex < sectionArray.length) {

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

  // Widget loader for discovering available widgets
  WidgetLoader {
    id: widgetLoader
  }

  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    discoverWidgets()
  }

  // Automatically discover available widgets using WidgetLoader
  function discoverWidgets() {
    availableWidgets.clear()

    // Use WidgetLoader to discover available widgets
    const discoveredWidgets = widgetLoader.discoverAvailableWidgets()

    // Add discovered widgets to the ListModel
    discoveredWidgets.forEach(widget => {
                                availableWidgets.append(widget)
                              })
  }
}
