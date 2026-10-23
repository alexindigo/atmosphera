import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Theming
import qs.Modules.Panels.Settings.Tabs.ColorScheme

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property var normalized: null
  property var cases: []
  property var saveCompletions: []
  function check(name, condition, actual) {
    const row = {name: name, pass: !!condition, actual: actual};
    cases.push(row);
    Logger.i("StandoutTest", "STANDOUT_UNIT|" + JSON.stringify(row));
  }
  FileView { id: source; path: Quickshell.shellDir + "/Assets/ColorScheme/MacOS/MacOS.json" }
  FileView { id: saved; path: Settings.configDir + "colorschemes/Custom/Custom.json"; printErrors: false }
  FileView { id: initial; path: Settings.configDir + "colors.json"; printErrors: false }
  PanelWindow {
    implicitWidth: 900
    implicitHeight: 850
    ColorCustomizer { id: editor }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 200) {
        root.check("watchdog", false, root.phase);
        Qt.exit(2);
      }
      if (!Settings.isLoaded)
        return;
      if (root.phase === 0) {
        initial.reload();
        var initialColors;
        try { initialColors = JSON.parse(initial.text()); } catch (error) { return; }
        root.check("bootstrap.only-role-keys", Object.keys(initialColors).length === AtmoColor.roleKeys.length && Object.keys(initialColors).every(key => AtmoColor.roleKeys.includes(key)), initialColors);
        Settings.data.general.animationDisabled = true;
        Settings.data.colorSchemes.useWallpaperColors = false;
        Settings.data.colorSchemes.darkMode = true;
        var legacy = JSON.parse(source.text());
        for (const mode of ["dark", "light"]) {
          delete legacy[mode].mStandout;
          delete legacy[mode].mOnStandout;
        }
        ColorSchemeService.normalizeScheme(legacy, function (data) { root.normalized = data; });
        root.phase++;
      } else if (root.phase === 1 && root.normalized) {
        root.check("loader.legacy-dark", root.normalized.dark.mStandout === "#f88349", root.normalized.dark);
        root.check("loader.mode-identity", root.normalized.dark.mStandout === root.normalized.light.mStandout, root.normalized.light);
        ColorSchemeService.lastPredefinedSchemeData = root.normalized;
        ColorSchemeService.writeColorsToDisk(root.normalized.dark);
        root.phase++;
      } else if (root.phase === 2 && String(AtmoColor.mStandout) === "#f88349") {
        root.check("consumer.on-role", String(AtmoColor.mOnStandout) === "#571f00", String(AtmoColor.mOnStandout));
        root.check("consumer.resolvers", String(AtmoColor.resolveColorKey("standout")) === "#f88349" && String(AtmoColor.resolveColorKeyOptional("standout")) === "#f88349" && String(AtmoColor.resolveOnColorKey("standout")) === "#571f00", String(AtmoColor.mStandout));
        root.check("consumer.selector", AtmoColor.colorKeyModel.some(row => row.key === "standout"), AtmoColor.colorKeyModel);
        editor.open();
        editor.setColor("mStandout", "#abcdef");
        editor.setColor("mOnStandout", "#123456");
        root.check("editor.dirty", editor.isDirty("mStandout") && editor.isDirty("mOnStandout"), editor.editColors.dark);
        editor.applyColors();
        editor.setColor("mStandout", "#fedcba");
        editor.setColor("mOnStandout", "#654321");
        editor.setColor("mPrimary", "#aabbcc");
        root.phase++;
      } else if (root.phase === 3 && Settings.data.colorSchemes.predefinedScheme === "Custom") {
        saved.reload();
        root.phase++;
      } else if (root.phase === 4 && String(AtmoColor.mStandout) === "#abcdef" && ColorSchemeService.lastPredefinedSchemeData && ColorSchemeService.lastPredefinedSchemeData.dark.mStandout === "#abcdef") {
        var data = JSON.parse(saved.text());
        root.check("editor.saved-fill", data.dark.mStandout === "#abcdef", data.dark.mStandout);
        root.check("editor.saved-ink", data.dark.mOnStandout === "#123456", data.dark.mOnStandout);
        root.check("editor.other-mode", data.light.mStandout === "#f88349", data.light.mStandout);
        root.check("editor.concurrent-edit-remains-dirty", editor.getColor("mStandout") === "#fedcba" && editor.isDirty("mStandout"), {edit: editor.getColor("mStandout"), original: editor.originalColors.dark.mStandout});
        root.check("editor.concurrent-on-edit-remains-dirty", editor.getColor("mOnStandout") === "#654321" && editor.isDirty("mOnStandout"), editor.originalColors.dark.mOnStandout);
        root.check("editor.concurrent-other-role-remains-dirty", editor.getColor("mPrimary") === "#aabbcc" && editor.isDirty("mPrimary"), editor.originalColors.dark.mPrimary);
        root.check("editor.acknowledges-submitted-snapshot", editor.originalColors.dark.mStandout === "#abcdef" && editor.originalColors.dark.mOnStandout === "#123456", editor.originalColors.dark);
        editor.applyColors();
        root.phase++;
      } else if (root.phase === 5 && String(AtmoColor.mStandout) === "#fedcba" && !editor.isDirty("mStandout")) {
        saved.reload();
        root.phase++;
      } else if (root.phase === 6) {
        var data = JSON.parse(saved.text());
        root.check("editor.second-apply-persists-later-edits", data.dark.mStandout === "#fedcba" && data.dark.mOnStandout === "#654321" && data.dark.mPrimary === "#aabbcc", data.dark);
        editor.close();
        editor.open();
        root.check("editor.reopen", editor.getColor("mStandout") === "#fedcba" && !editor.isDirty("mStandout"), editor.editColors.dark);
        root.check("consumer.reload", String(AtmoColor.mOnStandout) === "#654321", String(AtmoColor.mOnStandout));
        var first = JSON.parse(JSON.stringify(ColorSchemeService.lastPredefinedSchemeData));
        first.dark.mStandout = "#112233";
        ColorSchemeService.saveCustomScheme(first, function (success) { root.saveCompletions.push({name: "first", success: success}); });
        first.dark.mStandout = "#ffccdd";
        var second = JSON.parse(JSON.stringify(first));
        second.dark.mStandout = "#445566";
        ColorSchemeService.saveCustomScheme(second, function (success) { root.saveCompletions.push({name: "second", success: success}); });
        second.dark.mStandout = "#ccbbaa";
        root.phase++;
      } else if (root.phase === 7 && root.saveCompletions.length === 2) {
        saved.reload();
        root.phase++;
      } else if (root.phase === 8) {
        var data = JSON.parse(saved.text());
        root.check("service.save-order", root.saveCompletions.every(row => row.success) && root.saveCompletions.map(row => row.name).join(",") === "first,second", root.saveCompletions);
        root.check("service.owns-submitted-snapshots", data.dark.mStandout === "#445566", data.dark.mStandout);
        ColorSchemeService.applyScheme(Settings.configDir + "colorschemes/Custom/Custom.json");
        root.phase++;
      } else if (root.phase === 9 && String(AtmoColor.mStandout) === "#445566") {
        root.check("service.saved-snapshot-at-consumer", ColorSchemeService.lastPredefinedSchemeData.dark.mStandout === "#445566", String(AtmoColor.mStandout));
        Logger.i("StandoutTest", "STANDOUT_COMPLETE|" + JSON.stringify({cases: root.cases.length, passed: root.cases.every(row => row.pass)}));
        Qt.exit(root.cases.every(row => row.pass) ? 0 : 1);
      }
    }
  }
}
