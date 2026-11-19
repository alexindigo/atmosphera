import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property string mode: Quickshell.env("RELOAD_REVIEW_CASE")
  property bool armed: false
  property bool started: false
  property int receipts: 0
  SettingsBootstrap { }
  FileView { id: writer; blockWrites: true; printErrors: false }
  function check(value, message) {
    if (!value) {
      console.error("RELOAD_REVIEW_ASSERT: " + message);
      Qt.exit(2);
      throw new Error(message);
    }
  }
  function finish() {
    console.log("RELOAD_REVIEW: PASS " + mode);
    Qt.exit(0);
  }
  function replace(path, value) {
    writer.path = path;
    writer.setText(JSON.stringify(value));
  }
  function registry(states) { return {version: 6, sources: [], states: states}; }
  Connections {
    target: root.mode.startsWith("colors") ? AtmoColor : null
    function onMPrimaryChanged() {
      if (root.mode !== "colors-live" || root.armed) return;
      root.armed = true;
      root.replace(Settings.configDir + "colors.json", JSON.parse(Quickshell.env("RELOAD_REVIEW_PALETTE")));
      AtmoColor.reloadFromDisk(function (result) {
        root.check(result.status === "reloaded", "follow-up color read accepted");
        root.check(String(AtmoColor.mPrimary).toLowerCase() === "#123456", "receipt covers replacement palette, not live old read");
        root.finish();
      });
    }
  }
  Connections {
    target: root.mode.startsWith("registry") ? Registry : null
    function onPluginStatesChanged() {
      if (root.mode !== "registry-live" || root.armed) return;
      root.armed = true;
      root.replace(Registry.pluginsFile, root.registry({replacement: {enabled: false, sourceUrl: null}}));
      Registry.reloadFromDisk(function (result) {
        root.check(result.status === "reloaded", "explicit scan completed");
        root.check(!!Registry.pluginStates.replacement, "startup scan cannot acknowledge explicit read");
        root.finish();
      });
    }
    function onPluginsChanged() {
      if (root.started || root.mode === "registry-live") return;
      root.started = true;
      Qt.callLater(function () { root.afterRegistry(); });
    }
  }
  function afterRegistry() {
    console.log("RELOAD_REVIEW: after registry " + root.mode);
    if (root.mode === "registry-invalid") {
      check(!!Registry.pluginStates.original, "last-good state ready");
      replace(Registry.pluginsFile, registry({broken: null}));
      Registry.reloadFromDisk(function (result) {
        check(result.status === "failed", "malformed state refused");
        check(!!Registry.pluginStates.original && !Registry.pluginStates.broken, "invalid read preserves active state");
        replace(Registry.pluginsFile, registry({repaired: {enabled: false, sourceUrl: null}}));
        Registry.reloadFromDisk(function (retry) {
          check(retry.status === "reloaded" && !!Registry.pluginStates.repaired, "validation refusal releases request for retry");
          finish();
        });
      });
    } else if (root.mode === "registry-write") {
      Registry.save();
      Registry.reloadFromDisk(function (result) {
        root.check(result.status === "reloaded" && !!Registry.pluginStates.original, "reload waits for registry writer");
        root.finish();
      });
    } else if (root.mode === "registry-missing") {
      check(!!Registry.getPluginManifest("example"), "original manifest ready");
      remove.command = ["rm", Registry.pluginsDir + "/example/manifest.json"];
      remove.running = true;
    }
  }
  Process {
    id: remove
    onExited: code => {
      root.check(code === 0, "owned fixture removal");
      Registry.reloadFromDisk(function (result) {
        root.check(result.status === "reloaded" && !Registry.getPluginManifest("example"), "full scan removes missing manifest before receipt");
        root.finish();
      });
    }
  }
  Timer {
    interval: 700; repeat: true; running: root.mode === "colors-reentry"
    onTriggered: {
      if (root.started || AtmoColor.skipTransition || !Settings.isLoaded) return;
      root.started = true;
      AtmoColor.reloadFromDisk(function (first) {
        root.check(first.status === "reloaded", "first idle read");
        AtmoColor.reloadFromDisk(function (second) {
          root.check(second.status === "reloaded", "same-owner callback reentry read");
          root.finish();
        });
      });
    }
  }
  Timer {
    interval: 10000; running: true
    onTriggered: { console.error("RELOAD_REVIEW_ASSERT: watchdog " + root.mode); Qt.exit(2); }
  }
}
