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
  property var _observation: null
  property var _observationRetry: null
  property string observationError: ""
  property int _draftEditGeneration: 0
  readonly property bool _draftDirty: editor?.dirty === true
  on_DraftDirtyChanged: {
    if (_draftDirty)
      _draftEditGeneration++;
  }
  readonly property var _runtimeReadOwner: currentPluginApi ? currentPluginApi.settingsReadOwner : null
  on_RuntimeReadOwnerChanged: {
    if (_observation && _runtimeReadOwner !== _observation.reader)
      _observationFailed(_observation, "settings-runtime-owner");
  }
  readonly property bool _runtimeCurrent: _hasCurrentRuntime()
  on_RuntimeCurrentChanged: {
    if (_observation && !_runtimeCurrent)
      _observationFailed(_observation, "settings-runtime-owner");
  }
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
  signal settingsCompleted(var result)
  signal saved

  function _hasCurrentRuntime() {
    return !!currentPluginApi && currentPluginApi.settingsContext.current();
  }

  function openPluginSettings(manifest, entryPoint) {
    return _open(manifest, entryPoint, null);
  }
  function openInstanceSettings(manifest, instanceApi, entryPoint, capturedEditor) {
    if (!instanceApi) {
      if (presentationOpen || busy || editor !== null)
        return false;
      if (capturedEditor)
        capturedEditor.release();
      _openingRefused("settings-runtime-owner");
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
      if (capturedEditor)
        capturedEditor.release();
      _openingRefused("settings-runtime-owner");
      return false;
    }
    editor = capturedEditor || currentPluginApi.createSettingsEditor(true);
    if (!editor) {
      _openingRefused("settings-editor-unavailable");
      return false;
    }
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
        if (!root._hasCurrentRuntime() || !root._runtimeReadOwner) {
          root._openingRefused("settings-runtime-owner");
          return;
        }
        var base = root.isInstance ? root.currentInstanceApi.base : root.currentPluginApi;
        var capture = selected.fieldCapture;
        var metadata = base.settingsOwner.store.settingsEditorMetadata;
        if (!capture || !capture.current() || !metadata || metadata.ready !== true) {
          root._openingRefused("settings-field-contract");
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
        if (!root.fields) {
          root._openingRefused("settings-field-capability");
          return;
        }
        root._initial = Read.freeze(selected.initialValue);
        root.pageApi = root._pageApiFactory.createObject(root, {
                                                           capability: root._capability(root.currentPluginApi, selected, root.fields)
                                                         });
        if (!root.pageApi) {
          root._openingRefused("settings-page-capability");
          return;
        }
        root.presentRequested();
        return;
      }
      root._openingRefused(result.error.code, result);
    });
    return true;
  }
  function _openingRefused(code, receipt) {
    presentationClosed();
    settingsCompleted(receipt || {
                        status: "failed",
                        refreshState: "not_refreshed",
                        error: {
                          code: code
                        }
                      });
    openingFailed();
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
                      if (!root._preview)
                        root._preview = base.createSettingsPreview(selected);
                      return !!root._preview && root._preview.update(patch, function (edits) {
                        for (var key of Object.keys(edits))
                          if (!selectedFields.field(key).set(edits[key]))
                            return false;
                        return true;
                      });
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
    _beginSubmission();
    _submit(true);
    return true;
  }
  function applySettings() {
    if (!editor || editor.writable === false || !page || busy)
      return false;
    _beginSubmission();
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
  function _beginSubmission() {
    _observationRetry = null;
    observationError = "";
    pageApi.beginSubmission();
  }
  function retryObservation() {
    var retained = _observationRetry;
    if (!retained || !editor || !page || busy)
      return false;
    pageApi.busy = true;
    busy = true;
    pageApi.retryObservation();
    _synchronizeObservation(retained, true);
    return true;
  }
  function _sameDraft(receipt) {
    return editor === receipt.editor && editor.ready && !editor.dirty && !editor.busy && !editor.handle.conflicted && _draftEditGeneration === receipt.draftGeneration;
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
          root._observe(result, reset);
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
  function _observe(write, reset) {
    if (!write || ["saved", "nothing_to_save"].indexOf(write.status) === -1 || write.refreshState !== "current") {
      _finish(write, reset);
      return;
    }
    // Applied preview revisions are no longer temporary input. Leave only this
    // fully acknowledged preview; the editor/page and newer input stay owned.
    // Failed/stale writers return above without changing their preview.
    if (_preview) {
      _preview.acknowledge(_previewFence);
      if (!_preview.pending() && _preview.close())
        _preview = null;
    }
    _synchronizeObservation({
                              write: write,
                              reset: reset,
                              editor: editor,
                              draftGeneration: _draftEditGeneration
                            }, false);
  }
  function _synchronizeObservation(receipt, checking) {
    // A check uses exactly this retained write. It does not stage, persist or
    // acknowledge preview revisions. The same session can acquire the native
    // reader again (e.g. once an unrelated preview has closed).
    var pending = {
      receipt: receipt,
      checking: checking,
      reader: _runtimeReadOwner
    };
    _observation = pending;
    if (checking && !_sameDraft(receipt)) {
      _observationFailed(pending, "settings-observation-draft-changed");
      return;
    }
    if (_preview && _preview.pending()) {
      _observationFailed(pending, "settings-preview-pending");
      return;
    }
    if (!_hasCurrentRuntime() || !pending.reader) {
      _observationFailed(pending, "settings-runtime-owner");
      return;
    }
    var lifetime = _lifetime;
    try {
      pending.reader.readProjection.synchronize(receipt.write.observation, function (read) {
        if (!lifetime.alive || root._observation !== pending)
          return;
        // Registration is mutable in place. A cached QML binding does not
        // fence a native receipt that arrives after unregistration.
        if (!root._hasCurrentRuntime() || root._runtimeReadOwner !== pending.reader) {
          root._observationFailed(pending, "settings-runtime-owner");
          return;
        }
        if (read.status !== "observed") {
          root._observationFailed(pending, read.error?.code || "settings-runtime-observation");
          return;
        }
        if (checking && !root._sameDraft(receipt)) {
          root._observationFailed(pending, "settings-observation-draft-changed");
          return;
        }
        root._observation = null;
        root._observationRetry = null;
        root.observationError = "";
        // The native capture has installed on this exact reader, including
        // bindings, before this callback. Never infer that from writer signals.
        root._finish(receipt.write, receipt.reset, read, checking);
      });
    } catch (error) {
      _observationFailed(pending, "settings-runtime-observation");
    }
  }
  function _observationFailed(pending, code) {
    if (_observation !== pending)
      return;
    _observation = null;
    _observationRetry = pending.receipt;
    observationError = code;
    _finish({
              status: "failed",
              refreshState: "not_refreshed",
              error: {
                code: code,
                phase: "observation"
              },
              write: pending.receipt.write
            }, pending.receipt.reset, null, pending.checking);
  }
  function _finish(result, reset, read, checking) {
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
    }
    if (accepted && !reset && !checking)
      acknowledgeInputs(_inputFence);
    // Read snapshots are native immutable facts, not field metadata or a new
    // preference store. Keep them out of copyValue/field receipt serialization.
    if (accepted) {
      // The generic dirty flag cannot identify generations of buffered page
      // input. Do not tell a potentially dirty page that its input was saved.
      result = checking && (inputDirty || page?.settingsDirty !== false) ? {
                                                                             status: "observed",
                                                                             refreshState: "current",
                                                                             write: result,
                                                                             runtimeRead: read
                                                                           } : Object.assign({}, result, {
                                                                                               runtimeRead: read
                                                                                             });
    }
    // Preserve signal-before-callback and action exclusion through delivery.
    settingsCompleted(result);
    pageApi.complete(result);
    pageApi.busy = false;
    busy = false;
    if (!accepted || checking)
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
    _observation = null;
    _observationRetry = null;
    observationError = "";
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
