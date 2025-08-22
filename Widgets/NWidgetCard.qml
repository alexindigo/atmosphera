import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

NBox {
  id: root

  property string sectionName: ""
  property var widgetModel: []
  property var availableWidgets: []
  property var scrollView: null

  signal addWidget(string widgetName, string section)
  signal removeWidget(string section, int index)
  signal reorderWidget(string section, int fromIndex, int toIndex)

  color: Color.mSurface
  Layout.fillWidth: true
  Layout.minimumHeight: {
    var widgetCount = widgetModel.length
    if (widgetCount === 0)
      return 140 * scaling

    var availableWidth = scrollView ? scrollView.availableWidth - (Style.marginM * scaling * 2) : 400 * scaling
    var avgWidgetWidth = 150 * scaling
    var widgetsPerRow = Math.max(1, Math.floor(availableWidth / avgWidgetWidth))
    var rows = Math.ceil(widgetCount / widgetsPerRow)

    return (50 + 20 + (rows * 48) + ((rows - 1) * Style.marginS) + 20) * scaling
  }

  // Generate widget color from name checksum
  function getWidgetColor(name) {
    const totalSum = name.split('').reduce((acc, character) => {
                                             return acc + character.charCodeAt(0)
                                           }, 0)
    switch (totalSum % 5) {
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
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM * scaling
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
        placeholder: "Add widget to the " + sectionName.toLowerCase() + " section..."
        onSelected: key => {
                      comboBox.currentKey = key
                    }
        Layout.alignment: Qt.AlignVCenter
      }

      NIconButton {
        icon: "add"

        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Color.mSecondary
        colorFgHover: Color.mOnSecondary
        enabled: comboBox.selectedKey !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: {
          if (comboBox.currentKey !== "") {
            addWidget(comboBox.currentKey, sectionName.toLowerCase())
            comboBox.currentKey = "battery"
          }
        }
      }
    }

    Flow {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 65 * scaling
      spacing: Style.marginS * scaling
      flow: Flow.LeftToRight

      Repeater {
        model: widgetModel
        delegate: Rectangle {
          width: widgetContent.implicitWidth + 16 * scaling
          height: 40 * scaling
          radius: Style.radiusL * scaling
          color: root.getWidgetColor(modelData)
          border.color: Color.mOutline
          border.width: Math.max(1, Style.borderS * scaling)

          RowLayout {
            id: widgetContent
            anchors.centerIn: parent
            spacing: Style.marginXS * scaling

            NIconButton {
              icon: "chevron_left"
              size: 20 * scaling
              colorBorder: Color.applyOpacity(Color.mOutline, "40")
              colorBg: Color.mOnSurface
              colorFg: Color.mOnPrimary
              colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
              colorFgHover: Color.mOnPrimary
              enabled: index > 0
              onClicked: {
                if (index > 0) {
                  reorderWidget(sectionName.toLowerCase(), index, index - 1)
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
              colorBorder: Color.applyOpacity(Color.mOutline, "40")
              colorBg: Color.mOnSurface
              colorFg: Color.mOnPrimary
              colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
              colorFgHover: Color.mOnPrimary
              enabled: index < widgetModel.length - 1
              onClicked: {
                if (index < widgetModel.length - 1) {
                  reorderWidget(sectionName.toLowerCase(), index, index + 1)
                }
              }
            }

            NIconButton {
              icon: "close"
              size: 20 * scaling
              colorBorder: Color.applyOpacity(Color.mOutline, "40")
              colorBg: Color.mOnSurface
              colorFg: Color.mOnPrimary
              colorBgHover: Color.applyOpacity(Color.mOnPrimary, "40")
              colorFgHover: Color.mOnPrimary
              onClicked: {
                removeWidget(sectionName.toLowerCase(), index)
              }
            }
          }
        }
      }
    }
  }
}
