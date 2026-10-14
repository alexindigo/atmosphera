import QtQuick
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

// One plugin piece drawn in place (shared-loader design, 3.3). The loader
// supplies the values; this view only places the piece and reports failures.
//
// Inputs: pluginKey, entryPoint, url (file url of the entry file), api (the
// plugin or instance api passed as pluginApi), context (object of values for
// the entry point's contract names), active.
// Outputs: item, failed, placeholder, signal loaded(loadedItem).
Item {
  id: root

  property string pluginKey: ""
  property string entryPoint: ""
  property string url: ""
  property var api: null
  property var context: ({})
  property bool active: true
  property bool asynchronous: true
  property real placeholderSize: Style.baseWidgetSize

  readonly property var item: loader.item
  readonly property bool failed: _failed
  readonly property Item placeholder: placeholderItem

  property bool _failed: false
  property bool _ready: false

  signal loaded(var loadedItem)

  implicitWidth: failed ? placeholderItem.implicitWidth : (loader.item ? loader.item.implicitWidth : 0)
  implicitHeight: failed ? placeholderItem.implicitHeight : (loader.item ? loader.item.implicitHeight : 0)

  // Each input change loads exactly once: a new setSource replaces the piece,
  // an empty source unloads it.
  property var _initial: null

  function _reload() {
    _failed = false;
    _initial = null;
    if (!active || url === "") {
      loader.sourceComponent = null;
      return;
    }
    var props = PluginLoader.initialProperties(entryPoint, url, api, context);
    _initial = props;
    loader.setSource(url, props);
  }

  function _fail(message) {
    if (_failed)
      return;
    _failed = true;
    Service.recordPluginError(pluginKey, entryPoint, message);
  }

  function _failureMessage() {
    return PluginLoader.failureMessage(loader.sourceComponent, url);
  }

  // Input handlers only act after creation; the first load is the one in
  // Component.onCompleted, so initial bindings never trigger extra loads.
  onUrlChanged: if (_ready) _reload()
  onApiChanged: if (_ready) _reload()
  onEntryPointChanged: if (_ready) _reload()
  onActiveChanged: if (_ready) _reload()

  // Context values change without reloading; only names the item has apply.
  onContextChanged: if (_ready) PluginLoader.applyLateContext(loader.item, entryPoint, context, {})

  Component.onCompleted: {
    _ready = true;
    _reload();
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: root.asynchronous

    onLoaded: {
      if (!item) {
        root._fail(root._failureMessage());
        return;
      }
      PluginLoader.applyLateContext(item, root.entryPoint, root.context, root._initial);
      root.loaded(item);
    }

    onStatusChanged: {
      if (status === Loader.Error)
        root._fail(root._failureMessage());
    }
  }

  PluginPlaceholder {
    id: placeholderItem
    anchors.centerIn: parent
    size: root.placeholderSize
    visible: root.failed
  }
}
