import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  property string label: ""
  property string description: ""
  property string value: ""

  signal editClicked

  spacing: Style.marginM

  NLabel {
    label: root.label
    description: root.description
    labelColor: root.value ? AtmoColor.mPrimary : AtmoColor.mOnSurface
  }

  AtmoIconButton {
    icon: Icon.settings
    onClicked: root.editClicked()
    tooltipText: I18n.tr("common.edit")
  }
}
