import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Popup {
  id: root
  modal: true
  closePolicy: Popup.NoAutoClose
  anchors.centerIn: parent
  width: Math.min(400 * Style.uiScaleRatio, parent.width * 0.9)
  padding: Style.marginL
  signal discard
  signal keepEditing

  background: Rectangle {
    color: AtmoColor.mSurface
    radius: Style.radiusS
    border.color: AtmoColor.mOutline
    border.width: Style.borderS
  }

  contentItem: ColumnLayout {
    spacing: Style.marginL
    NText {
      text: I18n.tr("common.discard-changes")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
    RowLayout {
      Layout.fillWidth: true
      Item {
        Layout.fillWidth: true
      }
      NButton {
        text: I18n.tr("common.cancel")
        onClicked: root.keepEditing()
      }
      NButton {
        text: I18n.tr("common.discard")
        onClicked: root.discard()
      }
    }
  }
}
