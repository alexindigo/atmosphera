import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

NCard {
  id: root

  property string sectionName: ""
  property var widgetModel: []
  property var availableWidgets: []
  property var scrollView: null

  signal addWidget(string widgetName, string section)
  signal removeWidget(string section, int index)
  signal reorderWidget(string section, int fromIndex, int toIndex)

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
        color: Color.mOnSurface
        Layout.alignment: Qt.AlignVCenter
      }

      Item {
        Layout.fillWidth: true
      }

      NComboBox {
        id: comboBox
        width: 120 * scaling
        model: availableWidgets
        label: ""
        description: ""
        placeholder: "Add widget to " + sectionName.toLowerCase() + " section"
        onSelected: key => {
                      comboBox.selectedKey = key
                    }
      }

      NIconButton {
        icon: "add"
        size: 24 * scaling
        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Color.mPrimaryContainer
        colorFgHover: Color.mOnPrimaryContainer
        enabled: comboBox.selectedKey !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: {
          if (comboBox.selectedKey !== "") {
            addWidget(comboBox.selectedKey, sectionName.toLowerCase())
            comboBox.reset()
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
              colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
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
              colorBg: Color.applyOpacity(Color.mOnPrimary, "20")
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
