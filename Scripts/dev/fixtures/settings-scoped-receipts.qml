import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Keyboard
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string mode: Quickshell.env("SCOPED_RECEIPT_MODE")
  property int phase: 0
  property string head: ""
  property string token: ""
  property var editor: null
  property var profile: null
  property var blockedStore: null
  function check(ok, label) {
    if (!ok)
      throw new Error("SCOPED_RECEIPT_ASSERT: " + label);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function checkHead() {
    check(BindingsService.state === "Stopped" && BindingsService.headRequestId === head, "same stopped head");
    check(BindingsService.requestStatus(head).attemptId === 1, "no implicit deployment Retry");
    check(blockedStore.groupInfo(token).state === "retained" && !blockedStore.groupInfo(token).attempts.length, "same unattempted capture");
  }
  function done() {
    checkHead();
    phase = 4;
    console.log("SCOPED_RECEIPT: PASS " + mode);
    Qt.exit(0);
  }
  function publishSelected(paths, callback) {
    // Keep the rejecting control executable on the callback-only parent API.
    return typeof Settings.saveSelected === "function" ? Settings.saveSelected(paths, callback) : Settings.saveImmediate(callback);
  }
  function result(receipt) {
    try {
      console.log("SCOPED_RECEIPT_RESULT " + JSON.stringify({
                                                              mode: mode,
                                                              result: receipt,
                                                              initialValue: editor ? editor.initialValue : null
                                                            }));
      if (mode === "draft") {
        check(receipt.status === "saved" && !receipt.unresolvedGroups.length, "draft Apply has scoped success");
        check(editor.initialValue === (phase === 2 ? 1.6 : 1.8), "native draft baseline settled");
        if (phase === 2) {
          phase = 3;
          editor.apply(1.8, result);
          return;
        }
      } else if (["ordinary", "reset", "bar-command", "transfer"].indexOf(mode) !== -1) {
        check(receipt.operation === "saveSelected" && receipt.status === "saved" && !receipt.unresolvedGroups.length, "per-edit selected save acknowledged");
        const expected = mode === "transfer" ? ["bar.widgets.left", "bar.widgets.right"] : mode === "bar-command" ? ["bar.widgets.left"] : ["ui.fontDefaultScale"];
        check(JSON.stringify(receipt.coverage.map(function (entry) {
          return entry.path.join(".");
        }).sort()) === JSON.stringify(expected), "per-edit leaf coverage");
      } else
        check(receipt.status === "failed" && receipt.error.code === "unresolved-group", "root save keeps full-prefix refusal");
      done();
    } catch (error) {
      fail(error);
    }
  }
  function saveProfile() {
    if (phase !== 2)
      return;
    phase = 3;
    profile.saveProfile("blocked", function (ok, message, completed) {
      try {
        const receipt = completed.outcomes.settings;
        const owner = mode === "profile-plugin" ? "shell-profiles" : "shell";
        const key = mode === "profile-plugin" ? "plugin-held" : "bindings-reset-1";
        console.log("SCOPED_PROFILE_RESULT " + JSON.stringify({
                                                                message: message,
                                                                receipt: receipt
                                                              }));
        check(!ok && receipt.status === "failed" && receipt.error.code === "unresolved-group", "full profile save still refuses");
        check(receipt.preferenceBlockers.length === 1 && receipt.preferenceBlockers[0].ownerKey === owner, "failed owner provenance");
        check(receipt.preferenceBlockers[0].requestKey === key, "actual workflow identity");
        check(message.toLowerCase().indexOf("blocked") !== -1 && message.indexOf(owner + "/" + key) !== -1, "consumer names blocking workflow");
        check(profile._settingsFailure({
                                         error: {
                                           code: "io"
                                         }
                                       }, "ordinary-io") === "ordinary-io", "genuine IO report is not relabeled");
        done();
      } catch (error) {
        fail(error);
      }
    });
  }
  function openProfile() {
    Service._openSettingsOwner("shell-profiles", function (owner) {
      try {
        check(owner !== null, "real plugin preference owner");
        const api = Service.createPluginAPI("shell-profiles", {
                                              id: "shell-profiles",
                                              metadata: {}
                                            }, owner, {}, {}, {});
        Service.loadedPlugins["shell-profiles"] = {
          api: api
        };
        if (mode === "overlay") {
          editor = PluginInstances.createSettingsEditor("shell-profiles", {
                                                          kind: "bar",
                                                          list: "global",
                                                          section: "left",
                                                          index: 0
                                                        }, api);
          check(editor !== null, "real placement editor");
          editor.whenReady(function (opened) {
            try {
              check(opened.status === "opened", "native overlay opened");
              editor.values.icon = "scoped";
              editor.apply(editor.values, function (applied) {
                try {
                  check(applied.status === "saved" && applied.refreshState === "current", "placement Apply acknowledged");
                  check(!editor.dirty && editor.initialValue.icon === "scoped", "placement baseline settled");
                  editor.resetOverrides(function (reset) {
                    try {
                      check(reset.status === "saved" && reset.refreshState === "current", "placement Reset acknowledged");
                      check(!editor.dirty && editor.values.icon === api.pluginSettings.icon, "placement reset consumer");
                      done();
                    } catch (error) {
                      fail(error);
                    }
                  });
                } catch (error) {
                  fail(error);
                }
              });
            } catch (error) {
              fail(error);
            }
          });
          return;
        }
        function create() {
          const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
          check(component.status === Component.Ready, component.errorString());
          profile = component.createObject(root, {
                                             pluginApi: api
                                           });
          check(profile !== null, "actual profile Main");
          profile.profilesChanged.connect(saveProfile);
        }
        if (mode === "profile-plugin") {
          blockedStore = owner.store;
          owner.store.retainGroup({
                                    requestKey: "plugin-held",
                                    paths: [["settings", "icon"]],
                                    edits: [
                                      {
                                        path: ["settings", "icon"],
                                        present: true,
                                        value: "held"
                                      }
                                    ],
                                    dependencies: []
                                  }, function (retained) {
                                    try {
                                      check(retained.status === "retained", "plugin capture retained");
                                      token = retained.groupToken;
                                      create();
                                    } catch (error) {
                                      fail(error);
                                    }
                                  });
        } else
          create();
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (phase || !Settings.isLoaded)
      return;
    try {
      if (mode === "cold") {
        check(Settings.data.ui.fontDefaultScale === Number(Quickshell.env("SCOPED_RECEIPT_EXPECT")), "independent cold UI consumer");
        check(Settings.data.bindings.environment === "macos", "held bindings did not reach disk");
        const original = Quickshell.env("SCOPED_RECEIPT_COLD_CASE");
        if (original === "bar-command")
          check(Settings.data.bar.widgets.left[0].pinned[0] === "scoped", "cold actual bar field");
        if (original === "transfer")
          check(Settings.data.bar.widgets.left.length === 0 && Settings.data.bar.widgets.right[0].id === "Tray", "cold multi-leaf transfer");
        console.log("SCOPED_RECEIPT: COLD_PASS");
        Qt.exit(0);
        return;
      }
      phase = 1;
      BindingsService.init(function (environment, complete) {
        complete(false, "synthetic stopped startup, no deployment");
      });
      head = BindingsService.headRequestId;
      if (mode !== "profile-plugin") {
        // This witness tests scoped receipts against an unattempted native
        // blocker, not queue admission. A waiting reset now correctly retains
        // nothing until it reaches the FIFO head (covered by the FIFO proof).
        Settings.store.retainGroup({
                                     requestKey: "bindings-reset-1",
                                     paths: [["bindings"]],
                                     edits: [
                                       {
                                         path: ["bindings", "environment"],
                                         present: false
                                       }
                                     ],
                                     dependencies: []
                                   }, function (retained) {
                                     try {
                                       root.check(retained.status === "retained", "native unattempted blocker admitted");
                                       root.token = retained.groupToken;
                                     } catch (error) {
                                       root.fail(error);
                                     }
                                   });
        Settings.resetValue("bindings.environment");
      }
    } catch (error) {
      fail(error);
    }
  }
  function drive() {
    if (phase !== 1)
      return;
    try {
      if (mode !== "profile-plugin") {
        if (!token || BindingsService.queueCount !== 2)
          return;
        blockedStore = Settings.store;
        checkHead();
      }
      phase = 2;
      if (mode === "bar-command") {
        editor = BarService.createWidgetSettingsEditor("", "left", 0);
        check(editor !== null, "actual bar command editor");
        check(editor.submit({
                              pinned: ["scoped"]
                            }, result), "actual bar command admitted");
      } else if (mode === "transfer") {
        editor = Settings.createRecordListEditor(["bar", "widgets", "left"], [], [
                                                   {
                                                     path: ["bar", "widgets", "right"],
                                                     listAddress: []
                                                   }
                                                 ]);
        check(editor !== null, "native multi-leaf command editor");
        check(editor.submit([
                              {
                                op: "transfer",
                                from: editor.endpoint(0),
                                to: editor.endpoint(0, 1)
                              }
                            ], function (admitted) {
                              try {
                                check(admitted.status === "admitted", "native transfer admitted");
                                publishSelected([["bar", "widgets", "left"], ["bar", "widgets", "right"]], result);
                              } catch (error) {
                                fail(error);
                              }
                            }), "native transfer submitted");
      } else if (mode === "draft") {
        editor = Settings.createEditor("ui.fontDefaultScale");
        check(editor !== null, "actual selected native draft");
        editor.apply(1.6, result);
      } else if (mode === "reset")
        Settings.resetValue("ui.fontDefaultScale");
      else {
        Settings.data.ui.fontDefaultScale = 1.6;
        if (mode.indexOf("profile") === 0 || mode === "overlay")
          openProfile();
        else
          publishSelected([["ui", "fontDefaultScale"]], result);
      }
    } catch (error) {
      fail(error);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
    function onSettingsSaveCompleted(receipt) {
      if (root.phase === 2 && root.mode === "reset" && ["save", "saveSelected"].indexOf(receipt.operation) !== -1)
        root.result(receipt);
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 20
    repeat: true
    running: root.phase === 1
    onTriggered: root.drive()
  }
  Timer {
    interval: 35000
    running: true
    onTriggered: root.fail("timeout " + mode + " phase " + phase)
  }
}
