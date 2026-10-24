import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
import qs.Services.Theming
import qs.Modules.FileChooser
import qs.Modules.Panels.Settings.Tabs.ColorScheme
import qs.Modules.Panels.SetupWizard

ShellRoot {
  id: root
  property var palettes: JSON.parse(Quickshell.env("THEME_TEST_PALETTES"))
  property int phase: 0
  property int ticks: 0
  property int faultIndex: 0
  property var faults: ["start", "bad-json", "bad-snapshot", "wrong-authored", "timeout", "reject-input"]
  property bool fence: false
  property bool transitioned: false
  property bool intermediate: false
  property double changedAt: 0
  property var cases: []
  function copy(value) { return JSON.parse(JSON.stringify(value)); }
  function legacy(value, fault, tag) {
    var result = copy(value);
    for (const mode of ["dark", "light"]) {
      delete result[mode].mStandout;
      delete result[mode].mOnStandout;
      result[mode]._fault = fault;
      result[mode]._tag = tag;
    }
    return result;
  }
  function check(name, passed, actual) {
    cases.push({name: name, pass: !!passed, actual: actual});
    Logger.i("ThemeLoadTest", "THEME_LOAD_CASE|" + JSON.stringify(cases[cases.length - 1]));
  }
  function coherent(palette) {
    return AtmoColor.roleKeys.every(key => String(AtmoColor[key]).toLowerCase() === palette.dark[key].toLowerCase());
  }
  function fenceQueue(tag) {
    fence = false;
    ColorSchemeService.normalizeScheme(legacy(palettes.a, "", tag), function (value) {
      root.fence = !!value;
    });
  }
  PanelWindow {
    implicitWidth: 240
    implicitHeight: 220
    Rectangle { id: widget; width: 96; height: 32; color: AtmoColor.mPrimary }
    FileIcon { id: icon; y: 40; width: 96; height: 96; descriptor: ({type: "zip", group: "archives", folder: "", hidden: false}) }
    ColorsSubTab { id: cards; visible: false }
    SchemeDownloader { id: downloads; visible: false }
    SetupAppearanceStep { id: setup; visible: false }
    ColorCustomizer { id: editor }
  }
  property string goodFace: ""
  ThemingFileOracle { id: saved; path: Settings.configDir + "colors.json" }
  Process { id: corrupt; stdout: StdioCollector {} }
  Connections {
    target: AtmoColor
    function onIsTransitioningChanged() { if (AtmoColor.isTransitioning) root.transitioned = true; }
  }
  Timer {
    interval: 10
    repeat: true
    running: AtmoColor.isTransitioning && root.phase === 5
    onTriggered: {
      const value = String(widget.color).toLowerCase();
      if (value !== root.palettes.b.dark.mPrimary.toLowerCase() && value !== root.palettes.c.dark.mPrimary.toLowerCase())
        root.intermediate = true;
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 900) {
        root.check("watchdog", false, {phase: root.phase, fault: root.faultIndex});
        Qt.exit(2);
      }
      if (!Settings.isLoaded)
        return;
      if (root.phase === 0 && !AtmoColor.skipTransition) {
        Settings.data.general.animationDisabled = true;
        Settings.data.colorSchemes.useWallpaperColors = false;
        root.check("first-failure-keeps-defaults", root.coherent(root.palettes.a), String(icon.paints.face));
        var authored = root.copy(root.palettes.b);
        authored.dark._fault = "start";
        authored.light._fault = "start";
        authored.dark._tag = "complete-without-worker";
        ColorSchemeService.normalizeScheme(authored, function (value) { root.check("complete-snapshot-without-worker", !!value, value && value.dark.mStandout); });
        AtmoColor.loadColors(authored);
        root.phase++;
      } else if (root.phase === 1 && root.coherent(root.palettes.b) && !AtmoColor.skipTransition) {
        root.goodFace = String(icon.paints.face);
        root.phase++;
      } else if (root.phase === 2) {
        if (root.faultIndex === root.faults.length) {
          corrupt.command = ["python3", "-c", "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('{broken')", Settings.configDir + "colors.json"];
          corrupt.running = true;
          root.changedAt = Date.now();
          root.phase = 4;
          return;
        }
        const fault = root.faults[root.faultIndex];
        AtmoColor.loadColors(fault === "reject-input" ? {brand: "#112233"} : root.legacy(root.palettes.a, fault, fault));
        root.fenceQueue("fence-" + fault);
        root.phase++;
      } else if (root.phase === 3 && root.fence) {
        root.check("failure-" + root.faults[root.faultIndex], root.coherent(root.palettes.b) && !AtmoColor.skipTransition && String(widget.color).toLowerCase() === root.palettes.b.dark.mPrimary.toLowerCase() && String(icon.paints.face) === root.goodFace,
                   {widget: String(widget.color), icon: String(icon.paints.face), skip: AtmoColor.skipTransition});
        root.faultIndex++;
        root.phase = 2;
      } else if (root.phase === 4 && !corrupt.running && Date.now() - root.changedAt > 1200) {
        root.check("bad-file-json-keeps-consumers", root.coherent(root.palettes.b) && !AtmoColor.skipTransition && String(icon.paints.face) === root.goodFace, String(widget.color));
        Settings.data.general.animationDisabled = false;
        AtmoColor.loadColors(root.palettes.c);
        root.phase++;
      } else if (root.phase === 5 && root.coherent(root.palettes.c) && !AtmoColor.isTransitioning) {
        root.check("animated-recovery", root.transitioned && root.intermediate && !AtmoColor.skipTransition, {transition: root.transitioned, intermediate: root.intermediate, widget: String(widget.color)});
        Settings.data.general.animationDisabled = true;
        AtmoColor.loadColors(root.legacy(root.palettes.a, "slow", "old-colours"));
        AtmoColor.loadColors(root.palettes.c);
        cards.schemeLoaded("Test", root.legacy(root.palettes.a, "slow", "old-card"));
        cards.schemeLoaded("Test", root.palettes.b);
        setup.schemeLoaded("Test", root.legacy(root.palettes.a, "slow", "old-setup"));
        setup.schemeLoaded("Test", root.palettes.b);
        var old = root.legacy(root.palettes.a, "slow", "old-download"); old.name = "Test";
        var good = root.copy(root.palettes.b); good.name = "Test";
        downloads.cacheSchemeColors(old);
        downloads.cacheSchemeColors(good);
        root.fenceQueue("fence-stale");
        root.phase++;
      } else if (root.phase === 6 && root.fence) {
        root.check("older-colour-result-cannot-win", root.coherent(root.palettes.c) && !AtmoColor.skipTransition, String(icon.paints.face));
        root.check("older-preview-results-cannot-win", cards.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout && setup.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout && downloads.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout, cards.getSchemeColor("Test", "mStandout"));
        cards.schemeLoaded("Test", root.legacy(root.palettes.a, "exit", "bad-card"));
        setup.schemeLoaded("Test", root.legacy(root.palettes.a, "exit", "bad-setup"));
        var bad = root.legacy(root.palettes.a, "exit", "bad-download"); bad.name = "Test";
        downloads.cacheSchemeColors(bad);
        root.fenceQueue("fence-rejected-previews");
        root.phase++;
      } else if (root.phase === 7 && root.fence) {
        root.check("failed-previews-keep-good-data", cards.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout && setup.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout && downloads.getSchemeColor("Test", "mStandout") === root.palettes.b.dark.mStandout, setup.getSchemeColor("Test", "mStandout"));
        ColorSchemeService.writeColorsToDisk(root.legacy(root.palettes.a, "slow", "old-write"));
        ColorSchemeService.writeColorsToDisk(root.palettes.b.dark);
        root.fenceQueue("fence-write");
        root.phase++;
      } else if (root.phase === 8 && root.fence && root.coherent(root.palettes.b)) {
        saved.reload();
        root.phase++;
      } else if (root.phase === 9 && saved.ready && root.coherent(root.palettes.b)) {
        root.check("older-write-cannot-win", JSON.parse(saved.text()).mStandout === root.palettes.b.dark.mStandout, String(icon.paints.face));
        ColorSchemeService.lastPredefinedSchemeData = root.copy(root.palettes.b);
        ColorSchemeService.lastPredefinedSchemeData.dark._fault = "save-fail";
        editor.open();
        editor.setColor("mStandout", "#abcdef");
        editor.applyColors();
        root.changedAt = Date.now();
        root.phase++;
      } else if (root.phase === 10 && Date.now() - root.changedAt > 1500) {
        root.check("failed-save-is-not-acknowledged", editor.isDirty("mStandout") && editor.originalColors.dark.mStandout === root.palettes.b.dark.mStandout, editor.originalColors.dark.mStandout);
        const passed = root.cases.every(row => row.pass);
        Logger.i("ThemeLoadTest", "THEME_LOAD_COMPLETE|" + JSON.stringify({passed: passed, cases: root.cases.length}));
        Qt.exit(passed ? 0 : 1);
      }
    }
  }
}
