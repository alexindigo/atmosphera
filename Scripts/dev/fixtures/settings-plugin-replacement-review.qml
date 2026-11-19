import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  SettingsBootstrap {
    id: bootstrap
  }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: root
        readonly property string mode: Quickshell.env("PLUGIN_REPLACEMENT_CASE")
        readonly property string key: Quickshell.env("PLUGIN_REPLACEMENT_KEY")
        readonly property bool update: mode.startsWith("update-")
        readonly property bool uninstall: mode.startsWith("uninstall-")
        readonly property bool disabled: mode === "update-disabled"
        readonly property bool retry: mode.endsWith("-retry")
        readonly property bool held: mode.endsWith("-held-load")
        readonly property bool loadFailure: mode.endsWith("-load-failure")
        readonly property string expected: retry ? "latest requested-key intent" : "replacement native consumer"
        property bool started: false
        property bool heldProven: false
        property var api: null
        property var originalOwner: null
        property int requests: 0
        property int completions: 0
        property int reloaded: 0
        property var retryAction: null
        function check(ok, label) {
          if (!ok)
            throw new Error("PLUGIN_REPLACEMENT_ASSERT: " + label);
        }
        function guard(action) {
          try {
            action();
          } catch (error) {
            console.error(String(error));
            Qt.exit(2);
          }
        }
        function begin() {
          if (started || !Settings.isLoaded)
            return;
          started = true;
          Service.initialized = true;
          Service.pluginContainer = root;
          var manifest = JSON.parse(Quickshell.env("PLUGIN_REPLACEMENT_MANIFEST"));
          var installed = Object.assign({}, Registry.installedPlugins);
          installed[key] = manifest;
          Registry.installedPlugins = installed;
          var states = Object.assign({}, Registry.pluginStates);
          states[key] = {
            enabled: !disabled,
            sourceUrl: Quickshell.env("PLUGIN_REPLACEMENT_SOURCE")
          };
          Registry.pluginStates = states;
          Service.availablePlugins = [Object.assign({}, manifest, {
                                                      source: {
                                                        url: Quickshell.env("PLUGIN_REPLACEMENT_SOURCE"),
                                                        name: "review"
                                                      }
                                                    })];
          var updates = {};
          updates[key] = {
            currentVersion: "old",
            availableVersion: "new"
          };
          Service.pluginUpdates = updates;
          Service._openSettingsOwner(key, function (owner) {
            root.guard(function () {
              check(owner && owner.status === "Ready", "actual initial native owner");
              originalOwner = owner;
              api = Service.createPluginAPI(key, manifest, owner, {}, {}, {});
              var loaded = Object.assign({}, Service.loadedPlugins);
              if (!disabled)
                loaded[key] = {
                  manifest: manifest,
                  api: api
                };
              Service.loadedPlugins = loaded;
              if (loadFailure && !update) {
                var bad = Object.assign({}, manifest, {
                                          entryPoints: {
                                            main: "MissingReplacement.qml"
                                          }
                                        });
                var current = Object.assign({}, Registry.installedPlugins);
                current[key] = bad;
                Registry.installedPlugins = current;
              }
              if (loadFailure) {
                invoke();
                return;
              }
              api.pluginSettings.scratchpadContent = "replacement native consumer";
              api.saveSettings(function (result) {
                root.guard(function () {
                  check((result.status === "failed") === retry, "controlled initial requested publication result");
                  invoke();
                });
              });
            });
          });
        }
        function invoke() {
          requests++;
          if (uninstall)
            Service.uninstallPlugin(key, function (ok, error) {
              root.received({
                              status: ok ? "uninstalled" : "failed",
                              error: error
                            });
            });
          else if (update)
            Service.updatePlugin(key, function (ok, error) {
              root.received({
                              status: ok ? "updated" : "failed",
                              error: error
                            });
            });
          else
            check(Service.reloadPlugin(key, received), "same-owner reload/Retry accepted");
        }
        function received(result) {
          guard(function () {
            completions++;
            if (retry && completions === 1) {
              check(result.status === "failed", "failed retirement cannot report replacement success");
              check(Service._settingsOwners[key] === originalOwner && !originalOwner.closed, "failed retirement retains same native owner");
              check(!Service.isPluginLoaded(key) && reloaded === 0, "failed retirement has no loaded replacement or reload success signal");
              if (update || uninstall) {
                revision.reload();
                revision.waitForJob();
                check(revision.text().trim() === "old", "retirement failure cannot replace installed files");
                if (update)
                  check(Service.pluginUpdates[key] !== undefined, "failed update retains notice");
              }
              api.pluginSettings.fontSize = 99;
              api.pluginSettings.scratchpadContent = expected;
              if (uninstall)
                Qt.callLater(function () {
                  root.guard(root.invoke);
                });
              else {
                check(typeof retryAction === "function", "failure exposes a user-facing toast Retry action");
                requests++;
                Qt.callLater(function () {
                  root.guard(function () {
                    root.retryAction();
                    toastRetryCheck.start();
                  });
                });
              }
              return;
            }
            if (disabled) {
              check(result.status === "updated" && !Registry.isPluginEnabled(key) && !Service.isPluginLoaded(key), "updating a disabled plugin cannot enable or load it");
              check(Service.pluginUpdates[key] === undefined, "completed disabled install clears update notice");
              revision.reload();
              revision.waitForJob();
              check(revision.text().trim() === "new", "disabled plugin update replaced files after retirement");
            } else if (uninstall) {
              check(result.status === "uninstalled" && !Service.isPluginLoaded(key) && !Service._settingsOwners[key], "uninstall waits for retirement and requested publication");
              preferences.reload();
              preferences.waitForJob();
              var removedRaw = JSON.parse(preferences.text());
              check(removedRaw.scratchpadContent === expected && removedRaw.fontSize === undefined && removedRaw.opaque.keep === true, "uninstall Retry publishes only failed requested keys before removal");
            } else if (loadFailure) {
              check(result.status === "failed" && reloaded === 0, "replacement load failure owns failed completion without success signal");
              if (update)
                check(Service.pluginUpdates[key] !== undefined, "failed replacement load retains update notice");
            } else {
              check(result.status !== "failed", "replacement succeeds only after load");
              check(!held || heldProven, "completion waits for held actual state reader");
              var replacement = Service.getPluginAPI(key);
              check(replacement && replacement.settingsReady && replacement.settingsOwner !== originalOwner, "new ready native owner owns success");
              check(!originalOwner || originalOwner.closed, "old owner retired before replacement success");
              check(replacement.pluginSettings.scratchpadContent === expected, "replacement consumer reads requested-key publication");
              preferences.reload();
              preferences.waitForJob();
              var raw = JSON.parse(preferences.text());
              check(raw.scratchpadContent === expected && raw.opaque.keep === true, "persisted request and opaque field retained");
              if (retry)
                check(raw.fontSize === undefined, "Retry never flushes unrelated pending plugin key");
              if (update) {
                revision.reload();
                revision.waitForJob();
                check(revision.text().trim() === "new" && Service.pluginUpdates[key] === undefined, "successful loaded update replaces files then clears notice");
              } else
                check(reloaded === 1, "one reload success signal after ready replacement");
            }
            check(completions === requests, "every workflow request receives one completion");
            if (retry && !uninstall) {
              var currentApi = Service.getPluginAPI(key);
              retryAction();
              check(!Service._pluginReplacements[key] && Service.getPluginAPI(key) === currentApi, "stale toast Retry cannot start another replacement");
            }
            console.log("PLUGIN_REPLACEMENT: PASS " + mode);
            Qt.exit(0);
          });
        }
        FileView {
          id: revision
          path: Quickshell.env("PLUGIN_REPLACEMENT_REVISION")
          printErrors: false
        }
        FileView {
          id: preferences
          path: Quickshell.env("PLUGIN_REPLACEMENT_PREFERENCES")
          printErrors: false
        }
        FileView {
          id: marker
          path: Quickshell.env("PLUGIN_REPLACEMENT_MARKER")
          printErrors: false
        }
        FileView {
          id: release
          path: Quickshell.env("PLUGIN_REPLACEMENT_RELEASE")
          printErrors: false
        }
        Timer {
          id: toastRetryCheck
          interval: 30
          repeat: true
          onTriggered: root.guard(function () {
            if (Service._pluginReplacements[root.key] || !Service.isPluginLoaded(root.key))
              return;
            stop();
            root.received({
                            status: root.update ? "updated" : "reloaded"
                          });
          })
        }
        Timer {
          interval: 30
          running: root.held && root.started && !root.heldProven
          repeat: true
          onTriggered: root.guard(function () {
            marker.reload();
            marker.waitForJob();
            if (marker.text().trim() !== "held")
              return;
            root.check(root.completions === 0 && root.reloaded === 0, "pending replacement load cannot complete or toast success");
            if (root.update)
              root.check(Service.pluginUpdates[root.key] !== undefined, "update notice remains through pending replacement load");
            root.heldProven = true;
            release.setText("release");
            release.waitForJob();
          })
        }
        Connections {
          target: Service
          function onPluginReloaded(pluginId) {
            if (pluginId === root.key)
              root.guard(function () {
                root.reloaded++;
                var current = Service.getPluginAPI(root.key);
                root.check(current && current.settingsReady, "reload signal observes loaded ready replacement");
              });
          }
        }
        Connections {
          target: ToastService
          function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
            if (type === "error" && actionLabel === I18n.tr("common.retry"))
              root.retryAction = actionCallback;
          }
        }
        Connections {
          target: Settings
          function onSettingsLoaded() {
            root.guard(root.begin);
          }
        }
        Component.onCompleted: Qt.callLater(function () {
          root.guard(root.begin);
        })
        Timer {
          interval: 22000
          running: true
          onTriggered: root.guard(function () {
            throw new Error("PLUGIN_REPLACEMENT_ASSERT: deadline");
          })
        }
      }
    }
  }
}
