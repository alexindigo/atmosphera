import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["AppShortcut"]
  readonly property string appId: (widgetData && widgetData.appId !== undefined) ? widgetData.appId : widgetMetadata.appId
  readonly property string customLabel: (widgetData && widgetData.customLabel !== undefined) ? widgetData.customLabel : widgetMetadata.customLabel
  readonly property bool showLabel: (widgetData && widgetData.showLabel !== undefined) ? widgetData.showLabel : widgetMetadata.showLabel
  readonly property bool singleClick: (widgetData && widgetData.singleClick !== undefined) ? widgetData.singleClick : widgetMetadata.singleClick

  readonly property var _entry: appId ? ThemeIcons.findAppEntry(appId) : null
  readonly property string _displayLabel: customLabel || (_entry ? _entry.name : "")

  implicitWidth: 80 * widgetScale
  implicitHeight: (showLabel ? 108 : 80) * widgetScale
  width: implicitWidth
  height: implicitHeight

  Item {
    anchors.fill: parent
    scale: pressArea.pressed ? 0.95 : 1.0
    Behavior on scale {
      NumberAnimation {
        duration: 80
        easing.type: Easing.OutQuad
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 4 * root.widgetScale

      Image {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 64 * root.widgetScale
        Layout.preferredHeight: 64 * root.widgetScale
        source: root._entry ? ThemeIcons.iconForAppId(root.appId) : ""
        smooth: true
        asynchronous: true
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        visible: root.showLabel
        text: root._displayLabel
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: "white"
        font.pointSize: Math.max(1, Style.fontSizeS * root.widgetScale)
      }
    }

    MouseArea {
      id: pressArea
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      enabled: !DesktopWidgetRegistry.editMode && root._entry !== null
      onClicked: if (root.singleClick)
                   root.launch()
      onDoubleClicked: root.launch()
    }
  }

  function launch() {
    if (!_entry)
      return;
    if (_entry.command && _entry.command.length > 0)
      CompositorService.spawn(_entry.command);
    else if (_entry.execute)
      _entry.execute();
  }
}
