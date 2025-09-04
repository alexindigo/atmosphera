import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

NBox {
  id: root

  property string sectionName: ""
  property string sectionId: ""
  property var widgetModel: []
  property var availableWidgets: []

  signal addWidget(string widgetId, string section)
  signal removeWidget(string section, int index)
  signal reorderWidget(string section, int fromIndex, int toIndex)
  signal updateWidgetSettings(string section, int index, var settings)

  color: Color.mSurface
  Layout.fillWidth: true
  Layout.minimumHeight: {
    var widgetCount = widgetModel.length
    if (widgetCount === 0)
      return 140 * scaling

    var availableWidth = parent.width
    var avgWidgetWidth = 150 * scaling
    var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
    var rows = Math.ceil(widgetCount / widgetsPerRow)

    return (50 + 20 + (rows * 48) + ((rows - 1) * Style.marginS) + 20) * scaling
  }

  // Generate widget color from name checksum
  function getWidgetColor(widget) {
    const totalSum = JSON.stringify(widget).split('').reduce((acc, character) => {
                                                               return acc + character.charCodeAt(0)
                                                             }, 0)
    switch (totalSum % 10) {
    case 0:
      return Color.mPrimary
    case 1:
      return Color.mSecondary
    case 2:
      return Color.mTertiary
    case 3:
      return Color.mError
    case 4:
      return Color.mOnSurface
    case 5:
      return Qt.darker(Color.mPrimary, 1.3)
    case 6:
      return Qt.darker(Color.mSecondary, 1.3)
    case 7:
      return Qt.darker(Color.mTertiary, 1.3)
    case 8:
      return Qt.darker(Color.mError, 1.3)
    case 9:
      return Qt.darker(Color.mOnSurface, 1.3)
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL * scaling
    spacing: Style.marginM * scaling

    RowLayout {
      Layout.fillWidth: true

      NText {
        text: sectionName + " Section"
        font.pointSize: Style.fontSizeL * scaling
        font.weight: Style.fontWeightBold
        color: Color.mSecondary
        Layout.alignment: Qt.AlignVCenter
      }

      Item {
        Layout.fillWidth: true
      }
      NComboBox {
        id: comboBox
        model: availableWidgets
        label: ""
        description: ""
        placeholder: "Select a widget to add..."
        onSelected: key => comboBox.currentKey = key
        popupHeight: 240 * scaling

        Layout.alignment: Qt.AlignVCenter
      }

      NIconButton {
        icon: "add"

        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Color.mSecondary
        colorFgHover: Color.mOnSecondary
        enabled: comboBox.currentKey !== ""
        tooltipText: "Add widget to section"
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginS * scaling
        onClicked: {
          if (comboBox.currentKey !== "") {
            addWidget(comboBox.currentKey, sectionId)
            comboBox.currentKey = ""
          }
        }
      }
    }

    // Drag and Drop Widget Area
    // Replace your Flow section with this:

    // Drag and Drop Widget Area - use Item container
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 65 * scaling

      Flow {
        id: widgetFlow
        anchors.fill: parent
        spacing: Style.marginS * scaling
        flow: Flow.LeftToRight

        Repeater {
          model: widgetModel
          delegate: Rectangle {
            id: widgetItem
            required property int index
            required property var modelData

            width: widgetContent.implicitWidth + Style.marginL * scaling
            height: Style.baseWidgetSize * 1.15 * scaling
            radius: Style.radiusL * scaling
            color: root.getWidgetColor(modelData)
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderS * scaling)

            // Store the widget index for drag operations
            property int widgetIndex: index
            readonly property int buttonsWidth: Math.round(20 * scaling)
            readonly property int buttonsCount: 1 + BarWidgetRegistry.widgetHasUserSettings(modelData.id)

            // Visual feedback during drag
            states: State {
              when: flowDragArea.draggedIndex === index
              PropertyChanges {
                target: widgetItem
                scale: 1.1
                opacity: 0.9
                z: 1000
              }
            }

            RowLayout {
              id: widgetContent
              anchors.centerIn: parent
              spacing: Style.marginXXS * scaling

              NText {
                text: modelData.id
                font.pointSize: Style.fontSizeS * scaling
                color: Color.mOnPrimary
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                Layout.preferredWidth: 80 * scaling
              }

              RowLayout {
                spacing: 0
                Layout.preferredWidth: buttonsCount * buttonsWidth

                Loader {
                  active: BarWidgetRegistry.widgetHasUserSettings(modelData.id)
                  sourceComponent: NIconButton {
                    icon: "settings"
                    sizeRatio: 0.6
                    colorBorder: Qt.alpha(Color.mOutline, Style.opacityLight)
                    colorBg: Color.mOnSurface
                    colorFg: Color.mOnPrimary
                    colorBgHover: Qt.alpha(Color.mOnPrimary, Style.opacityLight)
                    colorFgHover: Color.mOnPrimary
                    onClicked: {
                      var dialog = Qt.createComponent("BarWidgetSettingsDialog.qml").createObject(root, {
                                                                                                    "widgetIndex": index,
                                                                                                    "widgetData": modelData,
                                                                                                    "widgetId": modelData.id,
                                                                                                    "parent": Overlay.overlay
                                                                                                  })
                      dialog.open()
                    }
                  }
                }

                NIconButton {
                  icon: "close"
                  sizeRatio: 0.6
                  colorBorder: Qt.alpha(Color.mOutline, Style.opacityLight)
                  colorBg: Color.mOnSurface
                  colorFg: Color.mOnPrimary
                  colorBgHover: Qt.alpha(Color.mOnPrimary, Style.opacityLight)
                  colorFgHover: Color.mOnPrimary
                  onClicked: {
                    removeWidget(sectionId, index)
                  }
                }
              }
            }
          }
        }
      }

      // MouseArea outside Flow, covering the same area
      MouseArea {
        id: flowDragArea
        anchors.fill: parent
        z: 999 // Above all widgets to ensure it gets events first

        // Critical properties for proper event handling
        acceptedButtons: Qt.LeftButton
        preventStealing: false // Prevent child items from stealing events
        propagateComposedEvents: draggedIndex != -1 // Don't propagate to children during drag
        hoverEnabled: draggedIndex != -1

        property point startPos: Qt.point(0, 0)
        property bool dragStarted: false
        property int draggedIndex: -1
        property real dragThreshold: 15 * scaling
        property Item draggedWidget: null
        property point clickOffsetInWidget: Qt.point(0, 0)
        property point originalWidgetPos: Qt.point(0, 0) // ADD THIS: Store original position

        onPressed: mouse => {
                     startPos = Qt.point(mouse.x, mouse.y)
                     dragStarted = false
                     draggedIndex = -1
                     draggedWidget = null

                     // Find which widget was clicked
                     for (var i = 0; i < widgetModel.length; i++) {
                       const widget = widgetFlow.children[i]
                       if (widget && widget.widgetIndex !== undefined) {
                         if (mouse.x >= widget.x && mouse.x <= widget.x + widget.width && mouse.y >= widget.y
                             && mouse.y <= widget.y + widget.height) {

                           const localX = mouse.x - widget.x
                           const buttonsStartX = widget.width - (widget.buttonsCount * widget.buttonsWidth)

                           if (localX < buttonsStartX) {
                             draggedIndex = widget.widgetIndex
                             draggedWidget = widget

                             // Calculate and store where within the widget the user clicked
                             const clickOffsetX = mouse.x - widget.x
                             const clickOffsetY = mouse.y - widget.y
                             clickOffsetInWidget = Qt.point(clickOffsetX, clickOffsetY)

                             // STORE ORIGINAL POSITION
                             originalWidgetPos = Qt.point(widget.x, widget.y)

                             // Immediately set prevent stealing to true when drag candidate is found
                             preventStealing = true
                             break
                           } else {
                             // Click was on buttons - allow event propagation
                             mouse.accepted = false
                             return
                           }
                         }
                       }
                     }
                   }

        onPositionChanged: mouse => {
                             if (draggedIndex !== -1) {
                               const deltaX = mouse.x - startPos.x
                               const deltaY = mouse.y - startPos.y
                               const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY)

                               if (!dragStarted && distance > dragThreshold) {
                                 dragStarted = true
                                 //Logger.log("BarSectionEditor", "Drag started")

                                 // Enable visual feedback
                                 if (draggedWidget) {
                                   draggedWidget.z = 1000
                                 }
                               }

                               if (dragStarted && draggedWidget) {
                                 // Adjust position to account for where within the widget the user clicked
                                 draggedWidget.x = mouse.x - clickOffsetInWidget.x
                                 draggedWidget.y = mouse.y - clickOffsetInWidget.y
                               }
                             }
                           }

        onReleased: mouse => {
                      if (dragStarted && draggedWidget) {
                        // Find drop target using improved logic
                        let targetIndex = -1
                        let minDistance = Infinity
                        const mouseX = mouse.x
                        const mouseY = mouse.y

                        // Check if we should insert at the beginning
                        let insertAtBeginning = true
                        let insertAtEnd = true

                        // Check if the dragged item is already the last item
                        let isLastItem = true
                        for (var k = 0; k < widgetModel.length; k++) {
                          if (k !== draggedIndex && k > draggedIndex) {
                            isLastItem = false
                            break
                          }
                        }

                        for (var i = 0; i < widgetModel.length; i++) {
                          if (i !== draggedIndex) {
                            const widget = widgetFlow.children[i]
                            if (widget && widget.widgetIndex !== undefined) {
                              const centerX = widget.x + widget.width / 2
                              const centerY = widget.y + widget.height / 2
                              const distance = Math.sqrt(Math.pow(mouseX - centerX, 2) + Math.pow(mouseY - centerY, 2))

                              // Check if mouse is to the right of this widget
                              if (mouseX > widget.x + widget.width / 2) {
                                insertAtBeginning = false
                              }
                              // Check if mouse is to the left of this widget
                              if (mouseX < widget.x + widget.width / 2) {
                                insertAtEnd = false
                              }

                              if (distance < minDistance) {
                                minDistance = distance
                                targetIndex = widget.widgetIndex
                              }
                            }
                          }
                        }

                        // If dragging the last item to the right, don't reorder
                        if (isLastItem && insertAtEnd) {
                          insertAtEnd = false
                          targetIndex = -1
                          //Logger.log("BarSectionEditor", "Last item dropped to right - no reordering needed")
                        }

                        // Determine final target index based on position
                        let finalTargetIndex = targetIndex

                        if (insertAtBeginning && widgetModel.length > 1) {
                          // Insert at the very beginning (position 0)
                          finalTargetIndex = 0
                          //Logger.log("BarSectionEditor", "Inserting at beginning")
                        } else if (insertAtEnd && widgetModel.length > 1) {
                          // Insert at the very end
                          let maxIndex = -1
                          for (var j = 0; j < widgetModel.length; j++) {
                            if (j !== draggedIndex) {
                              maxIndex = Math.max(maxIndex, j)
                            }
                          }
                          finalTargetIndex = maxIndex
                          //Logger.log("BarSectionEditor", "Inserting at end, target:", finalTargetIndex)
                        } else if (targetIndex !== -1) {
                          // Normal case - determine if we should insert before or after the target
                          const targetWidget = widgetFlow.children[targetIndex]
                          if (targetWidget) {
                            const targetCenterX = targetWidget.x + targetWidget.width / 2
                            if (mouseX > targetCenterX) {

                              // Mouse is to the right of target center, insert after
                              //Logger.log("BarSectionEditor", "Inserting after widget at index:", targetIndex)
                            } else {
                              // Mouse is to the left of target center, insert before
                              finalTargetIndex = targetIndex
                              //Logger.log("BarSectionEditor", "Inserting before widget at index:", targetIndex)
                            }
                          }
                        }

                        //Logger.log("BarSectionEditor", "Final drop target index:", finalTargetIndex)

                        // Check if reordering is needed
                        if (finalTargetIndex !== -1 && finalTargetIndex !== draggedIndex) {
                          // Reordering will happen - reset position for the Flow to handle
                          draggedWidget.x = 0
                          draggedWidget.y = 0
                          draggedWidget.z = 0
                          reorderWidget(sectionId, draggedIndex, finalTargetIndex)
                        } else {
                          // No reordering - restore original position
                          draggedWidget.x = originalWidgetPos.x
                          draggedWidget.y = originalWidgetPos.y
                          draggedWidget.z = 0
                          //Logger.log("BarSectionEditor", "No reordering - restoring original position")
                        }
                      } else if (draggedIndex !== -1 && !dragStarted) {

                        // This was a click without drag - could add click handling here if needed
                      }

                      // Reset everything
                      dragStarted = false
                      draggedIndex = -1
                      draggedWidget = null
                      preventStealing = false // Allow normal event propagation again
                      originalWidgetPos = Qt.point(0, 0) // Reset stored position
                    }

        // Handle case where mouse leaves the area during drag
        onExited: {
          if (dragStarted && draggedWidget) {
            // Restore original position when mouse leaves area
            draggedWidget.x = originalWidgetPos.x
            draggedWidget.y = originalWidgetPos.y
            draggedWidget.z = 0
          }
        }
      }
    }
  }
}
