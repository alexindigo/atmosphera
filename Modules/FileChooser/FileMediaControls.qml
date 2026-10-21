import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  required property var playback
  readonly property bool adjusting: positionSlider.activeFocus || volumeSlider.activeFocus
  function controlGeometry() {
    return [positionRow, volumeRow].map(row => Array.from(row.children).filter(control => control.visible).map(control => ({x: control.x, y: control.y, width: control.width, height: control.height, center: control.y + control.height / 2})));
  }
  spacing: Style.marginM
  RowLayout {
    id: positionRow
    Layout.fillWidth: true
    spacing: Style.marginM
    ChooserButton {
      primary: true
      icon: root.playback.playing ? Icon.mediaPause : Icon.mediaPlay
      text: root.playback.playing ? I18n.tr("widgets.file-picker.pause") : I18n.tr("widgets.file-picker.play")
      onClicked: root.playback.toggle()
    }
    NText { text: root.playback.time(root.playback.position); features: ({tnum: 1}); pointSize: Style.fontSizeS }
    ChooserSlider {
      id: positionSlider
      Layout.fillWidth: true
      activeFocusOnTab: true
      Accessible.name: I18n.tr("widgets.file-picker.playback-position")
      from: 0
      to: Math.max(1, root.playback.duration)
      value: root.playback.position
      stepSize: 1000
      enabled: root.playback.seekable
      cutoutColor: AtmoColor.mSurfaceVariant
      onMoved: root.playback.seek(value)
    }
    NText { text: root.playback.time(root.playback.duration); features: ({tnum: 1}); pointSize: Style.fontSizeS }
  }
  RowLayout {
    id: volumeRow
    Layout.fillWidth: true
    spacing: Style.marginM
    AtmoIcon { icon: root.playback.volume === 0 ? Icon.volumeMute : Icon.volumeHigh; pointSize: Style.fontSizeM; color: AtmoColor.mOnSurfaceVariant }
    ChooserSlider {
      id: volumeSlider
      Layout.fillWidth: true
      activeFocusOnTab: true
      Accessible.name: I18n.tr("widgets.file-picker.volume")
      from: 0
      to: 1
      value: root.playback.volume
      stepSize: 0.05
      cutoutColor: AtmoColor.mSurfaceVariant
      onMoved: root.playback.setVolume(value)
    }
    NText { text: Math.round(root.playback.volume * 100) + "%"; features: ({tnum: 1}); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant }
  }
}
