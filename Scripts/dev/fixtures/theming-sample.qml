import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Theming

ShellRoot {
  id: root
  SettingsBootstrap {
    id: directories
  }
  property int phase: 0
  property int completions: 0
  property string red: ""
  readonly property string fixtures: Quickshell.env("THEMING_SAMPLE_FIXTURES")

  Connections {
    target: TemplateProcessor
    function onColorsGenerated() {
      ++root.completions;
      reader.path = "";
      reader.path = Settings.configDir + "colors.json";
      if (!reader.waitForJob() || !reader.loaded) {
        Qt.exit(3);
        return;
      }
      const colors = JSON.parse(reader.text());
      const value = colors.mPrimary;
      if (root.phase === 1 && value && value !== "#000000") {
        root.red = value;
        root.phase = 2;
        TemplateProcessor.processWallpaperColors(root.fixtures + "/red.svg", "dark");
        TemplateProcessor.processWallpaperColors(root.fixtures + "/blue.svg", "dark");
      } else if (root.phase === 2 && value && value !== root.red) {
        root.phase = 3;
        TemplateProcessor.processWallpaperColors(root.fixtures + "/malformed.svg", "dark");
        rejected.start();
      } else {
        console.error("THEMING_SAMPLE unexpected output", root.phase, value, root.completions);
        Qt.exit(4);
      }
    }
  }
  FileView {
    id: reader
    printErrors: false
  }
  Timer {
    interval: 20
    repeat: true
    running: root.phase === 0
    onTriggered: {
      if (!directories.ready || !Settings.isLoaded)
        return;
      Settings.data.colorSchemes.useWallpaperColors = true;
      Settings.data.colorSchemes.generationMethod = "faithful";
      root.phase = 1;
      TemplateProcessor.processWallpaperColors(root.fixtures + "/red.svg", "dark");
    }
  }
  Timer {
    id: rejected
    interval: 1500
    onTriggered: {
      console.log("THEMING_SAMPLE PASS", root.red, root.completions);
      Qt.exit(root.completions === 2 ? 0 : 5);
    }
  }
  Timer {
    interval: 8000
    running: true
    onTriggered: {
      console.error("THEMING_SAMPLE timeout", root.phase, directories.ready, Settings.isLoaded, Settings.store.error);
      Qt.exit(6);
    }
  }
}
