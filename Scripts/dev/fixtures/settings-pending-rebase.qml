// Inert real-schema witness for the selected publication policy.
import ConfigQml 1.0
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Main

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_REBASE_DIR")
  readonly property string scenario: Quickshell.env("I5_REBASE_CASE")
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var cfg: store.values
  readonly property real scaleConsumer: cfg.ui.fontDefaultScale
  readonly property var keyConsumer: cfg.general.keybinds.keyUp
  readonly property var siblingConsumer: cfg.general.keybinds.keyDown
  property int overridden: 0
  property bool started: false

  function check(ok, label) {
    if (!ok)
      throw new Error("I5_PENDING_REBASE_ASSERT: " + label);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function verify() {
    if (scenario === "unknown-only") {
      check(scaleConsumer === 1.61, "original pending scale reaches consumer");
    } else {
      check(keyConsumer.length === 1 && keyConsumer[0] === "F9", "original pending descendant reaches consumer");
      var expected = scenario === "parent-remove" ? "F4" : "F2";
      check(siblingConsumer.length === 1 && siblingConsumer[0] === expected, "foreign sibling or legacy fallback reaches consumer");
    }
    check(cfg.bar.widgets.left[0].opaque.keep === true, "unrelated raw widget extension retained");
  }
  function begin() {
    if (!store.ready || started)
      return;
    started = true;
    try {
      if (verifyOnly) {
        verify();
        console.log("I5_PENDING_REBASE: RESTART_PASS");
        Qt.exit(0);
        return;
      }
      if (scenario === "unknown-only")
        cfg.ui.fontDefaultScale = 1.61;
      else
        cfg.general.keybinds.keyUp = ["F9"];
      // The save below is ordered after this explicit worker settlement, but it
      // does not recapture/reassign the pending edit after the foreign write.
      writer.running = true;
    } catch (error) { fail(error); }
  }

  Main.SettingsSources {
    id: routes
    settingsFile: root.directory + "/settings.json"
    overridesDirectory: root.directory + "/settings"
  }
  ConfigStore {
    id: store
    autoSave: false
    evidenceDirectory: root.directory + "/evidence"
    schema: Main.SettingsSchema {
      homeDirectory: "/inert/home"
      defaultFont: "Test Sans"
      fixedFont: "Test Mono"
    }
    sources: routes.sources
    onReadyChanged: root.begin()
    onSourceWarning: function(warning) {
      if (warning.code === "foreign-value-overridden")
        root.overridden++;
    }
    onStatusChanged: {
      if (status === ConfigStore.Error)
        root.fail("store initialization: " + error);
    }
  }
  Process {
    id: writer
    command: ["python3", "-B", "-c", "import os,sys; from pathlib import Path; p=Path(sys.argv[1]); q=p.with_suffix('.foreign'); q.write_bytes(Path(sys.argv[2]).read_bytes()); os.replace(q,p)", root.directory + "/settings/" + (root.scenario === "unknown-only" ? "ui" : "general") + ".json", root.directory + "/foreign.json"]
    onExited: function(code) {
      if (code !== 0) {
        root.fail("foreign writer failed");
        return;
      }
      store.reload(function(loaded) {
        try {
          root.check(loaded.status === "reloaded", "foreign source accepted");
          root.verify();
          store.save(function(result) {
            try {
              console.log("I5_PENDING_REBASE_RECEIPT: " + JSON.stringify(result));
              root.check(result.status === "saved", "successful publication, not retained failure");
              root.verify();
              root.check(root.scenario === "unknown-only" ? root.overridden === 0 : root.overridden === 1, "truthful local-wins overlap warning");
              console.log("I5_PENDING_REBASE: SAVED_PASS");
              Qt.exit(0);
            } catch (error) { root.fail(error); }
          });
        } catch (error) { root.fail(error); }
      });
    }
  }
  Timer { interval: 20000; running: true; onTriggered: root.fail("pending rebase watchdog") }
}
