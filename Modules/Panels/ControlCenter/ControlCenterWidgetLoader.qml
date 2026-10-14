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
  // Shortcut list the widget is placed in ("left" or "right"); the placement
  // of a plugin instance (plugin-instances design, 4).
  property string listSection: ""

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

  // Initial properties handed to the plugin widget currently being loaded
  property var _pluginInitial: null
  property string _pluginUrl: ""

  // Context for a plugin widget: the placement's widgetProps plus the screen.
  // PluginLoader hands over only the names the entry file declares.
  function _pluginContext() {
    var ctx = {
      "screen": widgetScreen
    };
    var props = widgetProps || {};
    for (var key in props)
      ctx[key] = props[key];
    return ctx;
  }

  readonly property var _currentContext: _pluginContext()
  on_CurrentContextChanged: {
    if (_isPlugin) {
      PluginLoader.applyLateContext(loader.item, "controlCenterWidget", _currentContext, {});
      _repointInstanceApi();
    }
  }

  // The plugin instance this widget is placed as. A move changes the placement,
  // so the loaded widget is handed the api of its new place.
  function _instancePlacement() {
    return {
      "kind": "controlCenter",
      "section": root.listSection,
      "index": root.sectionIndex
    };
  }

  function _instanceApi() {
    return PluginInstances.apiFor(root.widgetId.substring(7), _instancePlacement());
  }

  function _repointInstanceApi() {
    if (!loader.item || !("pluginApi" in loader.item))
      return;
    var api = _instanceApi();
    if (api && loader.item.pluginApi !== api)
      loader.item.pluginApi = api;
  }

  onListSectionChanged: _repointInstanceApi()

  function _loadPluginWidget() {
    var comp = root._registeredComponent;
    if (!comp) {
      // Unregistered: the widget must not stay loaded
      loader.source = "";
      return;
    }
    var pluginKey = widgetId.substring(7); // Remove "plugin:" prefix
    _pluginUrl = String(comp.url);
    if (!_pluginUrl) {
      loader.sourceComponent = null;
      PluginLoader.recordLoadFailure(pluginKey, "controlCenterWidget", comp, _pluginUrl);
      return;
    }
    _pluginInitial = PluginLoader.initialProperties("controlCenterWidget", _pluginUrl, _instanceApi(), _currentContext);
    loader.setSource(_pluginUrl, _pluginInitial);
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false

    // Core widgets use sourceComponent; plugin widgets use setSource() so the
    // context names the entry file declares are set from the first binding evaluation.
    Component.onCompleted: {
      if (root._isPlugin) {
        root._loadPluginWidget();
      } else {
        sourceComponent = Qt.binding(function () {
          return ControlCenterWidgetRegistry.getWidget(widgetId);
        });
      }
    }

    onStatusChanged: {
      if (status === Loader.Error && root._isPlugin)
        PluginLoader.recordLoadFailure(root.widgetId.substring(7), "controlCenterWidget", sourceComponent, root._pluginUrl);
    }

    onLoaded: {
      if (!item)
        return;

      if (root._isPlugin) {
        PluginLoader.applyLateContext(item, "controlCenterWidget", root._currentContext, root._pluginInitial);
      } else {
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
