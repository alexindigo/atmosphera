import QtQuick
import Quickshell
import "../../../Helpers/OwnedProcess.js" as OwnedProcess
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  property bool started: false
  property var owner: null
  property var api: null
  property var profile: null
  readonly property string mode: Quickshell.env("I5_PROFILE_MODE")
  readonly property string image: Quickshell.env("I5_PROFILE_IMAGE")
  readonly property color colorConsumer: AtmoColor.mPrimary
  property int completions: 0
  property bool concurrentInput: false
  readonly property bool negative: mode.indexOf("failure") !== -1
  function command(arguments, callback) {
    OwnedProcess.run(root, arguments, null, function (result) {
      try { check(result.success, "fault setup/restore"); callback(); }
      catch (error) { fail(error); }
    });
  }
  function check(ok, label) { if (!ok) throw new Error("I5_PROFILE_ASSERT: " + label); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function close() {
    Service.synchronizePreferences("save", function (receipt) {
      try {
        check(receipt.status === "current", "final settings receipt");
        console.log("I5_PROFILE_RUNTIME: PASS " + mode);
        Qt.exit(0);
      } catch (error) { fail(error); }
    });
  }
  Timer {
    id: verifyConsumers
    interval: 1200
    onTriggered: {
      try {
        check(String(root.colorConsumer) === "#123456", "actual color consumer after apply");
        check(!Registry.isPluginEnabled("shell-profiles"), "actual registry consumer after apply");
        close();
      } catch (error) { fail(error); }
    }
  }
  function expectFailure(ok, message) {
    check(!ok && profile.lastAppliedProfile === "previous", "failure never advances last applied");
    check(Settings.data.bar.position === (mode === "receipt-failure" || mode === "concurrent-failure" ? "bottom" : "top"), "failure preserves actual setting consumer");
    if (mode === "concurrent-failure") {
      check(concurrentInput && Settings.data.ui.fontDefaultScale === 1.7, "concurrent local input retained");
      check(["profile-concurrent-edit", "profile-reload-receipt"].indexOf(message) !== -1, "concurrent input refuses profile completion");
    } else check(message === {"backup-failure": "profile-backup-failed", "copy-failure": "profile-copy-failed",
      "receipt-failure": "profile-last-applied-receipt", "wallpaper-failure": "profile-wallpapers-read",
      "save-failure": "profile-settings-receipt"}[mode], "precise failure callback " + message);
    if (mode === "receipt-failure") check(api.pluginSettings.lastAppliedProfile === "saved" &&
      owner.store.info(["settings", "lastAppliedProfile"]).intentRevision !== "0", "failed native marker retains work");
    // Keep the fault through process shutdown, so a flush cannot erase the
    // observed failed-save endpoint. The VM runner restores permissions after
    // checking raw files and after this owned process has exited.
    console.log("I5_PROFILE_RUNTIME: PASS " + mode);
    Qt.exit(0);
  }
  function apply() {
    if (mode === "concurrent-failure") {
      var inject = function (event) {
        if (event.origin !== "external" || Settings.data.bar.position !== "bottom" ||
            !event.changedPaths.some(function (path) { return path[0] === "bar"; })) return;
        Settings.store.sourceAccepted.disconnect(inject);
        concurrentInput = true;
        Settings.data.ui.fontDefaultScale = 1.7;
      };
      Settings.store.sourceAccepted.connect(inject);
    }
    profile.applyProfile("saved", mode === "wallpapers" || mode === "wallpaper-failure", function (ok, message, result) {
      try {
        if (negative) { expectFailure(ok, message); return; }
        check(ok, "actual apply callback " + message);
        check(result.outcomes.settings.status === "current" && result.outcomes.colors.status === "reloaded" &&
          result.outcomes.registry.status === "reloaded", "independent owners acknowledged reload");
        check(Settings.data.bar.position === "bottom", "actual settings consumer after apply");
        check(profile.lastAppliedProfile === "saved" && api.pluginSettings.lastAppliedProfile === "saved", "last applied after acknowledged save");
        if (mode === "wallpapers") {
          check(result.outcomes.wallpapers.status === "changed", "separate wallpaper outcome");
          check(WallpaperService.getWallpaperPathForSlot("fixture-screen", "light") === image &&
            WallpaperService.getWallpaperPathForSlot("fixture-screen", "dark") === image, "actual requested wallpaper consumer");
        } else {
          check(result.outcomes.wallpapers.status === "not_requested", "settings-only apply has no wallpaper effect");
        }
        verifyConsumers.start();
      } catch (error) { fail(error); }
    });
  }
  function run() {
    try {
      if (mode === "cold") {
        check(Settings.data.bar.position === "bottom", "cold actual settings consumer");
        check(profile.lastAppliedProfile === "saved", "cold last-applied consumer");
        AtmoColor.reloadFromDisk(function (receipt) {
          try {
            check(receipt.status === "reloaded", "cold independent color owner ready");
            verifyConsumers.start();
          } catch (error) { fail(error); }
        });
        return;
      }
      if (mode === "save-failure") {
        Settings.data.bar.position = "top";
        command(["chmod", "0555", Settings.overridesDir], function () {
          profile.saveProfile("saved", function (ok, message) {
            try { expectFailure(ok, message); }
            catch (error) { fail(error); }
          });
        });
        return;
      }
      if (mode === "wallpapers") {
        WallpaperService.changeWallpaper(image, "fixture-screen", "light");
        WallpaperService.changeWallpaper(image, "fixture-screen", "dark");
      }
      profile.saveProfile("saved", function (ok, message, result) {
        try {
          console.log("I5_PROFILE_SNAPSHOT_RECEIPT: " + JSON.stringify({status: result.outcomes.settings.status,
            refreshState: result.outcomes.settings.refreshState, error: result.outcomes.settings.error}));
          check(ok && result.outcomes.settings.status === "current", "actual snapshot callback " + message);
          Settings.data.bar.position = "top";
          Service.synchronizePreferences("save", function (receipt) {
            try {
              check(receipt.status === "current", "changed setting acknowledged before apply");
              if (mode === "backup-failure") {
                command(["chmod", "0555", Settings.configDir + "profiles/_backups"], apply);
              } else if (mode === "copy-failure") {
                command(["python3", "-c", "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['entries']['settings/bar.json']['sha256']='bad'; open(p,'w').write(json.dumps(d))",
                  Settings.configDir + "profiles/saved/_config-files.json"], apply);
              } else if (mode === "wallpaper-failure") {
                command(["python3", "-c", "import sys; open(sys.argv[1],'w').write('{\"screens\":false}')",
                  Settings.configDir + "profiles/saved/wallpapers.json"], apply);
              } else {
                if (mode === "receipt-failure") {
                  var nativeSave = api.saveSettings;
                  api.saveSettings = function (callback) {
                    command(["chmod", "0555", Settings.overridesDir + "plugins"], function () { nativeSave(callback); });
                  };
                }
                if (negative) { apply(); return; }
                command(["python3", "-c", "import json,sys; c=json.load(open(sys.argv[1])); c={k:'#abcdef' for k in c}; open(sys.argv[1],'w').write(json.dumps(c)); p=json.load(open(sys.argv[2])); p['states']['shell-profiles']['enabled']=True; open(sys.argv[2],'w').write(json.dumps(p))",
                  Settings.configDir + "colors.json", Settings.configDir + "plugins.json"], function () {
                  AtmoColor.reloadFromDisk(function (colors) {
                    try {
                      check(colors.status === "reloaded", "changed colors acknowledged before apply");
                      Registry.reloadFromDisk(function (registry) {
                        try {
                          check(registry.status === "reloaded" && Registry.isPluginEnabled("shell-profiles"), "changed registry consumer before apply");
                          apply();
                        } catch (error) { fail(error); }
                      });
                    } catch (error) { fail(error); }
                  });
                });
              }
            } catch (error) { fail(error); }
          });
        } catch (error) { fail(error); }
      });
    } catch (error) { fail(error); }
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    Service._openSettingsOwner("shell-profiles", function (opened) {
      try {
        check(opened !== null, "real profile preference owner");
        owner = opened;
        api = Service.createPluginAPI("shell-profiles", {id: "shell-profiles", metadata: {}}, owner, {}, {}, {});
        Service.loadedPlugins["shell-profiles"] = {api: api};
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, "actual profile Main component " + component.errorString());
        profile = component.createObject(root, {pluginApi: api});
        check(profile !== null, "actual profile Main construction");
        Qt.callLater(run);
      } catch (error) { fail(error); }
    });
  }
  Timer { interval: 10; repeat: true; running: true; onTriggered: root.begin() }
  Timer { interval: 45000; running: true; onTriggered: root.fail("profile runtime timeout") }
}
