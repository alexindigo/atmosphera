import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root
  required property var settings
  property bool resizeAvailable: true
  signal resizeRequested(real dx, real dy)
  spacing: Style.marginM
  function controls() {
    return [thumbnails, zoomOut, slider, zoomIn, resizeGrip].filter(item => item.visible).map(item => ({
      name: item.Accessible.name,
      x: item.x,
      y: item.y,
      width: item.width,
      height: item.height
    }));
  }
    function resizeGeometry() {
    var r = resizeGrip.mapToItem(root, 0, 0, resizeGrip.width, resizeGrip.height);
    return {
    x: r.x,
    y: r.y,
    width: r.width,
    height: r.height
  };
  }
    ChooserCheckBox {
    id: thumbnails
    Layout.fillHeight: true
    accessibleName: I18n.tr("widgets.file-picker.thumbnails")
    label: accessibleName
    checked: root.settings.thumbnails
    onToggled: value => root.settings.thumbnails = value
  }
    Item {
    Layout.fillWidth: true
  }
    ChooserButton {
    id: zoomOut
    icon: "zoom-out"
    tooltipText: I18n.tr("widgets.file-picker.zoom-out")
    visible: root.settings.zoom > 0
    onClicked: root.settings.zoomBy(-1)
  }
    ChooserSlider {
    id: slider
    Layout.fillHeight: true
    Layout.preferredWidth: 150 * Style.uiScaleRatio
    Accessible.name: I18n.tr("widgets.file-picker.zoom")
    from: 0
    to: 6
    stepSize: 1
    value: root.settings.zoom
    onMoved: root.settings.setZoom(value)
    Keys.onPressed: event => {
    if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
    root.settings.setZoom(event.key === Qt.Key_Home ? 0 : 6);
    event.accepted = true;
  } else
    event.accepted = false;
  }
  }
    ChooserButton {
    id: zoomIn
    icon: "zoom-in"
    tooltipText: I18n.tr("widgets.file-picker.zoom-in")
    visible: root.settings.zoom < 6
    onClicked: root.settings.zoomBy(1)
  }
    FileDialogResizeGrip {
    id: resizeGrip
    Layout.preferredWidth: zoomIn.implicitHeight
    Layout.preferredHeight: zoomIn.implicitHeight
    visible: root.resizeAvailable
    onResizeRequested: (dx, dy) => root.resizeRequested(dx, dy)
  }
  }
