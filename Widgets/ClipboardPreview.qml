import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Services.Keyboard // Import ClipboardService

Item {
  id: previewPanel

  property var currentItem: null
  property string fullContent: ""
  property bool loadingFullContent: false

  implicitHeight: contentColumn.implicitHeight + Style.marginL * 2
  implicitWidth: 350 // A default width

  Connections {
    target: previewPanel
    function onCurrentItemChanged() {
      fullContent = ""; // Clear previous content
      loadingFullContent = false;

      if (currentItem && currentItem.clipboardId) {
        loadingFullContent = true;
        ClipboardService.decode(currentItem.clipboardId, function(content) {
          fullContent = content;
          loadingFullContent = false;
        });
      }
    }
  }

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
        text: currentItem ? (currentItem.name || "Preview") : "Preview"
        font.weight: Style.fontWeightBold
        Layout.fillWidth: true
        pointSize: Style.fontSizeM
        color: Color.mOnSurface
      }

      NDivider {
        Layout.fillWidth: true
      }

      Rectangle { // Frame around the content
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant || "#e0e0e0"
        border.color: Color.mOutline || "#aaaaaa"
        border.width: 1
        radius: Style.radiusS

        // Loading indicator
        BusyIndicator {
          anchors.centerIn: parent
          running: loadingFullContent
          visible: loadingFullContent
          width: Style.baseWidgetSize
          height: width
        }

        ScrollView {
          Layout.fillHeight: true // Explicitly fill height
          anchors.fill: parent
          anchors.margins: Style.marginS
          clip: true
          visible: !loadingFullContent // Hide scrollview while loading

          TextArea {
            Layout.fillHeight: true // Explicitly fill height
            text: fullContent // Bind to fullContent
            readOnly: true
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
