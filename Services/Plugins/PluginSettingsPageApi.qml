import QtQuick

// Editor-only API: preferences are local; saveSettings stages page input.
// The popup alone invokes the selected editor's Apply and completes callbacks.
QtObject {
  id: root
  required property var base
  property var pluginSettings: ({})
  property var initialSettings: ({})
  property var _preview: null
  readonly property bool previewDirty: _preview ? _preview.pending() : false
  property bool staged: false
  property bool busy: false
  property var _callbacks: []
  signal settingsCompleted(var result)

  readonly property string pluginId: base ? base.pluginId : ""
  readonly property string pluginDir: base ? base.pluginDir : ""
  readonly property var manifest: base ? base.manifest : ({})
  readonly property var mainInstance: base ? base.mainInstance : null
  readonly property var barWidget: base ? base.barWidget : null
  readonly property var desktopWidget: base ? base.desktopWidget : null
  readonly property var launcherProvider: base ? base.launcherProvider : null
  readonly property var controlCenterWidget: base ? base.controlCenterWidget : null
  readonly property var panelOpenScreen: base ? base.panelOpenScreen : null
  readonly property var ipcHandlers: base ? base.ipcHandlers : ({})
  readonly property var pluginTranslations: base ? base.pluginTranslations : ({})
  readonly property var pluginFallbackTranslations: base ? base.pluginFallbackTranslations : ({})
  readonly property string currentLanguage: base ? base.currentLanguage : ""
  readonly property int translationVersion: base ? base.translationVersion : 0
  // State, config and explicit application actions retain their existing owners.
  readonly property var state: base ? base.state : ({})
  readonly property bool stateLoaded: base ? base.stateLoaded : false
  readonly property var saveState: base ? base.saveState : null
  readonly property var getConfig: base ? base.getConfig : null
  readonly property var openPanel: base ? base.openPanel : null
  readonly property var closePanel: base ? base.closePanel : null
  readonly property var togglePanel: base ? base.togglePanel : null
  readonly property var openLauncher: base ? base.openLauncher : null
  readonly property var closeLauncher: base ? base.closeLauncher : null
  readonly property var toggleLauncher: base ? base.toggleLauncher : null
  readonly property var withCurrentScreen: base ? base.withCurrentScreen : null
  readonly property var tr: base ? base.tr : null
  readonly property var trp: base ? base.trp : null
  readonly property var hasTranslation: base ? base.hasTranslation : null

  function previewSettings(patch) {
    if (!_preview && base && typeof base.createSettingsPreview === "function")
      _preview = base.createSettingsPreview();
    if (!_preview || !_preview.update(patch)) return false;
    pluginSettings = Object.assign(Object.create(null), pluginSettings, JSON.parse(JSON.stringify(patch)));
    staged = true;
    return true;
  }

  function capturePreview() { return _preview ? _preview.capture() : null; }

  function refresh(value, captured) {
    initialSettings = JSON.parse(JSON.stringify(value));
    if (_preview) _preview.acknowledge(captured);
    pluginSettings = JSON.parse(JSON.stringify(_preview && _preview.pending() ? _preview.values() : value));
  }

  function releasePreview() {
    if (_preview) _preview.close();
    _preview = null;
  }

  Component.onDestruction: releasePreview()

  function saveSettings(callback) {
    if (busy)
      return false;
    staged = true;
    if (typeof callback === "function")
      _callbacks.push(callback);
    return true;
  }

  function complete(result) {
    var callbacks = _callbacks;
    _callbacks = [];
    if (result && (result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current")
      staged = previewDirty;
    settingsCompleted(result);
    for (var i = 0; i < callbacks.length; i++) {
      try {
        callbacks[i](result);
      } catch (error) {
        // One page observer must not strand the remaining detached callbacks.
        console.warn("Plugin settings page completion observer failed");
      }
    }
  }
}
