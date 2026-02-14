import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root

  property real minimumWidth: 200
  property string label: ""
  property string description: ""
  property string tooltip: ""
  property string currentKey: ""
  property var defaultValue: undefined
  property int circleSize: Style.baseWidgetSize * 0.9
  // Private properties
  readonly property bool isValueChanged: (defaultValue !== undefined) && (currentKey !== defaultValue)
  readonly property string indicatorTooltip: defaultValue !== undefined ? I18n.tr("panels.indicator.default-value", {
                                                                                    "value": defaultValue === "" ? "(empty)" : String(defaultValue)
                                                                                  }) : ""

  signal selected(string key)

  NLabel {
    label: root.label
    description: root.description
    showIndicator: root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  RowLayout {
    id: colourRow

    property real hoverScale: 1.15
    property int diameter: circleSize * Style.uiScaleRatio

    Layout.margins: Style.uiScaleRatio * hoverScale
    Layout.minimumWidth: Math.round(root.minimumWidth * Style.uiScaleRatio)

    Repeater {
      model: Color.colorKeyModel

      Rectangle {
        id: colorCircle

        property bool isSelected: root.currentKey === modelData.key
        property bool isHovered: circleMouseArea.containsMouse

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: colourRow.diameter
        implicitHeight: colourRow.diameter
        radius: colourRow.diameter * 0.5
        color: Color.resolveColorKey(modelData.key)
        border.color: isSelected ? Color.mOnSurface : "transparent"
        border.width: isSelected ? Style.borderS + 1 : 0
        scale: isHovered ? colourRow.hoverScale : 1

        MouseArea {
          id: circleMouseArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
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

        Behavior on scale {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutCubic
          }
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
