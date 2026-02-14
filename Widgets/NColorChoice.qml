import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI

RowLayout {
  id: root

  property real minimumWidth: 200
  property string label: I18n.tr("common.select-color")
  property string description: I18n.tr("common.select-color-description")
  property string tooltip: ""
  property string currentKey: ""
  property var defaultValue: "none"
  property int circleSize: Style.baseWidgetSize * 0.9
  readonly property bool isValueChanged: currentKey !== defaultValue
  readonly property string indicatorTooltip: {
    I18n.tr("panels.indicator.default-value", {
              "value": defaultValue === "" ? "(empty)" : String(defaultValue)
            });
  }
  readonly property int diameter: circleSize * Style.uiScaleRatio

  signal selected(string key)

  NLabel {
    label: root.label
    description: root.description
    showIndicator: root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  RowLayout {
    id: colourRow
    Layout.minimumWidth: root.diameter * Color.colorKeyModel.length

    Repeater {
      model: Color.colorKeyModel

      Rectangle {
        id: colorCircle

        property bool isSelected: root.currentKey === modelData.key
        property bool isHovered: circleMouseArea.containsMouse

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.diameter
        implicitHeight: root.diameter
        radius: root.diameter * 0.5
        color: Color.resolveColorKey(modelData.key)
        border.color: (isSelected || isHovered) ? Color.mOnSurface : Color.mOutline
        border.width: Style.borderM
        scale: isHovered ? colourRow.hoverScale : 1

        MouseArea {
          id: circleMouseArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: TooltipService.show(parent, modelData.name)
          onExited: TooltipService.hide()
          onClicked: {
            root.currentKey = modelData.key;
            root.selected(modelData.key);
          }
        }

        NIcon {
          anchors.centerIn: parent
          icon: "check"
          pointSize: Math.max(Style.fontSizeXS, colorCircle.width * 0.4)
          color: Color.mOnPrimary
          visible: colorCircle.isSelected
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }
    }
  }
}
