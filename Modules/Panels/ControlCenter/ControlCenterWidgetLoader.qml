import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

Item {
  id: root

  required property string widgetId
  required property var widgetScreen
  required property var widgetProps

  property string section: widgetProps && widgetProps.section || ""
  property int sectionIndex: widgetProps && widgetProps.sectionWidgetIndex || 0

  // Don't reserve space unless the loaded widget is really visible
  implicitWidth: getImplicitSize(loader.item, "implicitWidth")
  implicitHeight: getImplicitSize(loader.item, "implicitHeight")

  function getImplicitSize(item, prop) {
    return (item && item.visible) ? item[prop] : 0;
  }

  readonly property bool _isPlugin: ControlCenterWidgetRegistry.isPluginWidget(widgetId)

  // The component registered under this id, re-evaluated whenever the registry
  // publishes a change (plugin registered, re-registered or unregistered).
  readonly property var _registeredComponent: ControlCenterWidgetRegistry.getWidget(widgetId)
  on_RegisteredComponentChanged: {
    if (root._isPlugin)
      root._loadPluginWidget();
  }

  function _loadPluginWidget() {
    var comp = root._registeredComponent;
    if (!comp) {
      // Unregistered: the widget must not stay loaded
      loader.source = "";
      return;
    }
    var pluginId = widgetId.substring(7); // Remove "plugin:" prefix
    var api = Service.getPluginAPI(pluginId);
    loader.setSource(comp.url, api ? {
                                       "pluginApi": api
                                     } : {});
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false

    // Core widgets use sourceComponent; plugin widgets use setSource()
    // so pluginApi is available from the first binding evaluation.
    Component.onCompleted: {
      if (root._isPlugin) {
        root._loadPluginWidget();
      } else {
        sourceComponent = Qt.binding(function () {
          return ControlCenterWidgetRegistry.getWidget(widgetId);
        });
      }
    }

    onLoaded: {
      if (!item)
        return;

      // Apply properties to loaded widget
      for (var prop in widgetProps) {
        if (item.hasOwnProperty(prop)) {
          item[prop] = widgetProps[prop];
        }
      }

      // Set screen property
      if (item.hasOwnProperty("screen")) {
        item.screen = widgetScreen;
      }

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded();
      }
    }

    Component.onDestruction: {
      // Explicitly clear references
      widgetProps = null;
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!ControlCenterWidgetRegistry.hasWidget(widgetId))
      Logger.w("ControlCenterWidgetLoader", "Widget not found in registry (waiting for registration):", widgetId);
  }
}
