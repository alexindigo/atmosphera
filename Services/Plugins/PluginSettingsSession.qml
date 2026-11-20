import QtQuick
import "PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.Plugins

// Selected editor lifetime and receipt ownership, independent of popup chrome.
// The presentation supplies input-control callbacks and renders confirmation.
QtObject {
  id: root
  property var page: null
  property bool presentationOpen: false
  property bool inputDirty: false
  required property var commitInputs
  required property var captureInputs
  required property var acknowledgeInputs
  required property var resetInputs
  property var currentPlugin: null
  property var currentPluginApi: null
  property var currentInstanceApi: null
  readonly property bool isInstance: currentInstanceApi !== null
  property var editor: null
  property var pageApi: null
  property var fields: null
  property var _preview: null
  property var _initial: ({})
  property bool busy: false
  property bool failed: false
  readonly property bool dirty: failed || inputDirty || (editor && editor.dirty) || (fields && fields.error !== "") || (pageApi && pageApi.staged) || (page && (typeof page.settingsDirty !== "boolean" || page.settingsDirty))
  property string settingsUrl: ""
  property string settingsEntryPoint: "settings"
  property int _inputFence: 0
  property var _previewFence: null
  property var _cancelOpening: null
  property var _lifetime: ({
                             alive: true
                           })
  property Component _pageApiFactory: Component {
    PluginSettingsPageApi {}
  }
  property Component _fieldsFactory: Component {
    PluginSettingsFields {}
  }
  signal presentRequested
  signal reloadRequested
  signal closeAccepted
  signal discardRequired
  signal openingFailed
  signal presentationInvalidated
  signal settingsCompleted(var result)
  signal saved

  function openPluginSettings(manifest, entryPoint) {
    return _open(manifest, entryPoint, null);
  }
  function openInstanceSettings(manifest, instanceApi, entryPoint, capturedEditor) {
    if (!instanceApi) {
      openingFailed();
      return false;
    }
    return _open(manifest, entryPoint, instanceApi, capturedEditor);
  }
  function _open(manifest, entryPoint, instanceApi, capturedEditor) {
    if (presentationOpen || busy || editor !== null)
      return false;
    currentPlugin = manifest;
    var key = manifest.compositeKey || manifest.id;
    currentInstanceApi = instanceApi || null;
    currentPluginApi = instanceApi || Service.getPluginAPI(key);
    if (!currentPluginApi) {
      openingFailed();
      return false;
    }
    editor = capturedEditor || currentPluginApi.createSettingsEditor(true);
    if (!editor)
      return false;
    failed = false;
    resetInputs();
    settingsEntryPoint = entryPoint || "settings";
    var entry = manifest.entryPoints[settingsEntryPoint];
    settingsUrl = "file://" + Registry.getPluginDir(key) + "/" + entry + (entry.indexOf("?") === -1 ? "?" : "&") + "v=" + (Registry.pluginLoadVersions[key] || 0);
    var selected = editor;
    var lifetime = _lifetime;
    _cancelOpening = selected.whenReady(function (result) {
      if (!lifetime.alive || root.editor !== selected)
        return;
      root._cancelOpening = null;
      if (result.status === "opened") {
        var base = root.isInstance ? root.currentInstanceApi.base : root.currentPluginApi;
        var capture = selected.fieldCapture;
        var metadata = base.settingsOwner.store.settingsEditorMetadata;
        if (!capture || !capture.current() || !metadata || metadata.ready !== true) {
          root._openingRefused(selected, {
                                 status: "failed",
                                 refreshState: "not_refreshed",
                                 error: {
                                   code: "settings-field-contract"
                                 }
                               });
          return;
        }
        var placement = root.isInstance ? Read.freeze(root.currentInstanceApi.placement) : null;
        root.fields = root._fieldsFactory.createObject(root, {
                                                         editor: selected,
                                                         scopeKind: root.isInstance ? "instance" : "plugin",
                                                         metadata: metadata,
                                                         capture: capture,
                                                         recapture: function () {
                                                           return placement ? PluginInstances.captureSettingsFields(base, placement) : Service.captureSharedSettingsFields(base);
                                                         }
                                                       });
        root._initial = Read.freeze(selected.initialValue);
        root.pageApi = root._pageApiFactory.createObject(root, {
                                                           capability: root._capability(root.currentPluginApi, selected, root.fields)
                                                         });
        root.presentRequested();
        return;
      }
      root._openingRefused(selected, result);
    });
    return true;
  }
  function _openingRefused(selected, result) {
    root.failed = true;
    root.settingsCompleted(result);
    root.openingFailed();
    selected.discard();
    root.editor = null;
    root.currentPlugin = null;
    root.currentPluginApi = null;
    root.currentInstanceApi = null;
    root.failed = false;
    root.presentationInvalidated();
  }
  function _capability(base, selected, selectedFields) {
    var result = Object.create(null);
    for (var name of ["pluginId", "pluginDir", "manifest", "mainInstance", "barWidget", "desktopWidget", "launcherProvider", "controlCenterWidget", "panelOpenScreen", "ipcHandlers", "pluginTranslations", "pluginFallbackTranslations", "currentLanguage", "translationVersion", "state", "stateLoaded", "saveState", "getConfig", "openPanel", "closePanel", "togglePanel",
                      "openLauncher", "closeLauncher", "toggleLauncher", "withCurrentScreen", "tr", "trp", "hasTranslation"])
      _forward(result, base, name);
    Object.assign(result, {
                    scopeKind: selectedFields.scopeKind,
                    runtimeContext: base.settingsContext,
                    readSettings: function () {
                      return selectedFields.readSettings();
                    },
                    initialSettings: function () {
                      return root._initial;
                    },
                    field: function (key) {
                      return selectedFields.field(key);
                    },
                    contentField: function (key) {
                      return selectedFields.contentField(key);
                    },
                    resetFields: function (keys) {
                      return selectedFields.resetFields(keys);
                    },
                    copyValue: function (value) {
                      return selected.copyValue(value);
                    },
                    previewDirty: function () {
                      return root._preview ? root._preview.pending() : false;
                    },
                    previewSettings: function (patch) {
                      if (!patch || typeof patch !== "object" || Array.isArray(patch))
                        return false;
                      var keys = Object.keys(patch);
                      if (!keys.every(function (key) {
                        return selectedFields.configurationKeys.indexOf(key) !== -1;
                      }))
                        return false;
                      for (var key of keys)
                        if (!selectedFields.field(key).set(patch[key]))
                          return false;
                      if (!root._preview)
                        root._preview = base.createSettingsPreview(selected);
                      return !!root._preview && root._preview.update(patch);
                    }
                  });
    return Object.freeze(result);
  }
  function _forward(target, source, name) {
    Object.defineProperty(target, name, {
                            get: function () {
                              return source[name];
                            },
                            enumerable: true
                          });
  }
  function resetInstanceSettings() {
    if (!currentInstanceApi || !editor || !fields || !fields.ready || !pageApi || !page || busy)
      return false;
    _submit(true);
    return true;
  }
  function applySettings() {
    if (!editor || editor.writable === false || !page || busy)
      return false;
    commitInputs();
    busy = true;
    try {
      if (typeof page.saveSettings === "function")
        page.saveSettings();
      if (fields.error)
        throw new Error("settings-field-input");
      _submit(false);
    } catch (error) {
      _finish({
                status: "failed",
                refreshState: "not_refreshed",
                error: {
                  code: "editor-input"
                }
              }, false);
    }
    return true;
  }
  function _submit(reset) {
    _inputFence = captureInputs();
    _previewFence = _preview ? _preview.capture() : null;
    busy = true;
    pageApi.busy = true;
    failed = false;
    var lifetime = _lifetime;
    var selected = editor;
    try {
      var completed = function (result) {
        if (lifetime.alive && selected && root.editor === selected)
          root._finish(result, reset);
      };
      if (reset) {
        if (!fields.resetConfiguration(completed))
          _finish({
                    status: "failed",
                    refreshState: "not_refreshed",
                    error: {
                      code: "settings-field-reset"
                    }
                  }, true);
      } else
        editor.apply(editor.values, completed);
    } catch (error) {
      _finish({
                status: "failed",
                refreshState: "not_refreshed",
                error: {
                  code: "editor-input"
                }
              }, reset);
    }
  }
  function _finish(result, reset) {
    var accepted = result && (result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current";
    failed = !accepted;
    if (accepted && !fields.acknowledge(result)) {
      result = {
        status: "failed",
        refreshState: "not_refreshed",
        error: {
          code: "settings-field-capture"
        }
      };
      accepted = false;
      failed = true;
    }
    if (accepted) {
      _initial = Read.freeze(editor.initialValue);
      if (_preview)
        _preview.acknowledge(_previewFence);
    }
    if (accepted && !reset)
      acknowledgeInputs(_inputFence);
    // Preserve signal-before-callback and action exclusion through delivery.
    settingsCompleted(result);
    pageApi.complete(result);
    pageApi.busy = false;
    busy = false;
    if (!accepted)
      return;
    if (reset)
      reloadRequested();
    saved();
  }
  function requestClose() {
    if (busy)
      return false;
    commitInputs();
    if (dirty) {
      discardRequired();
      return false;
    }
    return confirmDiscard();
  }
  function confirmDiscard() {
    if (busy)
      return false;
    if (_cancelOpening) {
      _cancelOpening();
      _cancelOpening = null;
    }
    if (editor && editor.discard() === false)
      return false;
    editor = null;
    closeAccepted();
    return true;
  }
  // Called after an admitted close has torn down the page. Real presentation
  // loss uses the editor's existing deferred release, not forced busy discard.
  function _releaseSelection() {
    if (_cancelOpening) {
      _cancelOpening();
      _cancelOpening = null;
    }
    if (editor)
      editor.release();
    editor = null;
    if (_preview)
      _preview.close();
    _preview = null;
  }
  function presentationClosed() {
    _releaseSelection();
    if (pageApi)
      pageApi.destroy();
    pageApi = null;
    if (fields)
      fields.destroy();
    fields = null;
    busy = false;
    failed = false;
    currentPlugin = null;
    resetInputs();
    currentPluginApi = null;
    currentInstanceApi = null;
  }
  Component.onDestruction: {
    _lifetime.alive = false;
    _releaseSelection();
  }
}
