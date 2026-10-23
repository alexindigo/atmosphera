import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Services.Files
import qs.Widgets

FocusScope {
  id: root
  required property var preview
  property bool opened: false
  property Item keyFocusOwner: null
  NInputGuard {
    target: root
    focusOwner: root.keyFocusOwner
    focusOnActivation: true
  }
  property rect origin: Qt.rect(0, 0, 1, 1)
  readonly property var item: preview.item
  readonly property string sourceUrl: preview.path ? PortalPaths.pathToUri(preview.path).uri : ""
  readonly property var renderer: mediaLoader.item
  readonly property var playback: mediaPlayback
  readonly property var playbackState: playback.snapshot
  function transportGeometry() {
    return transport.item ? transport.item.controlGeometry() : [];
  }
  readonly property bool expanding: grow.running
  readonly property bool audio: preview.kind === "audio"
  readonly property bool media: audio || preview.kind === "video"
  readonly property size targetSize: Qt.size(Math.max(1, audio ? Math.min(width - Style.margin2XL, 620 * Style.uiScaleRatio) : width - Style.margin2XL), Math.max(1, audio ? Math.min(height - Style.margin2XL, sheetContent.implicitHeight + Style.marginL * 2) : height - Style.margin2XL))
  readonly property rect geometry: Qt.rect(sheet.x, sheet.y, sheet.width, sheet.height)
  readonly property real targetX: (width - targetSize.width) / 2
  readonly property real targetY: (height - targetSize.height) / 2
  signal closeRequested
  signal moveRequested(int delta)
  visible: opened
  clip: true

  FilePlayback {
    id: mediaPlayback
    active: root.opened && root.media
    looping: root.preview.kind === "video"
    source: root.sourceUrl
    videoOutput: root.preview.kind === "video" && mediaLoader.item ? mediaLoader.item.videoOutput : null
  }
  NScopedShortcut {
    scope: root
    sequence: "Space"
    enabled: root.opened
    onActivated: root.closeRequested()
  }
  NScopedShortcut {
    scope: root
    sequence: "Left"
    enabled: root.opened && (!transport.item || !transport.item.adjusting)
    onActivated: root.moveRequested(-1)
  }
  NScopedShortcut {
    scope: root
    sequence: "Right"
    enabled: root.opened && (!transport.item || !transport.item.adjusting)
    onActivated: root.moveRequested(1)
  }
  NScopedShortcut {
    scope: root
    sequence: "Up"
    enabled: root.opened && (!transport.item || !transport.item.adjusting)
    onActivated: root.moveRequested(-1)
  }
  NScopedShortcut {
    scope: root
    sequence: "Down"
    enabled: root.opened && (!transport.item || !transport.item.adjusting)
    onActivated: root.moveRequested(1)
  }
  NScopedShortcut {
    scope: root
    sequence: "Ctrl+P"
    enabled: root.opened && root.media
    onActivated: playback.toggle()
  }
  NScopedShortcut {
    scope: root
    sequence: "Ctrl+Left"
    enabled: root.opened && root.media
    onActivated: playback.seekBy(-5000)
  }
  NScopedShortcut {
    scope: root
    sequence: "Ctrl+Right"
    enabled: root.opened && root.media
    onActivated: playback.seekBy(5000)
  }
  NScopedShortcut {
    scope: root
    sequence: "Ctrl+Up"
    enabled: root.opened && root.media
    onActivated: playback.volumeBy(0.05)
  }
  NScopedShortcut {
    scope: root
    sequence: "Ctrl+Down"
    enabled: root.opened && root.media
    onActivated: playback.volumeBy(-0.05)
  }

  function openFrom(tile) {
    origin = tile;
    opened = true;
    forceActiveFocus();
    grow.restart();
  }
  Keys.onPressed: event => {
    if (event.modifiers !== Qt.NoModifier) {
      event.accepted = false;
      return;
    }
    event.accepted = true;
    if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape)
      closeRequested();
    else if ([Qt.Key_Left, Qt.Key_Up].includes(event.key))
      moveRequested(-1);
    else if ([Qt.Key_Right, Qt.Key_Down].includes(event.key))
      moveRequested(1);
    else
      event.accepted = false;
  }
  Rectangle {
    anchors.fill: parent
    color: AtmoColor.mSurface
    opacity: 0.85
  }
  MouseArea {
    anchors.fill: parent
    onClicked: root.closeRequested()
  }
  Rectangle {
    id: sheet
    x: root.targetX
    y: root.targetY
    width: root.targetSize.width
    height: root.targetSize.height
    color: AtmoColor.mSurfaceVariant
    radius: Style.radiusM
    border.width: Style.borderS
    border.color: AtmoColor.mOutline
    MouseArea {
      anchors.fill: parent
    }
    ParallelAnimation {
      id: grow
      NumberAnimation {
        target: sheet
        property: "x"
        from: root.origin.x
        to: root.targetX
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: sheet
        property: "y"
        from: root.origin.y
        to: root.targetY
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: sheet
        property: "width"
        from: root.origin.width
        to: root.targetSize.width
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: sheet
        property: "height"
        from: root.origin.height
        to: root.targetSize.height
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
    ColumnLayout {
      id: sheetContent
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM
      RowLayout {
        Layout.fillWidth: true
        NText {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          text: root.item ? root.item.name : ""
          pointSize: Style.fontSizeL
          elide: Text.ElideMiddle
        }
        ChooserButton {
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          onClicked: root.closeRequested()
        }
      }
      Loader {
        id: mediaLoader
        Layout.fillWidth: true
        Layout.fillHeight: !root.audio
        Layout.preferredHeight: root.audio ? implicitHeight : -1
        active: root.opened
        sourceComponent: root.preview.status === "error" ? information : ({
                                                                            image: stillImage,
                                                                            animatedImage: animatedImage,
                                                                            video: movingImage,
                                                                            audio: sound,
                                                                            text: textPreview,
                                                                            pdf: root.preview.pdfAvailable ? pdfPreview : information
                                                                          })[root.preview.kind] || information
      }
      Loader {
        id: transport
        Layout.fillWidth: true
        active: root.opened && root.media
        visible: active
        sourceComponent: FileMediaControls {
          playback: mediaPlayback
        }
      }
      RowLayout {
        Layout.fillWidth: true
        NText {
          text: root.item && !root.item.directory ? FileTypes.formatSize(root.item.size) : I18n.tr("widgets.file-picker.folder")
          pointSize: Style.fontSizeS
          features: ({
                       tnum: 1
                     })
          color: AtmoColor.mOnSurfaceVariant
        }
        Item {
          Layout.fillWidth: true
        }
        NText {
          text: root.item ? FileTypes.formatDate(root.item.modified) : ""
          pointSize: Style.fontSizeS
          features: ({
                       tnum: 1
                     })
          color: AtmoColor.mOnSurfaceVariant
        }
      }
    }
  }
  Component {
    id: stillImage
    Item {
      readonly property string previewState: image.status === Image.Ready ? "ready" : image.status === Image.Error ? "error" : "loading"
      readonly property size decodeSize: image.sourceSize
      Image {
        id: image
        anchors.fill: parent
        source: root.sourceUrl
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: root.targetSize.width * 2
        sourceSize.height: root.targetSize.height * 2
      }
      NText {
        anchors.centerIn: parent
        visible: image.status === Image.Error
        text: I18n.tr("widgets.file-picker.preview-unavailable")
      }
    }
  }
  Component {
    id: animatedImage
    Item {
      readonly property string previewState: animation.status === Image.Ready ? "ready" : animation.status === Image.Error ? "error" : "loading"
      readonly property int frame: animation.currentFrame
      readonly property int frames: animation.frameCount
      AnimatedImage {
        id: animation
        anchors.fill: parent
        source: root.sourceUrl
        fillMode: Image.PreserveAspectFit
        playing: root.opened && Style.animationNormal > 0
      }
      NText {
        anchors.centerIn: parent
        visible: animation.status === Image.Error
        text: I18n.tr("widgets.file-picker.preview-unavailable")
      }
    }
  }
  Component {
    id: movingImage
    Item {
      readonly property string previewState: playback.status === "error" ? "error" : video.sourceRect.width > 0 ? "ready" : "loading"
      readonly property real position: playback.position
      readonly property var videoOutput: video
      VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
      }
      NText {
        anchors.centerIn: parent
        visible: playback.status === "error"
        text: I18n.tr("widgets.file-picker.preview-unavailable")
      }
    }
  }
  Component {
    id: sound
    RowLayout {
      readonly property string previewState: playback.status
      readonly property real position: playback.position
      spacing: Style.marginL
      AtmoIcon {
        icon: Icon.filepickerMusic
        pointSize: Style.fontSizeXXXL * 2
        color: AtmoColor.mOnSurfaceVariant
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        NText {
          Layout.fillWidth: true
          visible: text !== ""
          text: playback.title !== (root.item ? root.item.name : "") ? playback.title : ""
          pointSize: Style.fontSizeM
        }
        NText {
          Layout.fillWidth: true
          visible: text !== ""
          text: playback.artist
          pointSize: Style.fontSizeM
        }
        NText {
          Layout.fillWidth: true
          visible: text !== ""
          text: playback.album
          pointSize: Style.fontSizeS
          color: AtmoColor.mOnSurfaceVariant
        }
        NText {
          Layout.fillWidth: true
          visible: playback.status === "error"
          text: I18n.tr("widgets.file-picker.preview-unavailable")
          color: AtmoColor.mError
        }
      }
    }
  }
  Component {
    id: textPreview
    ColumnLayout {
      readonly property string previewState: root.preview.status
      spacing: Style.marginM
      NText {
        id: textTypography
        visible: false
        pointSize: Style.fontSizeM
      }
      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        TextArea {
          readOnly: true
          selectByMouse: true
          text: root.preview.text
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          font: textTypography.font
          color: AtmoColor.mOnSurface
          background: null
        }
      }
      NText {
        visible: root.preview.truncated
        text: I18n.tr("widgets.file-picker.preview-truncated")
        pointSize: Style.fontSizeS
        color: AtmoColor.mOnSurfaceVariant
      }
    }
  }
  Component {
    id: pdfPreview
    Item {
      readonly property bool unavailable: pdf.status === Loader.Error || (!!pdf.item && pdf.item.previewState === "error")
      readonly property string previewState: unavailable ? "info" : pdf.item ? pdf.item.previewState : "loading"
      Loader {
        id: pdf
        anchors.fill: parent
        source: root.preview.pdfAvailable ? Qt.resolvedUrl("Optional/PdfQuickLook.qml") : ""
        onLoaded: item.source = Qt.binding(() => root.sourceUrl)
      }
      Loader {
        anchors.fill: parent
        active: parent.unavailable
        sourceComponent: information
      }
    }
  }
  Component {
    id: information
    ColumnLayout {
      readonly property string previewState: "info"
      Item {
        Layout.fillHeight: true
      }
      AtmoIcon {
        Layout.alignment: Qt.AlignHCenter
        icon: root.item ? FileTypes.icon(root.item.name, root.item.directory) : Icon.filepickerFile
        pointSize: Style.fontSizeXXXL * 3
        color: AtmoColor.mOnSurfaceVariant
      }
      NText {
        Layout.alignment: Qt.AlignHCenter
        text: root.item ? root.item.name : ""
        pointSize: Style.fontSizeL
      }
      NText {
        Layout.alignment: Qt.AlignHCenter
        text: root.preview.errorText || I18n.tr("widgets.file-picker.file-information")
        pointSize: Style.fontSizeS
        color: AtmoColor.mOnSurfaceVariant
      }
      Item {
        Layout.fillHeight: true
      }
    }
  }
}
