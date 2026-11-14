import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import "../../../Helpers/OwnedProcess.js" as OwnedProcess

// Native port of plugin-settings-receipts.qml. One owner's queued captures stay
// queued; the application sequences dependent operations on independent owners.
Scope {
  id: root
  property bool started: false
  property var api: null
  property var bad: null
  property var linked: null
  property int signals: 0
  property var order: []
  property bool invalidRejected: false
  property bool firstReturned: false
  readonly property string failureDirectory: Quickshell.env("I5_RECEIPTS_IO_DIR")
  property string expected: "quote '\"\nPLUGIN_SETTINGS_EOF_not_a_delimiter\n\u96ea"
  property string consumer: api && api.settingsReady ? api.pluginSettings.label : ""
  function check(ok, message) { if (!ok) throw new Error("I4_PLUGIN_RECEIPTS_ASSERT: " + message); }
  function guard(fn) { try { fn(); } catch (error) { console.error(String(error)); Qt.exit(2); } }
  function outcome(result, status, label) {
    check(result.status === status && signals === order.length + 1, label + " status and signal-before-callback");
    order.push(label);
  }
  function open(key, callback) {
    var manifest = {id: key, metadata: {}, entryPoints: {}};
    Service.loadPluginData(key, manifest, function (owner, translations, fallback, state) {
      root.guard(function () {
        root.check(owner.status === "Ready", "actual native owner ready");
        callback(Service.createPluginAPI(key, manifest, owner, translations, fallback, state));
      });
    });
  }
  function clean() {
    api.saveSettings(function (result) {
      root.guard(function () {
        root.outcome(result, "nothing_to_save", "clean");
        root.check(root.order.join() === "first,invalid,second,bad,linked,clean", "FIFO including failed and reentrant work");
        Service.loadPluginSettings("i4-receipts", function (value) {
          root.guard(function () {
            root.check(value.label === root.expected && value.nested.keep === 1, "captured queued value reached file reader");
            console.log("I4_PLUGIN_RECEIPTS: SAVED_PASS"); Qt.exit(0);
          });
        });
      });
    });
  }
  function otherOwners() {
    // These are independent native stores, not one old shared serializer queue.
    // Preserve the observable workflow order explicitly at the caller boundary.
    OwnedProcess.run(root, ["chmod", "0555", failureDirectory], null, function (permission) {
      root.guard(function () {
        root.check(permission.success, "post-open permission failure prepared");
        root.bad.pluginSettings.label = "must fail";
        root.bad.saveSettings(function (failed) {
          root.guard(function () {
            root.outcome(failed, "failed", "bad");
            root.check(root.bad.pluginSettings.label === "must fail", "failed save retains effective work");
            OwnedProcess.run(root, ["chmod", "0755", root.failureDirectory], null, function (restored) {
              root.guard(function () {
                root.check(restored.success, "failure target permissions restored");
                root.linked.pluginSettings.label = "link target";
                root.linked.pluginSettings.opaque = {keep: true};
                root.linked.saveSettings(function (saved) {
                  root.guard(function () { root.outcome(saved, "saved", "linked"); root.clean(); });
                });
              });
            });
          });
        });
      });
    });
  }
  function submit() {
    api.settingsHandle.completed.connect(function (result) {
      if (result.operation === "write" && result.status === "failed" && result.error.code === "not-nullable") root.signals++;
    });
    api.pluginSettings.label = "first";
    api.pluginSettings.nested = {keep: 1};
    api.saveSettings(function (first) {
      root.guard(function () {
        root.check(root.firstReturned, "completion asynchronous");
        root.outcome(first, "saved", "first");
      });
    });
    firstReturned = true;
    try {
      api.settingsHandle.setUser(["label"], null, function (invalid) {
        root.guard(function () {
          root.check(root.invalidRejected, "native rejection also reported synchronously");
          root.outcome(invalid, "failed", "invalid");
        });
      });
    } catch (error) {
      check(String(error).indexOf("configqml: not-nullable") !== -1, "specific native invalid input rejection");
      invalidRejected = true;
    }
    check(invalidRejected, "invalid native input throws rather than becoming an untracked JS value");
    var submitted = {label: expected, nested: {keep: 1}};
    api.pluginSettings.label = submitted.label;
    api.pluginSettings.nested = submitted.nested;
    api.saveSettings(function (second) {
      root.guard(function () { root.outcome(second, "saved", "second"); root.otherOwners(); });
    });
    submitted.nested.keep = 999;
    check(api.pluginSettings.nested.keep === 1, "submitted child owned at native ingress");
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    open("i4-receipts", function (value) {
      root.api = value;
      if (Quickshell.env("I4_VERIFY") === "1") {
        root.guard(function () {
          root.check(root.consumer === root.expected && root.api.pluginSettings.nested.keep === 1, "restarted actual API consumer");
          console.log("I4_PLUGIN_RECEIPTS: RESTART_PASS"); Qt.exit(0);
        });
        return;
      }
      root.open("i4-receipts-bad", function (badApi) {
        root.guard(function () {
          var refused = false;
          try { badApi.pluginSettings.label = "quarantined input"; }
          catch (error) {
            root.check(String(error).indexOf("source-quarantined") !== -1, "specific startup quarantine refusal");
            refused = true;
          }
          root.check(refused && badApi.pluginSettings.label === "base", "quarantine never admits an unsavable choice");
          root.open("i4-receipts-io", function (ioApi) {
            root.bad = ioApi;
            root.open("i4-receipts-linked", function (linkedApi) { root.linked = linkedApi; root.guard(root.submit); });
          });
        });
      });
    });
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) { root.signals++; }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 60000; running: true; onTriggered: { console.error("I4_PLUGIN_RECEIPTS_ASSERT: watchdog"); Qt.exit(2); } }
}
