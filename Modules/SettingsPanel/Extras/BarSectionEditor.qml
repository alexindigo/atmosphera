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
    Flow {
      id: widgetFlow
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 65 * scaling
      spacing: Style.marginS * scaling
      flow: Flow.LeftToRight

      Repeater {
        model: widgetModel
        delegate: Rectangle {
          id: widgetItem
          required property int index
          required property var modelData

          width: widgetContent.implicitWidth + Style.marginL * scaling
          height: 40 * scaling
          radius: Style.radiusL * scaling
          color: root.getWidgetColor(modelData)
          border.color: Color.mOutline
          border.width: Math.max(1, Style.borderS * scaling)

          // Drag properties
          Drag.keys: ["widget"]
          Drag.active: mouseArea.drag.active
          Drag.hotSpot.x: width / 2
          Drag.hotSpot.y: height / 2

          // Store the widget index for drag operations
          property int widgetIndex: index

          // Visual feedback during drag
          states: State {
            when: mouseArea.drag.active
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
            spacing: Style.marginXS * scaling

            NText {
              text: modelData.id
              font.pointSize: Style.fontSizeS * scaling
              color: Color.mOnPrimary
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              Layout.preferredWidth: 80 * scaling
            }

            Loader {
              active: BarWidgetRegistry.widgetHasUserSettings(modelData.id)
              sourceComponent: NIconButton {
                icon: "settings"
                sizeRatio: 0.6
                colorBorder: Color.applyOpacity(Color.mOutline, "40")
                colorBg: Color.mOnSurface
                colorFg: Color.mOnPrimary
                colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
                colorFgHover: Color.mOnPrimary
                onClicked: {
                  // Open widget settings dialog
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
              colorBorder: Color.applyOpacity(Color.mOutline, "40")
              colorBg: Color.mOnSurface
              colorFg: Color.mOnPrimary
              colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
              colorFgHover: Color.mOnPrimary
              onClicked: {
                removeWidget(sectionId, index)
              }
            }
          }

          // Mouse area for drag and drop
          MouseArea {
            id: mouseArea
            anchors.fill: parent
            drag.target: parent

            onPressed: mouse => {
                         // Check if the click is on the settings or close button area
                         const buttonsX = widgetContent.x + widgetContent.width - 45 * scaling
                         const buttonsY = widgetContent.y
                         const buttonsWidth = 45 * scaling
                         const buttonsHeight = 20 * scaling

                         if (mouseX >= buttonsX && mouseX <= buttonsX + buttonsWidth && mouseY >= buttonsY
                             && mouseY <= buttonsY + buttonsHeight) {
                           // Click is on the buttons, don't start drag
                           mouse.accepted = false
                           return
                         }

                         //Logger.log("BarSectionEditor", `Started dragging widget: ${modelData.id} at index ${index}`)
                         // Bring to front when starting drag
                         widgetItem.z = 1000
                       }

            onReleased: {
              //Logger.log("BarSectionEditor", `Released widget: ${modelData.id} at index ${index}`)
              // Reset z-index when drag ends
              widgetItem.z = 0

              // Get the global mouse position
              const globalDropX = mouseArea.mouseX + widgetItem.x + widgetFlow.x
              const globalDropY = mouseArea.mouseY + widgetItem.y + widgetFlow.y

              // Find which widget the drop position is closest to
              let targetIndex = -1
              let minDistance = Infinity

              for (var i = 0; i < widgetModel.length; i++) {
                if (i !== index) {
                  // Get the position of other widgets
                  const otherWidget = widgetFlow.children[i]
                  if (otherWidget && otherWidget.widgetIndex !== undefined) {
                    // Calculate the center of the other widget
                    const otherCenterX = otherWidget.x + otherWidget.width / 2 + widgetFlow.x
                    const otherCenterY = otherWidget.y + otherWidget.height / 2 + widgetFlow.y

                    // Calculate distance to the center of this widget
                    const distance = Math.sqrt(Math.pow(globalDropX - otherCenterX,
                                                        2) + Math.pow(globalDropY - otherCenterY, 2))

                    if (distance < minDistance) {
                      minDistance = distance
                      targetIndex = otherWidget.widgetIndex
                    }
                  }
                }
              }

              // Only reorder if we found a valid target and it's different from current position
              if (targetIndex !== -1 && targetIndex !== index) {
                const fromIndex = index
                const toIndex = targetIndex
                reorderWidget(sectionId, fromIndex, toIndex)
              }
            }
          }
        }
      }
    }

    // Drop zone at the beginning (positioned absolutely)
    DropArea {
      id: startDropZone
      width: 40 * scaling
      height: 40 * scaling
      x: widgetFlow.x
      y: widgetFlow.y + (widgetFlow.height - height) / 2
      keys: ["widget"]
      z: 1001 // Above the Flow

      Rectangle {
        anchors.fill: parent
        color: startDropZone.containsDrag ? Color.applyOpacity(Color.mPrimary, "20") : Color.transparent
        border.color: startDropZone.containsDrag ? Color.mPrimary : Color.transparent
        border.width: startDropZone.containsDrag ? 2 : 0
        radius: Style.radiusS * scaling
      }

      onEntered: function (drag) {//Logger.log("BarSectionEditor", "Entered start drop zone")
      }

      onDropped: function (drop) {
        //Logger.log("BarSectionEditor", "Dropped on start zone")
        if (drop.source && drop.source.widgetIndex !== undefined) {
          const fromIndex = drop.source.widgetIndex
          const toIndex = 0 // Insert at the beginning
          if (fromIndex !== toIndex) {
            //Logger.log("BarSectionEditor", `Dropped widget from index ${fromIndex} to beginning`)
            reorderWidget(sectionId, fromIndex, toIndex)
          }
        }
      }
    }

    // Drop zone at the end (positioned absolutely)
    DropArea {
      id: endDropZone
      width: 40 * scaling
      height: 40 * scaling
      x: widgetFlow.x + widgetFlow.width - width
      y: widgetFlow.y + (widgetFlow.height - height) / 2
      keys: ["widget"]
      z: 1001 // Above the Flow

      Rectangle {
        anchors.fill: parent
        color: endDropZone.containsDrag ? Color.applyOpacity(Color.mPrimary, "20") : Color.transparent
        border.color: endDropZone.containsDrag ? Color.mPrimary : Color.transparent
        border.width: endDropZone.containsDrag ? 2 : 0
        radius: Style.radiusS * scaling
      }

      onEntered: function (drag) {//Logger.log("BarSectionEditor", "Entered end drop zone")
      }

      onDropped: function (drop) {
        //Logger.log("BarSectionEditor", "Dropped on end zone")
        if (drop.source && drop.source.widgetIndex !== undefined) {
          const fromIndex = drop.source.widgetIndex
          const toIndex = widgetModel.length // Insert at the end
          if (fromIndex !== toIndex) {
            //Logger.log("BarSectionEditor", `Dropped widget from index ${fromIndex} to end`)
            reorderWidget(sectionId, fromIndex, toIndex)
          }
        }
      }
    }
  }
}
