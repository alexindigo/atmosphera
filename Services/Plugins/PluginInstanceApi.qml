import QtQuick
import qs.Commons
import qs.Services.Plugins

// The plugin api of one placed plugin piece (plugin-instances design, section 4).
// Every member of the plugin api is forwarded from `base`; the instance differs
// in its settings (plugin settings with this placement's instanceSettings on
// top) and in opening its panels with this api.
QtObject {
  id: root

  // Plugin api of the plugin this instance belongs to
  property var base: null
  // Where the instance is drawn; see PluginInstances.entryFor
  property var placement: null

  readonly property string pluginId: base ? base.pluginId : ""
  readonly property string pluginDir: base ? base.pluginDir : ""
  property var manifest: base ? base.manifest : ({})

  // Instance references (the plugin's own pieces, set by the shell)
  property var mainInstance: base ? base.mainInstance : null
  property var barWidget: base ? base.barWidget : null
  property var desktopWidget: base ? base.desktopWidget : null
  property var launcherProvider: base ? base.launcherProvider : null
  property var controlCenterWidget: base ? base.controlCenterWidget : null

  property var panelOpenScreen: base ? base.panelOpenScreen : null
  property var ipcHandlers: base ? base.ipcHandlers : ({})

  property var pluginTranslations: base ? base.pluginTranslations : ({})
  property var pluginFallbackTranslations: base ? base.pluginFallbackTranslations : ({})
  property string currentLanguage: base ? base.currentLanguage : ""
  property int translationVersion: base ? base.translationVersion : 0

  // Shared plugin state: the same object for every instance of the plugin
  property var state: base ? base.state : ({})
  property bool stateLoaded: base ? base.stateLoaded : false
  property var saveState: base ? base.saveState : null

  property var getConfig: base ? base.getConfig : null
  property var closePanel: base ? base.closePanel : null
  property var openLauncher: base ? base.openLauncher : null
  property var closeLauncher: base ? base.closeLauncher : null
  property var toggleLauncher: base ? base.toggleLauncher : null
  property var withCurrentScreen: base ? base.withCurrentScreen : null
  property var tr: base ? base.tr : null
  property var trp: base ? base.trp : null
  property var hasTranslation: base ? base.hasTranslation : null

  property var runtime: null
  property string _openError: ""
  property var _lifetime: ({alive: true})
  property var _cancelOpen: null
  property var _cancelPreviewOpen: null
  property var _inheritedPreview: null
  property var _previewGeneration: null
  property bool _constructed: false
  readonly property var _sharedPreviewBase: base && base.settingsPreviewOwner ? base.settingsPreviewOwner.baseScope : null
  readonly property bool settingsReady: runtime !== null && runtime.ready
  readonly property string settingsError: _openError || (runtime ? runtime.error : "")
  readonly property var pluginSettings: runtime ? runtime.values : null
  readonly property var settingsView: settingsPreviewOwner.values
  property PluginSettingsPreview settingsPreviewOwner: PluginSettingsPreview {
    draftFactory: function () { return root.createSettingsEditor(); }
    sourceValue: root._inheritedPreview && root._inheritedPreview.ready ? root._inheritedPreview.values : root.pluginSettings
    currentOwner: function () { return root.settingsReady ? root.runtime.placementToken : null; }
  }

  function createSettingsPreview(editor) { return settingsPreviewOwner.open(editor); }

  function _refreshPreviewView() {
    if (!_constructed) return;
    var token = {};
    var lifetime = _lifetime;
    _previewGeneration = token;
    if (_cancelPreviewOpen) { _cancelPreviewOpen(); _cancelPreviewOpen = null; }
    if (_inheritedPreview) { _inheritedPreview.detach(); _inheritedPreview = null; }
    if (!_sharedPreviewBase) return;
    _cancelPreviewOpen = PluginInstances.openPreviewView(base, placement, _sharedPreviewBase, function (result) {
      if (!lifetime.alive || root._previewGeneration !== token) { if (result.editor) result.editor.detach(); return; }
      if (result.status === "opened") root._inheritedPreview = result.editor;
    });
  }
  on_SharedPreviewBaseChanged: _refreshPreviewView()

  Component.onCompleted: {
    _constructed = true;
    var lifetime = _lifetime;
    _cancelOpen = PluginInstances.openRuntime(base, placement, function (result) {
      if (!lifetime.alive) { if (result.editor) result.editor.detach(); return; }
      if (result.status === "opened") root.runtime = result.editor;
      else root._openError = result.error?.code || "overlay-open";
    });
    _refreshPreviewView();
  }
  Component.onDestruction: {
    _lifetime.alive = false;
    if (_cancelOpen) _cancelOpen();
    if (_cancelPreviewOpen) _cancelPreviewOpen();
    if (_inheritedPreview) _inheritedPreview.detach();
    if (runtime) runtime.detach();
  }

  // Stores only the values that differ from the plugin settings, in this
  // placement's entry. The plugin settings file is never written.
  function saveSettings(callback) {
    if (!runtime || !runtime.ready) {
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback({status: "failed", error: {code: "plugin-owner"}});
      });
      return false;
    }
    return typeof callback === "function" ? runtime.save(callback) : runtime.save();
  }

  // Drops every instance override of this placement.
  function resetSettings(callback) {
    var editor = createSettingsEditor();
    if (!editor) {
      var lifetime = _lifetime;
      Qt.callLater(function () {
        if (lifetime.alive && typeof callback === "function") callback({status: "failed", refreshState: "not_refreshed", error: {code: "overlay-owner"}});
      });
      return false;
    }
    editor.whenReady(function (opened) {
      if (opened.status !== "opened") {
        if (typeof callback === "function") callback(opened);
        return;
      }
      editor.resetOverrides(function (result) {
        // Only current acknowledged success closes this one-shot editor.
        // Failed/stale work stays owned by the returned editor for retry.
        if (result.status !== "failed" && result.refreshState === "current") editor.discard();
        if (typeof callback === "function") callback(result);
      });
    });
    return editor;
  }

  function createSettingsEditor() {
    return PluginInstances.createSettingsEditor(pluginId, placement, base);
  }

  function openPanel(screen, buttonItem) {
    if (!screen) {
      Logger.w("PluginInstanceApi", "No screen available for opening panel");
      return false;
    }
    return Service.openPluginPanel(pluginId, screen, buttonItem, root);
  }

  function togglePanel(screen, buttonItem) {
    if (!screen) {
      Logger.w("PluginInstanceApi", "No screen available for toggling panel");
      return false;
    }
    return Service.togglePluginPanel(pluginId, screen, buttonItem, root);
  }
}
