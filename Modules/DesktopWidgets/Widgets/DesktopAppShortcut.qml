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
  readonly property real _blendStrength: widgetData?.blendStrength ?? Settings.data.desktopWidgets.iconBlendStrength
  readonly property real _hueAdjustment: widgetData?.hueAdjustment ?? Settings.data.desktopWidgets.iconHueAdjustment

  readonly property var _entry: appId ? ThemeIcons.findAppEntry(appId) : null
  readonly property string _displayLabel: customLabel || (_entry ? _entry.name : appId)

  readonly property string _iconName: {
    var iconType = (widgetData && widgetData.iconType) || "auto";
    var iconSrc = (widgetData && widgetData.iconSource) || "";
    if (iconType === "file" && iconSrc)
      return iconSrc;
    if (iconType === "icons" && iconSrc)
      return iconSrc;
    if (iconType === "theme" && iconSrc)
      return iconSrc;
    if (appId)
      return ThemeIcons.iconNameForAppId(appId);
    return "";
  }

  // Extra params from widget data (e.g. ["-e", "neomutt"] or ["--xwayland"])
  readonly property var _params: (widgetData && widgetData.params) || []

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

      AtmoIcon {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 64 * root.widgetScale
        Layout.preferredHeight: 64 * root.widgetScale
        name: root._iconName
        size: 64 * root.widgetScale
        layer.enabled: true
        layer.smooth: true
        layer.effect: NIconColorizeEffect {
          targetColor: Color.mPrimary
          blendStrength: root._blendStrength
          hueAdjustment: root._hueAdjustment
        }
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
      enabled: !DesktopWidgetRegistry.editMode && root.appId !== ""
      onClicked: if (root.singleClick)
                   root.launch()
      onDoubleClicked: root.launch()
    }
  }

  function _shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  function launch() {
    if (!appId)
      return;

    var envVars = (widgetData && widgetData.environmentVars) || [];
    var params = root._params;
    var baseCmd = (_entry && _entry.command) || [];

    // Build the full command: entry.command + params
    var fullCmd = baseCmd.slice();
    for (var i = 0; i < params.length; i++) {
      fullCmd.push(String(params[i]));
    }

    if (fullCmd.length > 0) {
      if (envVars.length > 0) {
        var envParts = [];
        for (var i = 0; i < envVars.length; i++) {
          var kv = envVars[i];
          if (kv && kv.key && kv.key.trim() !== "") {
            envParts.push(kv.key.trim() + "=" + _shellQuote(kv.value || ""));
          }
        }

        if (envParts.length > 0) {
          var cmdParts = [];
          for (var j = 0; j < fullCmd.length; j++) {
            var c = fullCmd[j];
            cmdParts.push(c.includes(" ") ? _shellQuote(c) : c);
          }
          CompositorService.spawn(["sh", "-c", "env " + envParts.join(" ") + " " + cmdParts.join(" ")]);
        } else {
          CompositorService.spawn(fullCmd);
        }
      } else {
        CompositorService.spawn(fullCmd);
      }
    } else if (_entry && _entry.execute) {
      _entry.execute();
    }
  }
}
