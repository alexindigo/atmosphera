import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string density: Settings.data.bar.density
  readonly property real itemSize: (density === "compact") ? Style.capsuleHeight * 0.9 : Style.capsuleHeight * 0.8

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : (widgetMetadata.hideMode !== undefined ? widgetMetadata.hideMode : "hidden")

  property int __filteredCount: 0
  readonly property bool __onlySameOutput: widgetSettings.onlySameOutput === undefined ? widgetMetadata.onlySameOutput : widgetSettings.onlySameOutput
  readonly property bool __onlyActiveWorkspaces: widgetSettings.onlyActiveWorkspaces === undefined ? widgetMetadata.onlyActiveWorkspaces : widgetSettings.onlyActiveWorkspaces
  function __updateFilteredCount() {
    try {
      var count = 0
      var total = CompositorService.windows.count || 0
      var activeIds = CompositorService.getActiveWorkspaces().map(function(ws) { return ws.id })
      for (var i = 0; i < total; i++) {
        var w = CompositorService.windows.get(i)
        if (!w)
          continue
        var passOutput = (!__onlySameOutput) || (w.output == screen.name)
        var passWorkspace = (!__onlyActiveWorkspaces) || (activeIds.includes(w.workspaceId))
        if (passOutput && passWorkspace) {
          count++
        }
      }
      __filteredCount = count
    } catch (e) {
      __filteredCount = 0
    }
  }

  Component.onCompleted: __updateFilteredCount()
  Connections {
    target: CompositorService
    function onWindowListChanged() { __updateFilteredCount() }
    function onWorkspaceChanged() { __updateFilteredCount() }
  }
  onScreenChanged: __updateFilteredCount()

  visible: hideMode !== "hidden" || __filteredCount > 0
  opacity: (hideMode !== "transparent" || __filteredCount > 0) ? 1.0 : 0
  Behavior on opacity { NumberAnimation { duration: Style.animationNormal; easing.type: Easing.OutCubic } }

  implicitWidth: visible ? (isVerticalBar ? Style.capsuleHeight : Math.round(taskbarLayout.implicitWidth + Style.marginM * 2)) : 0
  implicitHeight: visible ? (isVerticalBar ? Math.round(taskbarLayout.implicitHeight + Style.marginM * 2) : Style.capsuleHeight) : 0
  radius: Style.radiusM
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  GridLayout {
    id: taskbarLayout
    anchors.fill: parent
    anchors {
      leftMargin: isVerticalBar ? undefined : Style.marginM
      rightMargin: isVerticalBar ? undefined : Style.marginM
      topMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
      bottomMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
    }

    // Configure GridLayout to behave like RowLayout or ColumnLayout
    rows: isVerticalBar ? -1 : 1 // -1 means unlimited
    columns: isVerticalBar ? 1 : -1 // -1 means unlimited

    rowSpacing: isVerticalBar ? Style.marginXXS : 0
    columnSpacing: isVerticalBar ? 0 : Style.marginXXS

    Repeater {
      model: CompositorService.windows
      delegate: Item {
        id: taskbarItem
        required property var modelData
        property ShellScreen screen: root.screen

  visible: (!__onlySameOutput || modelData.output == screen.name) && (!__onlyActiveWorkspaces || CompositorService.getActiveWorkspaces().map(function(ws){ return ws.id }).includes(modelData.workspaceId))

        Layout.preferredWidth: root.itemSize
        Layout.preferredHeight: root.itemSize
        Layout.alignment: Qt.AlignCenter

        IconImage {

          id: appIcon
          width: parent.width
          height: parent.height
          source: ThemeIcons.iconForAppId(taskbarItem.modelData.appId)
          smooth: true
          asynchronous: true
          opacity: modelData.isFocused ? Style.opacityFull : 0.6

          // Apply dock shader to all taskbar icons
          layer.enabled: widgetSettings.colorizeIcons !== false
          layer.effect: ShaderEffect {
            property color targetColor: Color.mOnSurface
            property real colorizeMode: 0.0 // Dock mode (grayscale)

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }

          Rectangle {
            anchors.bottomMargin: -2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            id: iconBackground
            width: 4
            height: 4
            color: modelData.isFocused ? Color.mPrimary : Color.transparent
            radius: width * 0.5
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton

          onPressed: function (mouse) {
            if (!taskbarItem.modelData)
              return

            if (mouse.button === Qt.LeftButton) {
              try {
                CompositorService.focusWindow(taskbarItem.modelData)
              } catch (error) {
                Logger.error("Taskbar", "Failed to activate toplevel: " + error)
              }
            } else if (mouse.button === Qt.RightButton) {
              try {
                CompositorService.closeWindow(taskbarItem.modelData)
              } catch (error) {
                Logger.error("Taskbar", "Failed to close toplevel: " + error)
              }
            }
          }
          onEntered: TooltipService.show(Screen, taskbarItem, taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown app.", BarService.getTooltipDirection())
          onExited: TooltipService.hide()
        }
      }
    }
  }
}
