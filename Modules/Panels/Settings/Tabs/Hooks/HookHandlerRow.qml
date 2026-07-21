import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  property string label: ""
  property string description: ""
  property string command: ""
  property bool exclusive: false

  signal editClicked
  signal exclusiveToggled(bool checked)

  spacing: Style.marginM

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginXS

    RowLayout {
      spacing: Style.marginS

      NLabel {
        label: root.label
        description: root.description
        labelColor: root.command ? Color.mPrimary : Color.mOnSurface
      }

      NIconButton {
        icon: Icon.settings
        onClicked: root.editClicked()
        tooltipText: I18n.tr("common.edit")
      }
    }

    RowLayout {
      spacing: Style.marginM
      visible: root.command !== ""

      NToggle {
        label: I18n.tr("panels.hooks.handler-exclusive-label")
        description: I18n.tr("panels.hooks.handler-exclusive-description")
        checked: root.exclusive
        onToggled: checked => root.exclusiveToggled(checked)
      }
    }
  }
}
