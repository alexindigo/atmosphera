import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  required property string widgetId
  required property var widgetScreen
  required property var widgetProps

  // Extract section info from widgetProps
  readonly property string section: widgetProps ? (widgetProps.section || "") : ""
  readonly property int sectionIndex: widgetProps ? (widgetProps.sectionWidgetIndex || 0) : 0

  // Store registration key at registration time so unregistration always uses the correct key,
  // even if binding properties (section, sectionIndex) have changed by destruction time
  property string _regScreen: ""
  property string _regSection: ""
  property string _regWidgetId: ""
  property int _regIndex: -1

  function _unregister() {
    if (_regScreen !== "") {
      BarService.unregisterWidget(_regScreen, _regSection, _regWidgetId, _regIndex);
      _regScreen = "";
    }
  }

  // Bar orientation and height for extended click areas
  readonly property string barPosition: Settings.getBarPositionForScreen(widgetScreen?.name)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(widgetScreen?.name)

  // Request full bar dimension from layout to extend click areas above/below widgets
  // For horizontal bars: full bar height, widget's content width
  // For vertical bars: full bar width, widget's content height
  implicitWidth: isVerticalBar ? barHeight : getImplicitSize(loader.item, "implicitWidth")
  implicitHeight: isVerticalBar ? getImplicitSize(loader.item, "implicitHeight") : barHeight

  // Remove layout space left by hidden widgets
  visible: loader.item ? ((loader.item.opacity > 0.0) || (loader.item.hasOwnProperty("hideMode") && loader.item.hideMode === "transparent")) : false

  function getImplicitSize(item, prop) {
    return (item && item.visible) ? Math.round(item[prop]) : 0;
  }

  // Only load if widget exists in registry
  function checkWidgetExists(): bool {
    return root.widgetId !== "" && BarWidgetRegistry.hasWidget(root.widgetId);
  }

  // A plugin widget whose plugin is still installed but momentarily
  // unloadable keeps its slot: the placeholder renders until the real
  // widget returns (mark-and-remember, no deletion from the layout).
  // The registry's widget map is not a reactive property, so this answer is
  // re-evaluated on every plugin registry update (reloadCounter). Without that
  // a delegate created before its widget registered kept the placeholder answer.
  readonly property bool _pluginUnavailable: (root.reloadCounter >= 0) && root._isPlugin && !BarWidgetRegistry.hasWidget(root.widgetId) && Registry.isPluginDownloaded(root.widgetId.substring(7))

  // Force reload counter - incremented when plugin widget registry changes
  property int reloadCounter: 0

  // Listen for plugin widget registry changes to force reload — in BOTH
  // directions (real widget when the plugin returns, placeholder when its
  // widget unregisters while the plugin stays installed).
  Connections {
    target: BarWidgetRegistry
    enabled: BarWidgetRegistry.isPluginWidget(root.widgetId)

    function onPluginWidgetRegistryUpdated() {
      root.reloadCounter++;
      if (loader.active)
        root._loadWidget();
      Logger.d("BarWidgetLoader", "Plugin widget registry updated, reloading:", root.widgetId);
    }
  }

  readonly property bool _isPlugin: BarWidgetRegistry.isPluginWidget(widgetId)

  // Values for the bar widget's context names (shared-loader design 3.1,
  // barWidget). Core widgets get them as initial properties, so they are
  // available during Component.onCompleted and registration keys built from
  // screen.name / section / sectionWidgetIndex stay correct. Plugin widgets get
  // them through PluginLoader, which hands over only the names they declare.
  function _contextProps() {
    var props = widgetProps || {};
    return {
      "screen": widgetScreen,
      "widgetId": props.widgetId || "",
      "section": props.section || "",
      "sectionWidgetIndex": props.sectionWidgetIndex || 0,
      "sectionWidgetsCount": props.sectionWidgetsCount || 0
    };
  }

  // A reactive snapshot owns delivery both during and after asynchronous load.
  readonly property var _currentContext: _contextProps()
  on_CurrentContextChanged: {
    if (_isPlugin) {
      PluginLoader.applyLateContext(loader.item, "barWidget", _currentContext, {});
      _repointInstanceApi();
    }
  }

  // The plugin instance this widget is placed as (plugin-instances design, 4).
  // A move in the bar changes the placement, so the loaded widget is handed the
  // api of its new place.
  function _instancePlacement() {
    return {
      "kind": "bar",
      "list": PluginInstances.barList(root.widgetScreen ? root.widgetScreen.name : ""),
      "section": root.section,
      "index": root.sectionIndex
    };
  }

  function _instanceApi() {
    return PluginInstances.apiFor(root.widgetId.replace("plugin:", ""), _instancePlacement());
  }

  function _repointInstanceApi() {
    if (!loader.item || !("pluginApi" in loader.item))
      return;
    var api = _instanceApi();
    if (api && loader.item.pluginApi !== api)
      loader.item.pluginApi = api;
  }

  // Initial properties handed to the plugin widget currently being loaded
  property var _pluginInitial: null
  property string _pluginUrl: ""

  // Core widget URLs: file names match widget IDs exactly
  readonly property string _barWidgetsDir: Quickshell.shellDir + "/Modules/Bar/Widgets/"

  function _loadWidget() {
    if (root._pluginUnavailable) {
      loader.sourceComponent = placeholderComponent;
      return;
    }
    if (!BarWidgetRegistry.hasWidget(root.widgetId))
      return;

    if (_isPlugin) {
      var comp = BarWidgetRegistry.getWidget(root.widgetId);
      if (!comp)
        return;
      var pluginKey = root.widgetId.replace("plugin:", "");
      _pluginUrl = String(comp.url);
      if (!_pluginUrl) {
        loader.sourceComponent = null;
        PluginLoader.recordLoadFailure(pluginKey, "barWidget", comp, _pluginUrl);
        return;
      }
      _pluginInitial = PluginLoader.initialProperties("barWidget", _pluginUrl, _instanceApi(), _currentContext);
      loader.setSource(_pluginUrl, _pluginInitial);
    } else {
      loader.setSource(_barWidgetsDir + root.widgetId + ".qml", _contextProps());
    }
  }

  // Placeholder for an installed-but-unloadable plugin's widget
  Component {
    id: placeholderComponent
    PluginPlaceholder {
      size: Math.round(root.barHeight * 0.5)
    }
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: true
    active: (root.checkWidgetExists() || root._pluginUnavailable) && (root.reloadCounter >= 0)

    // All widgets use setSource() so that screen and widget properties
    // are set as initial properties, available during Component.onCompleted.
    Component.onCompleted: root._loadWidget()

    onActiveChanged: {
      if (active)
        root._loadWidget();
    }

    // Unregister when the loaded item is destroyed (Loader deactivated or sourceComponent changed)
    onItemChanged: {
      if (!item) {
        root._unregister();
      }
    }

    onStatusChanged: {
      if (status === Loader.Error && root._isPlugin)
        PluginLoader.recordLoadFailure(root.widgetId.replace("plugin:", ""), "barWidget", sourceComponent, root._pluginUrl);
    }

    onLoaded: {
      if (!item)
        return;

      Logger.d("BarWidgetLoader", "Loading widget", widgetId, "on screen:", widgetScreen.name);

      // Extend widget to fill full bar dimension for extended click areas
      // For horizontal bars: widget fills bar height (content width preserved)
      // For vertical bars: widget fills bar width (content height preserved)
      if (root.isVerticalBar) {
        item.width = Qt.binding(function () {
          return root.barHeight;
        });
      } else {
        item.height = Qt.binding(function () {
          return root.barHeight;
        });
      }

      if (root._isPlugin) {
        // Synchronize values that changed during asynchronous creation too.
        PluginLoader.applyLateContext(item, "barWidget", root._currentContext, root._pluginInitial);
      } else {
        // Apply remaining widget properties (screen is already set as initial prop)
        for (var prop in widgetProps) {
          if (item.hasOwnProperty(prop)) {
            item[prop] = widgetProps[prop];
          }
        }
      }

      // Unregister any previous registration before registering the new instance
      root._unregister();

      // Register and store the key for reliable unregistration
      BarService.registerWidget(widgetScreen.name, section, widgetId, sectionIndex, item);
      root._regScreen = widgetScreen.name;
      root._regSection = section;
      root._regWidgetId = widgetId;
      root._regIndex = sectionIndex;

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded();
      }
    }

    Component.onDestruction: {
      root._unregister();
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!BarWidgetRegistry.hasWidget(widgetId) && !root._pluginUnavailable) {
      Logger.w("BarWidgetLoader", "Widget not found in registry:", widgetId);
    }
  }
}
