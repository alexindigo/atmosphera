import QtQuick
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
  property bool busy: false
  property bool failed: false
  readonly property bool dirty: failed || inputDirty || (editor && editor.dirty) || (pageApi && pageApi.staged) ||
      (page && (typeof page.settingsDirty !== "boolean" || page.settingsDirty))
  property string settingsUrl: ""
  property string settingsEntryPoint: "settings"
  property int _inputFence: 0
  property var _previewFence: null
  property var _cancelOpening: null
  property var _lifetime: ({alive: true})
  property Component _pageApiFactory: Component { PluginSettingsPageApi {} }
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
    if (!instanceApi) { openingFailed(); return false; }
    return _open(manifest, entryPoint, instanceApi, capturedEditor);
  }
  function _open(manifest, entryPoint, instanceApi, capturedEditor) {
    if (presentationOpen || busy || editor !== null) return false;
    currentPlugin = manifest;
    var key = manifest.compositeKey || manifest.id;
    currentInstanceApi = instanceApi || null;
    currentPluginApi = instanceApi || Service.getPluginAPI(key);
    if (!currentPluginApi) { openingFailed(); return false; }
    editor = capturedEditor || currentPluginApi.createSettingsEditor();
    if (!editor) return false;
    failed = false;
    resetInputs();
    settingsEntryPoint = entryPoint || "settings";
    var entry = manifest.entryPoints[settingsEntryPoint];
    settingsUrl = "file://" + Registry.getPluginDir(key) + "/" + entry + (entry.indexOf("?") === -1 ? "?" : "&") + "v=" + (Registry.pluginLoadVersions[key] || 0);
    var selected = editor;
    var lifetime = _lifetime;
    _cancelOpening = selected.whenReady(function (result) {
      if (!lifetime.alive || root.editor !== selected) return;
      root._cancelOpening = null;
      if (result.status === "opened") {
        root.pageApi = root._pageApiFactory.createObject(root, {
          base: root.currentPluginApi, editor: selected,
          initialSettings: Settings.store.copyValue(selected.initialValue), pluginSettings: selected.values
        });
        root.presentRequested();
        return;
      }
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
    });
    return true;
  }
  function resetInstanceSettings() {
    if (!currentInstanceApi || !editor || busy) return false;
    _submit(true);
    return true;
  }
  function applySettings() {
    if (!editor || editor.writable === false || !page || busy) return false;
    commitInputs();
    busy = true;
    try {
      if (typeof page.saveSettings === "function") page.saveSettings();
      _submit(false);
    } catch (error) {
      _finish({status: "failed", refreshState: "not_refreshed", error: {code: "editor-input"}}, false);
    }
    return true;
  }
  function _submit(reset) {
    _inputFence = captureInputs();
    _previewFence = pageApi.capturePreview();
    busy = true;
    pageApi.busy = true;
    failed = false;
    var lifetime = _lifetime;
    try {
      var completed = function (result) { if (lifetime.alive) root._finish(result, reset); };
      if (reset) _resetReviewedConfiguration(completed);
      else editor.apply(pageApi.pluginSettings, completed);
    } catch (error) {
      _finish({status: "failed", refreshState: "not_refreshed", error: {code: "editor-input"}}, reset);
    }
  }
  // P001 safety on the existing page API. The field-only catalog integration
  // replaces this session-level dispatch with its field capability Reset.
  function _resetReviewedConfiguration(callback) {
    var base = currentInstanceApi.base;
    var metadata = base.settingsOwner.store.settingsEditorMetadata;
    if (!metadata || metadata.ready !== true) {
      // Unported pages retain their existing native Reset contract. Never
      // guess usage for an unreviewed schema during this independent unit.
      editor.resetOverrides(callback);
      return;
    }
    for (var key of Object.keys(metadata.fields)) {
      if (metadata.fields[key].usage === "configuration" && !editor.handle.unset([key]))
        throw new Error("settings-configuration-reset");
    }
    editor.apply(editor.values, callback);
  }
  function _finish(result, reset) {
    var accepted = result && (result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current";
    failed = !accepted;
    if (accepted) pageApi.refresh(editor.initialValue, _previewFence);
    if (accepted && !reset) acknowledgeInputs(_inputFence);
    // Preserve signal-before-callback and action exclusion through delivery.
    settingsCompleted(result);
    pageApi.complete(result);
    pageApi.busy = false;
    busy = false;
    if (!accepted) return;
    if (reset) reloadRequested();
    saved();
  }
  function requestClose() {
    if (busy) return false;
    commitInputs();
    if (dirty) { discardRequired(); return false; }
    return confirmDiscard();
  }
  function confirmDiscard() {
    if (busy) return false;
    if (_cancelOpening) { _cancelOpening(); _cancelOpening = null; }
    if (editor && editor.discard() === false) return false;
    editor = null;
    closeAccepted();
    return true;
  }
  // Called after an admitted close has torn down the page. Real presentation
  // loss uses the editor's existing deferred release, not forced busy discard.
  function presentationClosed() {
    if (_cancelOpening) { _cancelOpening(); _cancelOpening = null; }
    if (editor) editor.release();
    editor = null;
    if (pageApi) pageApi.destroy();
    pageApi = null;
    busy = false;
    failed = false;
    currentPlugin = null;
    resetInputs();
    currentPluginApi = null;
    currentInstanceApi = null;
  }
  Component.onDestruction: {
    _lifetime.alive = false;
    if (_cancelOpening) _cancelOpening();
    if (editor) editor.release();
  }
}
