pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/QmlRootDeclarations.js" as RootDeclarations
import "PluginContract.js" as PluginContract
import qs.Services.Plugins

// The one place that hands values to plugin QML (shared-loader design, 3.2-3.3).
// Values are passed as initial properties only when the entry file declares
// them on its root object; everything else inherited is assigned after
// creation; the rest is skipped silently. No `Cannot assign` warnings and no
// late nulls.
Singleton {
  id: root

  // Synchronous reader for entry-file text; the path is set per call.
  FileView {
    id: reader
    blockLoading: true
    printErrors: false
    watchChanges: false
  }

  property var _declaredCache: ({})

  function _hasOwn(obj, name) {
    return obj !== null && obj !== undefined && Object.prototype.hasOwnProperty.call(obj, name);
  }

  // file:///x/Main.qml?v=3 -> /x/Main.qml
  function _pathOf(url) {
    var s = String(url);
    var q = s.indexOf("?");
    if (q >= 0)
      s = s.substring(0, q);
    if (s.indexOf("file://") === 0)
      s = s.substring("file://".length);
    try {
      return decodeURIComponent(s);
    } catch (e) {
      return s;
    }
  }

  // Names declared on the root object of the entry file at `url`. Cached per
  // full url (including the ?v= cache-bust), so a reload re-reads the file.
  function declaredNames(url) {
    var key = String(url);
    if (_hasOwn(_declaredCache, key))
      return _declaredCache[key];
    // Changing path keeps the previous text until the load completes
    // (FileView.blockLoading), so unload first and wait for the new file.
    reader.path = "";
    reader.path = _pathOf(url);
    reader.waitForJob();
    var names = RootDeclarations.rootPropertyNames(reader.text());
    _declaredCache[key] = names;
    return names;
  }

  // Initial properties for setSource/createObject: pluginApi, plus every
  // context name of this entry point that the entry file declares on its root.
  function initialProperties(entryPoint, url, api, context) {
    var props = {
      "pluginApi": api
    };
    var declared = declaredNames(url);
    var names = PluginContract.contextNames(entryPoint);
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      if (declared.indexOf(name) >= 0 && _hasOwn(context, name))
        props[name] = context[name];
    }
    return props;
  }

  // Synchronizes every supported context name with the site's current value,
  // including names supplied at creation. Equal values need no reassignment;
  // names the item does not have are skipped silently.
  function applyLateContext(item, entryPoint, context, initial) {
    if (!item || !context)
      return;
    var names = PluginContract.contextNames(entryPoint);
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      if (!_hasOwn(context, name))
        continue;
      if (name in item && item[name] !== context[name])
        item[name] = context[name];
    }
  }

  // Report from the component used for this attempt, never a second compile.
  // Loader clears source on incubation failure but retains sourceComponent.
  // Incubator errors are printed by Qt, not exposed through errorString(); in
  // that case keep the original URL and distinguish creation from compilation.
  function failureMessage(component, url) {
    var source = url ? String(url) : "";
    if (component) {
      var message = component.errorString();
      if (message)
        return message;
      if (!source)
        source = String(component.url);
      if (component.status === Component.Ready)
        return "Failed to instantiate " + (source || "plugin component") + "; Qt reported an item creation error";
    }
    return source ? "Failed to load " + source : "Plugin entry has no source component or URL";
  }

  // Records a failed load for sites that own their Loader (bar, control
  // center, desktop). PluginView records its own failures.
  function recordLoadFailure(pluginKey, entryPoint, component, url) {
    Service.recordPluginError(pluginKey, entryPoint, failureMessage(component, url));
  }

  // Creates a plugin piece directly (Main, launcher providers). Returns the
  // instance, or null after recording the error for the plugin.
  function createObject(pluginKey, entryPoint, component, parent, api, context) {
    if (!component) {
      recordLoadFailure(pluginKey, entryPoint, component, "");
      return null;
    }
    if (component.status === Component.Error) {
      recordLoadFailure(pluginKey, entryPoint, component, component.url);
      return null;
    }
    if (component.status !== Component.Ready) {
      Service.recordPluginError(pluginKey, entryPoint, "Component is not ready");
      return null;
    }
    var initial = initialProperties(entryPoint, component.url, api, context);
    var instance;
    try {
      instance = component.createObject(parent, initial);
    } catch (e) {
      Service.recordPluginError(pluginKey, entryPoint, "Failed to instantiate " + String(component.url) + ": " + String(e));
      return null;
    }
    if (!instance) {
      recordLoadFailure(pluginKey, entryPoint, component, component.url);
      return null;
    }
    applyLateContext(instance, entryPoint, context, initial);
    return instance;
  }
}
