import QtQuick
import Quickshell
import "../../../Helpers/OwnedProcess.js" as OwnedProcess
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  readonly property string mode: Quickshell.env("OWNER_REVIEW_MODE")
  function check(ok, label) {
    if (!ok)
      throw new Error("OWNER_REVIEW_ASSERT: " + label);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function done() {
    console.log("OWNER_REVIEW: PASS " + mode);
    Qt.exit(0);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    Service._openSettingsOwner("owner-review", function (owner) {
      try {
        check(owner === null, "invalid authored descriptor refused");
        if (root.mode === "profile") {
          function synchronize(operation) {
            Service.synchronizePreferences(operation, function (result) {
              try {
                check(result.status === "current", "failed plugin does not poison unrelated profile " + operation + ": " + JSON.stringify(result));
                if (operation === "save")
                  synchronize("reload");
                else
                  root.done();
              } catch (error) {
                root.fail(error);
              }
            });
          }
          synchronize("save");
        } else if (root.mode === "retry" || root.mode === "config") {
          OwnedProcess.run(root, ["cp", Quickshell.env("OWNER_REVIEW_VALID"), Quickshell.env("OWNER_REVIEW_MANIFEST")], null, function (result) {
            try {
              check(result.success, "repair fixture manifest");
              Service._openSettingsOwner("owner-review", function (reloaded) {
                try {
                  check(reloaded !== null && reloaded.status === "Ready", "new load constructs a fresh owner after failure");
                  check(reloaded.settingsScope.values.label === "ready", "real reloaded settings consumer");
                  if (root.mode === "config") {
                    var api = Service.createPluginAPI("owner-review", {
                                                        id: "owner-review"
                                                      }, reloaded, {}, {}, {});
                    reloaded.detach();
                    api.getConfig(function (value) {
                      try {
                        check(value === null, "closed owner completes config callback with null");
                        api.settingsOwner = null;
                        api.getConfig(function (detached) {
                          try {
                            check(detached === null, "absent owner completes config callback with null");
                            root.done();
                          } catch (error) {
                            root.fail(error);
                          }
                        });
                      } catch (error) {
                        root.fail(error);
                      }
                    });
                  } else
                    root.done();
                } catch (error) {
                  root.fail(error);
                }
              });
            } catch (error) {
              root.fail(error);
            }
          });
        } else {
          check(!Service._settingsOwners["owner-review"], "failed owner removed from live map");
          root.done();
        }
      } catch (error) {
        root.fail(error);
      }
    });
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 30000
    running: true
    onTriggered: root.fail("owner review timeout " + root.mode)
  }
}
