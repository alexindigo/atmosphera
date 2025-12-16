import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Variants {
  id: root
  model: Quickshell.screens

  // Direct binding to registry's widgets property for reactivity
  readonly property var registeredWidgets: DesktopWidgetRegistry.widgets

  delegate: Loader {
    id: screenLoader
    required property ShellScreen modelData

    // Reactive property for widgets on this specific screen
    property var screenWidgets: {
      if (!modelData || !modelData.name) {
        return [];
      }
      var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
      for (var i = 0; i < monitorWidgets.length; i++) {
        if (monitorWidgets[i].name === modelData.name) {
          return monitorWidgets[i].widgets || [];
        }
      }
      return [];
    }

    // Only create PanelWindow if enabled AND screen has widgets
    active: modelData && Settings.data.desktopWidgets.enabled && screenWidgets.length > 0

    sourceComponent: PanelWindow {
      id: window
      color: Color.transparent
      screen: screenLoader.modelData

      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-desktop-widgets-" + (screen?.name || "unknown")

      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      Component.onCompleted: {
        Logger.d("DesktopWidgets", "Created panel window for", screen?.name);
      }

      Item {
        id: widgetsContainer
        anchors.fill: parent

        // Load widgets dynamically from per-monitor array
        Repeater {
          model: screenLoader.screenWidgets

          delegate: Loader {
            id: widgetLoader
            // Bind to registeredWidgets to re-evaluate when plugins register/unregister
            active: (modelData.id in root.registeredWidgets)

            property var widgetData: modelData
            property int widgetIndex: index

            sourceComponent: {
              // Access registeredWidgets to create reactive binding
              var widgets = root.registeredWidgets;
              return widgets[modelData.id] || null;
            }

            onLoaded: {
              if (item) {
                item.screen = window.screen;
                item.parent = widgetsContainer;
                item.widgetData = widgetData;
                item.widgetIndex = widgetIndex;

                // Inject plugin API for plugin widgets
                if (DesktopWidgetRegistry.isPluginWidget(modelData.id)) {
                  var pluginId = modelData.id.replace("plugin:", "");
                  var api = PluginService.getPluginAPI(pluginId);
                  if (api && item.hasOwnProperty("pluginApi")) {
                    item.pluginApi = api;
                  }
                }
              }
            }
          }
        }

        // Exit edit mode button
        NButton {
          id: editModeButton
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled

          readonly property string barPos: Settings.data.bar.position || "top"
          readonly property bool barFloating: Settings.data.bar.floating || false
          // Calculate offset from bar based on position and floating state
          readonly property int barOffsetTop: {
            if (barPos !== "top")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginV = barFloating ? Math.ceil(Settings.data.bar.marginVertical * Style.marginXL) : 0;
            return Style.barHeight + floatMarginV + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }
          readonly property int barOffsetRight: {
            if (barPos !== "right")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal * Style.marginXL) : 0;
            return Style.barHeight + floatMarginH + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }

          anchors {
            top: parent.top
            right: parent.right
            topMargin: barOffsetTop
            rightMargin: barOffsetRight
          }
          text: I18n.tr("settings.desktop-widgets.edit-mode.exit-button")
          icon: "check"
          backgroundColor: Color.mSurface
          textColor: Color.mOnSurface
          hoverColor: Color.mSurfaceVariant
          outlined: false
          fontSize: Style.fontSizeM * 1.1
          iconSize: Style.fontSizeL * 1.1
          z: 10000
          onClicked: Settings.data.desktopWidgets.editMode = false
        }

        // Controls explanation text
        NText {
          id: controlsExplanation
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled
          anchors {
            top: editModeButton.bottom
            right: parent.right
            topMargin: Style.marginM
            rightMargin: editModeButton.barOffsetRight
          }
          text: I18n.tr("settings.desktop-widgets.edit-mode.controls-explanation")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignRight
          wrapMode: Text.WordWrap
          width: Math.min(implicitWidth, 300 * Style.uiScaleRatio)
          z: 10000
        }
      }
    }
  }
}
