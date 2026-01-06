import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Keyboard
import qs.Widgets

Item {
  id: previewPanel

  property var currentItem: null
  property string fullContent: ""
  property string imageDataUrl: ""
  property bool loadingFullContent: false
  property bool isImageContent: false

  implicitHeight: contentArea.implicitHeight + Style.marginL * 2

  function loadContent() {
    if (!currentItem || !currentItem.clipboardId)
      return;

    if (isImageContent) {
      // For images, check cache first then decode
      imageDataUrl = ClipboardService.getImageData(currentItem.clipboardId) || "";
      loadingFullContent = !imageDataUrl;
      if (!imageDataUrl && currentItem.mime) {
        ClipboardService.decodeToDataUrl(currentItem.clipboardId, currentItem.mime, null);
      }
    } else {
      // For text, check sync cache first
      const cached = ClipboardService.getContent(currentItem.clipboardId);
      if (cached) {
        fullContent = cached;
        loadingFullContent = false;
      } else {
        // Show preview while loading full content
        fullContent = currentItem.preview || "";
        loadingFullContent = true;
        // Async decode as fallback
        var requestedId = currentItem.clipboardId;
        ClipboardService.decode(requestedId, function (content) {
          if (previewPanel.currentItem && previewPanel.currentItem.clipboardId === requestedId) {
            var trimmed = content ? content.trim() : "";
            if (trimmed !== "") {
              previewPanel.fullContent = trimmed;
            }
            previewPanel.loadingFullContent = false;
          }
        });
      }
    }
  }

  Connections {
    target: previewPanel
    function onCurrentItemChanged() {
      fullContent = "";
      imageDataUrl = "";
      loadingFullContent = false;
      isImageContent = currentItem && currentItem.isImage;

      if (currentItem && currentItem.clipboardId) {
        loadContent();
      }
    }
  }

  readonly property int _rev: ClipboardService.revision
  on_RevChanged: {
    // When cache updates, try to load content if we're still showing loading or preview
    if (currentItem && currentItem.clipboardId && !isImageContent && loadingFullContent) {
      const cached = ClipboardService.getContent(currentItem.clipboardId);
      if (cached) {
        fullContent = cached;
        loadingFullContent = false;
      }
    }
  }

  Timer {
    id: imageUpdateTimer
    interval: 200
    running: currentItem && currentItem.isImage && imageDataUrl === ""
    repeat: currentItem && currentItem.isImage && imageDataUrl === ""

    onTriggered: {
      if (currentItem && currentItem.clipboardId) {
        const newData = ClipboardService.getImageData(currentItem.clipboardId) || "";
        if (newData !== imageDataUrl) {
          imageDataUrl = newData;
          if (newData) {
            loadingFullContent = false;
          }
        }
      }
    }
  }

  Item {
    id: contentArea
    anchors.fill: parent
    anchors.margins: Style.marginS

    BusyIndicator {
      anchors.centerIn: parent
      running: loadingFullContent
      visible: loadingFullContent
      width: Style.baseWidgetSize
      height: width
    }

    Image {
      anchors.fill: parent
      anchors.margins: Style.marginS
      source: imageDataUrl
      visible: isImageContent && !loadingFullContent && imageDataUrl !== ""
      fillMode: Image.PreserveAspectFit
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginS
      spacing: Style.marginXS
      visible: !isImageContent && !loadingFullContent

      NText {
        Layout.fillWidth: true
        visible: fullContent.length > 0
        text: {
          const chars = fullContent.length;
          const words = fullContent.split(/\s+/).filter(w => w.length > 0).length;
          const lines = fullContent.split('\n').length;
          return `${chars} chars, ${words} words, ${lines} lines`;
        }
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        NText {
          text: fullContent
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          font.pointSize: Style.fontSizeM
          font.family: Settings.data.ui.fontFixed
          color: Color.mOnSurface
        }
      }
    }
  }
}
