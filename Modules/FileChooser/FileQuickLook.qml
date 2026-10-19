import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import qs.Commons
import qs.Services.Files
import qs.Widgets
import "../../Helpers/PortalPaths.js" as PortalPaths

FocusScope {
  id: root
  required property var preview
  property bool opened: false
  property rect origin: Qt.rect(0, 0, 1, 1)
  readonly property var item: preview.item
  readonly property string sourceUrl: preview.path ? PortalPaths.pathToUri(preview.path).uri : ""
  readonly property var renderer: mediaLoader.item
  readonly property bool expanding: grow.running
  readonly property rect geometry: Qt.rect(sheet.x, sheet.y, sheet.width, sheet.height)
  signal closeRequested
  signal moveRequested(int delta)
  visible: opened
  clip: true
  Shortcut { sequence: "Space"; enabled: root.opened; onActivated: root.closeRequested() }
  Shortcut { sequence: "Left"; enabled: root.opened; onActivated: root.moveRequested(-1) }
  Shortcut { sequence: "Right"; enabled: root.opened; onActivated: root.moveRequested(1) }
  Shortcut { sequence: "Up"; enabled: root.opened; onActivated: root.moveRequested(-1) }
  Shortcut { sequence: "Down"; enabled: root.opened; onActivated: root.moveRequested(1) }

  function openFrom(tile) {
    origin = tile;
    opened = true;
    forceActiveFocus();
    grow.restart();
  }
  Keys.onPressed: event => {
    event.accepted = true;
    if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape) closeRequested();
    else if ([Qt.Key_Left, Qt.Key_Up].includes(event.key)) moveRequested(-1);
    else if ([Qt.Key_Right, Qt.Key_Down].includes(event.key)) moveRequested(1);
    else event.accepted = false;
  }
  Rectangle { anchors.fill: parent; color: AtmoColor.mSurface; opacity: 0.85 }
  MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
  Rectangle {
    id: sheet
    x: Style.marginXL
    y: Style.marginXL
    width: root.width - Style.margin2XL
    height: root.height - Style.margin2XL
    color: AtmoColor.mSurfaceVariant
    radius: Style.radiusM
    border.width: Style.borderS
    border.color: AtmoColor.mOutline
    MouseArea { anchors.fill: parent }
    ParallelAnimation {
      id: grow
      NumberAnimation { target: sheet; property: "x"; from: root.origin.x; to: Style.marginXL; duration: Style.animationNormal; easing.type: Easing.OutCubic }
      NumberAnimation { target: sheet; property: "y"; from: root.origin.y; to: Style.marginXL; duration: Style.animationNormal; easing.type: Easing.OutCubic }
      NumberAnimation { target: sheet; property: "width"; from: root.origin.width; to: root.width - Style.margin2XL; duration: Style.animationNormal; easing.type: Easing.OutCubic }
      NumberAnimation { target: sheet; property: "height"; from: root.origin.height; to: root.height - Style.margin2XL; duration: Style.animationNormal; easing.type: Easing.OutCubic }
    }
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM
      RowLayout {
        Layout.fillWidth: true
        NText { Layout.fillWidth: true; text: root.item ? root.item.name : ""; pointSize: Style.fontSizeL }
        ChooserButton { icon: Icon.close; tooltipText: I18n.tr("common.close"); onClicked: root.closeRequested() }
      }
      Loader {
        id: mediaLoader
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.opened
        sourceComponent: root.preview.status === "error" ? information : ({image: stillImage, animatedImage: animatedImage, video: movingImage, audio: sound, text: textPreview, pdf: root.preview.pdfAvailable ? pdfPreview : information})[root.preview.kind] || information
      }
      RowLayout {
        Layout.fillWidth: true
        NText { text: root.item && !root.item.directory ? FileTypes.formatSize(root.item.size) : I18n.tr("widgets.file-picker.folder"); pointSize: Style.fontSizeS; features: ({tnum: 1}); color: AtmoColor.mOnSurfaceVariant }
        Item { Layout.fillWidth: true }
        NText { text: root.item ? FileTypes.formatDate(root.item.modified) : ""; pointSize: Style.fontSizeS; features: ({tnum: 1}); color: AtmoColor.mOnSurfaceVariant }
      }
    }
  }
  Component {
    id: stillImage
    Item {
      readonly property string previewState: image.status === Image.Ready ? "ready" : image.status === Image.Error ? "error" : "loading"
      Image { id: image; anchors.fill: parent; source: root.sourceUrl; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: width * 2; sourceSize.height: height * 2 }
      NText { anchors.centerIn: parent; visible: image.status === Image.Error; text: I18n.tr("widgets.file-picker.preview-unavailable") }
    }
  }
  Component {
    id: animatedImage
    Item {
      readonly property string previewState: animation.status === Image.Ready ? "ready" : animation.status === Image.Error ? "error" : "loading"
      readonly property int frame: animation.currentFrame
      readonly property int frames: animation.frameCount
      AnimatedImage { id: animation; anchors.fill: parent; source: root.sourceUrl; fillMode: Image.PreserveAspectFit; playing: root.opened && Style.animationNormal > 0 }
      NText { anchors.centerIn: parent; visible: animation.status === Image.Error; text: I18n.tr("widgets.file-picker.preview-unavailable") }
    }
  }
  Component {
    id: movingImage
    Item {
      readonly property string previewState: player.error !== MediaPlayer.NoError ? "error" : player.hasVideo && video.sourceRect.width > 0 ? "ready" : "loading"
      readonly property int position: player.position
      MediaPlayer {
        id: player
        source: root.sourceUrl
        videoOutput: video
        audioOutput: AudioOutput {}
        autoPlay: true
        loops: MediaPlayer.Infinite
      }
      VideoOutput { id: video; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
      NText { anchors.centerIn: parent; visible: player.error !== MediaPlayer.NoError; text: I18n.tr("widgets.file-picker.preview-unavailable") }
    }
  }
  Component {
    id: sound
    Item {
      readonly property string previewState: player.error !== MediaPlayer.NoError ? "error" : player.hasAudio ? "ready" : "loading"
      readonly property int position: player.position
      MediaPlayer {
        id: player
        source: root.sourceUrl
        audioOutput: AudioOutput {}
        autoPlay: true
      }
      ColumnLayout {
        anchors.centerIn: parent
        spacing: Style.marginXL
        AtmoIcon { Layout.alignment: Qt.AlignHCenter; icon: Icon.filepickerMusic; pointSize: Style.fontSizeXXXL * 3; color: AtmoColor.mPrimary }
        NText { text: player.error !== MediaPlayer.NoError ? I18n.tr("widgets.file-picker.preview-unavailable") : root.item ? root.item.name : "" }
        ChooserButton { Layout.alignment: Qt.AlignHCenter; text: player.playbackState === MediaPlayer.PlayingState ? I18n.tr("widgets.file-picker.pause") : I18n.tr("widgets.file-picker.play"); onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
      }
    }
  }
  Component {
    id: textPreview
    ColumnLayout {
      readonly property string previewState: root.preview.status
      spacing: Style.marginM
      NText { id: textTypography; visible: false; pointSize: Style.fontSizeM }
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
      NText { visible: root.preview.truncated; text: I18n.tr("widgets.file-picker.preview-truncated"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant }
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
      Loader { anchors.fill: parent; active: parent.unavailable; sourceComponent: information }
    }
  }
  Component {
    id: information
    ColumnLayout {
      readonly property string previewState: "info"
      Item { Layout.fillHeight: true }
      AtmoIcon { Layout.alignment: Qt.AlignHCenter; icon: root.item ? FileTypes.icon(root.item.name, root.item.directory) : Icon.filepickerFile; pointSize: Style.fontSizeXXXL * 3; color: AtmoColor.mOnSurfaceVariant }
      NText { Layout.alignment: Qt.AlignHCenter; text: root.item ? root.item.name : ""; pointSize: Style.fontSizeL }
      NText { Layout.alignment: Qt.AlignHCenter; text: root.preview.errorText || I18n.tr("widgets.file-picker.file-information"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant }
      Item { Layout.fillHeight: true }
    }
  }
}
