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

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginXS

    NText {
      text: root.label
      font.weight: Style.fontWeightBold
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    NText {
      text: root.description
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeS
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
    }

    // Optional: Show current value preview if not empty?
    // For now, let's keep it clean as requested.
  }

  NIconButton {
    icon: "settings"
    onClicked: root.editClicked()
    tooltipText: I18n.tr("common.edit")
  }
}
