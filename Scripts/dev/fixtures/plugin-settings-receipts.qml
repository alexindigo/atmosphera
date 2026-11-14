// Inert actual old-plugin-owner witness; copied into an installed candidate.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

Scope {
  id: root
  property bool started: false
  property var api: null
  property int signals: 0
  property var order: []
  property string consumer: api ? api.pluginSettings.label : ""
  property string key: "i4-receipts"
  property string expected: "quote '\"\nPLUGIN_SETTINGS_EOF_not_a_delimiter\n雪"
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_PLUGIN_RECEIPTS_ASSERT: " + label);
  }
  function guard(fn) {
    try {
      fn();
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  }
  function outcome(result, status, label) {
    check(result.status === status && signals === order.length + 1, label + " status and signal-before-callback");
    order.push(label);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    if (verifyOnly) {
      Service.loadPluginSettings(key, function (value) {
        root.guard(function () {
          root.api = Service.createPluginAPI(root.key, {
                                               metadata: {}
                                             }, value, {}, {}, {});
          root.check(root.consumer === root.expected && root.api.pluginSettings.nested.keep === 1, "restarted actual API consumer");
          console.log("I4_PLUGIN_RECEIPTS: RESTART_PASS");
          Qt.exit(0);
        });
      });
      return;
    }
    guard(function () {
      api = Service.createPluginAPI(key, {
                                      metadata: {}
                                    }, {
                                      label: "first",
                                      nested: {
                                        keep: 1
                                      }
                                    }, {}, {}, {});
      var returned = false;
      api.saveSettings(function (first) {
        root.guard(function () {
          root.check(returned, "completion asynchronous");
          root.outcome(first, "saved", "first");
          // This reentrant no-op goes behind every already-queued request.
          root.api.saveSettings(function (clean) {
            root.guard(function () {
              root.outcome(clean, "nothing_to_save", "clean");
              root.check(root.order.join() === "first,invalid,second,bad,linked,clean", "FIFO including failed and reentrant work");
              Service.loadPluginSettings(root.key, function (value) {
                root.guard(function () {
                  root.check(value.label === root.expected && value.nested.keep === 1, "captured queued value reached file reader");
                  console.log("I4_PLUGIN_RECEIPTS: SAVED_PASS");
                  Qt.exit(0);
                });
              });
            });
          });
        });
      });
      returned = true;
      Service.savePluginSettings(key, null, function (invalid) {
        root.guard(function () {
          root.outcome(invalid, "failed", "invalid");
        });
      });
      var submitted = {
        label: expected,
        nested: {
          keep: 1
        }
      };
      api.pluginSettings = submitted;
      api.saveSettings(function (second) {
        root.guard(function () {
          root.outcome(second, "saved", "second");
        });
      });
      // api.saveSettings reassigns only the top record. Its child is still aliased
      // by this caller; the service must have captured the complete input already.
      submitted.nested.keep = 999;
      api.pluginSettings = {
        label: expected,
        nested: {
          keep: 1
        }
      };
      Service.savePluginSettings("i4-receipts-bad", {
                                   label: "must fail"
                                 }, function (failed) {
                                   root.guard(function () {
                                     root.outcome(failed, "failed", "bad");
                                   });
                                 });
      Service.savePluginSettings("i4-receipts-linked", {
                                   label: "link target",
                                   opaque: {
                                     keep: true
                                   }
                                 }, function (linked) {
                                   root.guard(function () {
                                     root.outcome(linked, "saved", "linked");
                                   });
                                 });
    });
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) {
      root.signals++;
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 60000
    running: true
    onTriggered: {
      console.error("I4_PLUGIN_RECEIPTS_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
