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

  // Plugin settings with this placement's instanceSettings on top. Reactive to
  // plugin-level saves (base) and to instance saves (PluginInstances.revision).
  property var pluginSettings: PluginInstances.effectiveSettings(base ? base.pluginSettings : null, placement, PluginInstances.revision)

  // Stores only the values that differ from the plugin settings, in this
  // placement's entry. The plugin settings file is never written.
  function saveSettings() {
    if (!base)
      return;
    var changed = {};
    var local = root.pluginSettings || {};
    var shared = base.pluginSettings || {};
    for (var key in local) {
      if (JSON.stringify(local[key]) !== JSON.stringify(shared[key]))
        changed[key] = JSON.parse(JSON.stringify(local[key]));
    }
    PluginInstances.writeSettings(pluginId, placement, Object.keys(changed).length > 0 ? changed : null);
  }

  // Drops every instance override of this placement.
  function resetSettings() {
    PluginInstances.writeSettings(pluginId, placement, null);
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
