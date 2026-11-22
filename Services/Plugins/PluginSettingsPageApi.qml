import QtQuick

// Only closure-bound field capabilities cross into a generic page. Neither the
// live base API nor the native editor/namespace is an input to this component.
QtObject {
  id: root
  required property var capability
  readonly property string apiRole: "settings-editor"
  readonly property string scopeKind: capability.scopeKind
  readonly property var runtimeContext: capability.runtimeContext
  readonly property var pluginSettings: capability.readSettings()
  readonly property var initialSettings: capability.initialSettings()
  readonly property bool previewDirty: capability.previewDirty()
  property bool staged: false
  property bool busy: false
  property var _callbacks: []
  property var _observationCallbacks: []
  signal settingsCompleted(var result)

  readonly property string pluginId: capability.pluginId
  readonly property string pluginDir: capability.pluginDir
  readonly property var manifest: capability.manifest
  readonly property var mainInstance: capability.mainInstance
  readonly property var barWidget: capability.barWidget
  readonly property var desktopWidget: capability.desktopWidget
  readonly property var launcherProvider: capability.launcherProvider
  readonly property var controlCenterWidget: capability.controlCenterWidget
  readonly property var panelOpenScreen: capability.panelOpenScreen
  readonly property var ipcHandlers: capability.ipcHandlers
  readonly property var pluginTranslations: capability.pluginTranslations
  readonly property var pluginFallbackTranslations: capability.pluginFallbackTranslations
  readonly property string currentLanguage: capability.currentLanguage
  readonly property int translationVersion: capability.translationVersion
  // Explicit state/config/application operations retain their existing owners.
  readonly property var state: capability.state
  readonly property bool stateLoaded: capability.stateLoaded
  readonly property var saveState: capability.saveState
  readonly property var getConfig: capability.getConfig
  readonly property var openPanel: capability.openPanel
  readonly property var closePanel: capability.closePanel
  readonly property var togglePanel: capability.togglePanel
  readonly property var openLauncher: capability.openLauncher
  readonly property var closeLauncher: capability.closeLauncher
  readonly property var toggleLauncher: capability.toggleLauncher
  readonly property var withCurrentScreen: capability.withCurrentScreen
  readonly property var tr: capability.tr
  readonly property var trp: capability.trp
  readonly property var hasTranslation: capability.hasTranslation

  function field(key) {
    return capability.field(key);
  }
  // Reset for one multi-field control: the listed configuration leaves only.
  function resetFields(keys) {
    return capability.resetFields(keys);
  }
  function contentField(key) {
    return capability.contentField(key);
  }
  function copyValue(value) {
    return capability.copyValue(value);
  }
  function previewSettings(patch) {
    if (busy || !capability.previewSettings(patch))
      return false;
    staged = true;
    return true;
  }
  // Compatibility means staging and observing completion, never ingesting a
  // reconstructed effective snapshot or invoking native publication.
  function saveSettings(callback) {
    if (busy)
      return false;
    if (typeof callback === "function")
      _callbacks.push(callback);
    return true;
  }
  function beginSubmission() {
    _observationCallbacks = [];
  }
  function retryObservation() {
    _callbacks = _observationCallbacks.concat(_callbacks);
    _observationCallbacks = [];
  }
  function complete(result) {
    var callbacks = _callbacks;
    _callbacks = [];
    // Observation-only Retry does not rerun the page's staging function. Its
    // original observers must still see the retried terminal result.
    if (result?.error?.phase === "observation")
      _observationCallbacks = callbacks;
    if (result && (result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current")
      staged = previewDirty;
    settingsCompleted(result);
    for (var callback of callbacks) {
      try {
        callback(result);
      } catch (error) {
        console.warn("Plugin settings page completion observer failed");
      }
    }
  }
}
