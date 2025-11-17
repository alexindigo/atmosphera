import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
  id: previewPanel

  property var currentItem: null

  implicitHeight: contentColumn.implicitHeight + Style.marginL * 2
  implicitWidth: 350 // A default width

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface || "#f5f5f5"
    border.color: Color.mOutlineVariant || "#cccccc"
    border.width: 1
    radius: Style.radiusM

    ColumnLayout {
      id: contentColumn
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      NText {
        text: "Preview"
        font.weight: Style.fontWeightBold
        Layout.fillWidth: true
      }

      ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: 400 // A default height
        clip: true

        TextArea {
          text: {
            if (currentItem && currentItem.preview != null) {
              return String(currentItem.preview);
            }
            return "";
          }
          readOnly: true
          wrapMode: Text.Wrap
          font.family: Style.monospaceFontFamily
        }
      }
    }
  }
}
