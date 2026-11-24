import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root

  property string label: ""
  property string description: ""
  property bool enableDescriptionRichText: false

  opacity: enabled ? 1.0 : 0.6
  spacing: Style.marginXXS
  Layout.fillWidth: true
  Layout.bottomMargin: Style.marginM

  NText {
    text: root.label
    pointSize: Style.fontSizeXL
    font.weight: Style.fontWeightSemiBold
    color: AtmoColor.mPrimary
    visible: root.label !== ""
  }

  NText {
    text: root.enableDescriptionRichText ? "" : root.description
    pointSize: Style.fontSizeM
    color: AtmoColor.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    visible: !root.enableDescriptionRichText && root.description !== ""
  }

  // Rich descriptions (for example from a plugin) present their images
  // through the shared owner.
  NImageText {
    text: root.enableDescriptionRichText ? root.description : ""
    format: "rich"
    pointSize: Style.fontSizeM
    color: AtmoColor.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    visible: root.enableDescriptionRichText && root.description !== ""
  }
}
