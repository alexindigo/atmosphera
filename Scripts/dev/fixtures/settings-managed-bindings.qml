import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Keyboard

// The real FIFO and native retained groups are under test. An intentionally
// stopped setup callback keeps deployment outside this persistence witness.
ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: probe
        readonly property string mode: Quickshell.env("MANAGED_BINDINGS_CASE")
        property bool started: false
        property int attempts: 0
        property int environmentRequests: 0
        property bool waitingForReset: false
        property bool waitingForExternal: false
        function check(ok, label) {
          if (!ok) throw new Error("MANAGED_BINDINGS_ASSERT: " + label);
        }
        function guard(callback) {
          try { callback(); }
          catch (error) { console.error(String(error)); Qt.exit(2); }
        }
        function finish() {
          Settings.store.close(function (result) {
            probe.guard(function () {
              check(result.status !== "failed", "native owner closes without stopped groups");
              console.log("MANAGED_BINDINGS: PASS " + mode);
              Qt.exit(0);
            });
          });
        }
        function begin() {
          if (started || !Settings.isLoaded) return;
          started = true;
          BindingsService.init(function (environment, complete) { complete(true, ""); });
          if (mode === "reset-section" || mode === "reset-value") {
            var captured = "";
            var path = mode === "reset-section" ? ["bindings"] : ["bindings", "environment"];
            Settings.saveBindingsEnvironment("none", function (result) {
              probe.guard(function () {
                check(result.status === "saved", "reset removal saved");
                check(captured === "macos" && Settings.data.bindings.environment === "macos", "reset captures the inherited environment, not an explicit default");
                Settings.releaseManagedRequest("direct-reset");
                finish();
              });
            }, "direct-reset", "", path, function (environment) { captured = environment; });
          } else if (mode === "reset-pending") {
            BindingsService.requestEnvironment("macos", null, {prepare: function (work, complete, identity) {
              Settings.saveBindingsEnvironment("macos", function (result) {
                probe.guard(function () {
                  check(result.status === "saved", "earlier pending capture saved");
                  Settings.releaseManagedRequest(identity + "-boundary");
                  complete({status: "failed", error: {code: "intentional-no-deployment"}});
                  check(BindingsService.queueCount === 2, "reset survives an earlier capture whose callback was pending");
                  finish();
                });
              }, identity + "-boundary", "");
              Settings.resetSection("bindings");
            }});
          } else if (mode === "reset-queue") {
            BindingsService.requestEnvironment("macos", function (success) {
              probe.guard(function () {
                check(!success, "intentional setup stop keeps deployment out of this witness");
                if (attempts === 1) {
                  Settings.resetSection("bindings");
                  waitingForReset = true;
                }
              });
            }, {prepare: function (work, complete, identity) {
              attempts++;
              if (attempts === 1) {
                complete({status: "failed", error: {code: "intentional-setup-stop"}});
                return;
              }
              Settings.saveBindingsEnvironment("macos", function (result) {
                probe.guard(function () {
                  check(result.status === "saved" || result.status === "nothing_to_save", "earlier request native save succeeds after Retry");
                  Settings.releaseManagedRequest(identity + "-boundary");
                  complete({status: "failed", error: {code: "intentional-no-deployment"}});
                  check(attempts === 2 && Settings.data.bindings.environment === "macos", "head save is not blocked by a later reset");
                  check(BindingsService.queueCount === 2, "waiting reset remains behind the stopped head");
                  finish();
                });
              }, identity + "-boundary", "");
            }});
          } else {
            // Hold the real queue head before its save. An unrelated disk edit
            // must not append the unchanged accepted environment behind it.
            BindingsService.requestEnvironment("macos", null, {prepare: function () {}});
            waitingForExternal = true;
            externalUi.setText('{"fontDefaultScale":1.37}');
          }
        }
        FileView { id: externalUi; path: Settings.overridesDir + "ui.json"; printErrors: false }
        Connections {
          target: Settings
          function onBindingsEnvironmentRequested() { probe.environmentRequests++; }
          function onSettingsReloaded() {
            if (!probe.waitingForExternal) return;
            probe.waitingForExternal = false;
            probe.guard(function () {
              check(Settings.data.ui.fontDefaultScale === 1.37, "external setting reached the consumer");
              check(environmentRequests === 0 && BindingsService.queueCount === 1, "unchanged disk environment does not append a choice");
              finish();
            });
          }
        }
        Timer {
          interval: 10
          running: true
          repeat: true
          onTriggered: {
            probe.guard(function () {
              probe.begin();
              if (probe.waitingForReset && BindingsService.queueCount === 2) {
                probe.waitingForReset = false;
                BindingsService.retryHead();
              }
            });
          }
        }
      }
    }
  }
  Timer { interval: 15000; running: true; onTriggered: { console.error("MANAGED_BINDINGS_ASSERT: watchdog"); Qt.exit(2); } }
}
