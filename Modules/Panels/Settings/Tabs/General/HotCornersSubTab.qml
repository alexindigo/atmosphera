import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  objectName: "hotCornersSettings"
  spacing: Style.marginL
  width: parent.width

  readonly property var corners: [
    {
      key: "topLeft",
      label: I18n.tr("panels.general.hot-corners-top-left"),
      icon: "arrow-up-left"
    },
    {
      key: "topRight",
      label: I18n.tr("panels.general.hot-corners-top-right"),
      icon: "arrow-up-right"
    },
    {
      key: "bottomLeft",
      label: I18n.tr("panels.general.hot-corners-bottom-left"),
      icon: "arrow-down-left"
    },
    {
      key: "bottomRight",
      label: I18n.tr("panels.general.hot-corners-bottom-right"),
      icon: "arrow-down-right"
    }
  ]

  NLabel {
    label: I18n.tr("panels.general.hot-corners-title")
    description: I18n.tr("panels.general.hot-corners-description")
    Layout.fillWidth: true
  }

  Repeater {
    model: root.corners
    delegate: ColumnLayout {
      id: cornerBlock
      required property var modelData
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        AtmoIcon {
          icon: cornerBlock.modelData.icon
          pointSize: Style.fontSizeM
        }
        NText {
          text: cornerBlock.modelData.label
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
        }
      }

      NActionPicker {
        Layout.fillWidth: true
        fieldObjectName: "hotCorner-" + cornerBlock.modelData.key
        popupTitle: I18n.tr("panels.general.hot-corners-popup-title")
        command: Settings.data.general.hotCorners[cornerBlock.modelData.key]
        onCommandChosen: command => Settings.data.general.hotCorners[cornerBlock.modelData.key] = command
      }
    }
  }

  NValueSlider {
    objectName: "hotCornersDelaySlider"
    Layout.fillWidth: true
    label: I18n.tr("panels.general.hot-corners-delay-label")
    description: I18n.tr("panels.general.hot-corners-delay-description")
    from: 100
    to: 1000
    stepSize: 50
    value: Settings.data.general.hotCorners.delayMs
    defaultValue: Settings.getDefaultValue("general.hotCorners.delayMs")
    text: String(Math.round(value))
    onMoved: value => Settings.data.general.hotCorners.delayMs = Math.round(value)
  }

  NText {
    objectName: "hotCornersNiriNote"
    visible: CompositorService.isNiri
    text: I18n.tr("panels.general.hot-corners-niri-note")
    pointSize: Style.fontSizeS
    color: AtmoColor.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
