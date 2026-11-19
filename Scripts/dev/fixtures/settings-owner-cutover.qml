import QtQuick
import Quickshell
import qs.Commons

// Run only in a disposable workspace through settings-cutover-regression.py.
ShellRoot {
  id: root
  property bool started: false
  property int checks: 0
  property string lastCompletion: ""
  function check(ok, label) {
    if (!ok) throw new Error("I5_OWNER_ASSERT: " + label);
    checks++;
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function start() {
    if (started || !Settings.isLoaded) return;
    started = true;
    try {
      check(Settings.data === Settings.store.values, "one production namespace");
      check(Settings.data.settingsVersion === 62, "compatibility version");
      if (Quickshell.env("I5_OWNER_MANAGED") === "1") {
        managed();
        return;
      }
      if (Quickshell.env("I5_OWNER_RESTART") === "1") {
        check(Settings.data.general.scaleRatio === 1.61, "cold scalar consumer");
        check(Settings.data.ui.fontDefault === "owner-cutover", "cold draft consumer");
        console.log("I5_OWNER: PASS restart " + checks);
        Settings.store.close(function (result) {
          try { check(result.status === "nothing_to_save", "cold close no write"); Qt.exit(0); }
          catch (error) { fail(error); }
        });
        return;
      }
      var editor = Settings.createEditor("ui.fontDefault");
      check(editor !== null, "native draft adapter");
      var before = Settings.data.ui.fontDefault;
      editor.apply("owner-cutover", function (result) {
        try {
          console.log("I5_OWNER_RECEIPT: draft " + JSON.stringify(result));
          check(result.status === "saved", "draft save receipt");
          check(Settings.data.ui.fontDefault === "owner-cutover", "draft store consumer");
          check(editor.initialValue === "owner-cutover", "draft refreshed consumer");
          check(editor.discard(), "draft delivery detach");
          Settings.data.general.scaleRatio = 1.61;
          check(Settings.data.general.scaleRatio === 1.61, "immediate scalar consumer");
          var synchronous = true;
          Settings.saveResult(function (saved) {
            try {
              console.log("I5_OWNER_RECEIPT: scalar " + JSON.stringify(saved));
              check(!synchronous && saved.status === "saved", "async scalar save");
              Settings.store.close(function (closed) {
                try {
                  check(closed.status === "nothing_to_save", "close settled");
                  console.log("I5_OWNER: PASS save " + checks);
                  Qt.exit(0);
                } catch (error) { fail(error); }
              });
            } catch (error) { fail(error); }
          });
          synchronous = false;
        } catch (error) { fail(error); }
      });
      check(Settings.data.ui.fontDefault === before, "unapplied draft isolated");
    } catch (error) { fail(error); }
  }
  function managed() {
    function values() {
      check(Settings.data.general.scaleRatio === 1.74, "retained setup scale consumer");
      check(Settings.data.bar.position === "left", "retained setup bar consumer");
      check(Settings.data.wallpaper.directory === "/owner-wallpapers", "retained setup wallpaper consumer");
      check(Settings.data.bindings.environment === "macos", "retained binding consumer");
    }
    function close() {
      Settings.store.close(function (result) {
        try {
          check(result.status === "nothing_to_save", "managed async close");
          console.log("I5_OWNER: PASS managed " + checks);
          Qt.exit(0);
        } catch (error) { fail(error); }
      });
    }
    if (Quickshell.env("I5_OWNER_RESTART") === "1") {
      values();
      close();
      return;
    }
    Settings.beginManagedBindings();
    var sync = true;
    Settings.saveSetupWork({scaleRatio: 1.74, barPosition: "left", wallpaperDirectory: "/owner-wallpapers"}, function (result) {
      try {
        console.log("I5_OWNER_MANAGED_RECEIPT: " + JSON.stringify({status: result.status, code: result.error?.code, operation: result.operation, groupToken: result.groupToken}));
        check(!sync && result.status === "saved", "setup async native receipt");
        check(lastCompletion === result.requestId, "setup signal before callback");
        var token = Settings._groups["owner-managed:setup"];
        var capture = Settings.store.groupInfo(token);
        check(capture.state === "succeeded" && capture.capturePrefix === result.capturePrefix, "setup native retained identity");
        Settings.saveBindingsEnvironment("macos", function (binding) {
          try {
            check(binding.status === "saved" && lastCompletion === binding.requestId, "binding receipt ordering");
            values();
            Settings.releaseManagedRequest("owner-managed");
            Settings.saveSetupWork({}, function (invalid) {
              try {
                check(invalid.status === "failed" && lastCompletion === invalid.requestId, "missing id ordered failure");
                close();
              } catch (error) { fail(error); }
            }, "");
          } catch (error) { fail(error); }
        }, "owner-managed");
      } catch (error) { fail(error); }
    }, "owner-managed");
    sync = false;
  }
  Connections {
    target: Settings
    function onSettingsLoaded() { Qt.callLater(root.start); }
    function onSettingsSaveCompleted(result) { root.lastCompletion = result.requestId; }
  }
  Component.onCompleted: Qt.callLater(start)
  Timer { running: true; interval: 25000; onTriggered: root.fail("owner timeout") }
}
