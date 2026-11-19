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
        readonly property string name: "notes-scratchpad"
        readonly property string mode: Quickshell.env("PLUGIN_LOAD_CASE")
        property bool started: false
        property bool cancelled: false
        property int completions: 0
        property int startupCompletions: 0
        property int loadedSignals: 0
        property var originalOwner: null
        function check(ok, label) {
          if (!ok)
            throw new Error("PLUGIN_LOAD_ASSERT: " + label);
        }
        function guard(action) {
          try {
            action();
          } catch (error) {
            console.error(String(error));
            Qt.exit(2);
          }
        }
        function complete(result) {
          guard(function () {
            completions++;
            if ((mode === "opening" || mode === "state" || mode === "state-replace" || mode === "icons" || mode === "self-unload") && completions === 1) {
              check(cancelled && result.status === "failed" && result.error.code === "plugin-load-cancelled", "cancelled load owns failed completion");
            } else if (mode === "failure" || mode === "icons-failure" || mode === "missing") {
              check(result.status === "failed", "owner/component refusal owns failed load completion");
              if (mode === "failure")
                check(!Service.isPluginLoaded(name), "failed owner never registers");
            } else {
              check(result.status === "loaded" && Service.isPluginLoaded(name), "completion observes registered load");
              check(Service.getPluginAPI(name).settingsOwner.status === "Ready", "completion observes ready native owner");
            }
            finish.start();
          });
        }
        function begin() {
          if (started || !Settings.isLoaded)
            return;
          started = true;
          Service.initialized = true;
          Service.pluginContainer = root;
          var installed = Object.assign({}, Registry.installedPlugins);
          if (mode === "missing")
            delete installed[name];
          else
            installed[name] = JSON.parse(Quickshell.env("PLUGIN_LOAD_MANIFEST"));
          Registry.installedPlugins = installed;
          if (mode === "self-unload")
            cancelled = true;
          if (mode === "opening" || mode.startsWith("state") || mode === "icons")
            Service._pendingPluginLoads = 1;
          Service.loadPlugin(name, null, complete, mode === "opening" || mode.startsWith("state") || mode === "icons");
          originalOwner = Service._settingsOwners[name];
          if (mode === "coalesce")
            Service.loadPlugin(name, null, complete);
          if (mode === "opening") {
            check(originalOwner && originalOwner.status === "Loading", "cancel actual opening native owner");
            cancel();
          }
        }
        function cancel() {
          cancelled = true;
          Service.unloadPlugin(name, true, function (result) {
            guard(function () {
              check(result.status !== "failed", "cancelled owner retirement completes");
            });
          });
          if (mode === "state-replace")
            Service.loadPlugin(name, null, complete);
          if (mode.startsWith("state") || mode === "icons") {
            release.setText("release");
            release.waitForJob();
          }
          finish.start();
        }
        FileView {
          id: marker
          path: Quickshell.env("PLUGIN_LOAD_MARKER")
          printErrors: false
        }
        FileView {
          id: release
          path: Quickshell.env("PLUGIN_LOAD_RELEASE")
          printErrors: false
        }
        Timer {
          interval: 30
          repeat: true
          running: (root.mode.startsWith("state") || root.mode === "icons") && root.started && !root.cancelled
          onTriggered: root.guard(function () {
            marker.reload();
            marker.waitForJob();
            if (marker.text().trim() !== "held")
              return;
            root.check(root.originalOwner && root.originalOwner.status === "Ready", "cancel after owner opens and state reader starts");
            root.cancel();
          })
        }
        Timer {
          id: finish
          interval: 700
          onTriggered: root.guard(function () {
            root.check(Service._pendingPluginLoads === 0, "startup accounting settles once, runtime loads never decrement it");
            if (root.cancelled) {
              if (root.mode === "state-replace") {
                root.check(Service.isPluginLoaded(root.name) && root.loadedSignals === 1, "only replacement generation registers");
                root.check(Service.getPluginAPI(root.name).settingsOwner !== root.originalOwner, "replacement owns a different ready native owner");
              } else {
                root.check(!Service.isPluginLoaded(root.name) && root.loadedSignals === 0, "late read cannot register cancelled plugin");
                root.check(!Service._settingsOwners[root.name], "cancelled native owner retired");
                root.check(!IconRegistry.iconSets[root.name], "late data-only read cannot register retired plugin");
              }
              root.check(root.startupCompletions === (root.mode === "self-unload" ? 0 : 1), "cancelled startup completes once, runtime cancellation is not startup");
            }
            root.check(root.completions === (root.mode === "coalesce" || root.mode === "state-replace" ? 2 : 1), "each accepted request settles exactly once");
            console.log("PLUGIN_LOAD: PASS " + root.mode);
            Qt.exit(0);
          })
        }
        Connections {
          target: Service
          function onAllPluginsLoaded() {
            root.startupCompletions++;
          }
          function onPluginLoaded(pluginId) {
            if (pluginId === root.name)
              root.loadedSignals++;
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
          interval: 15000
          running: true
          onTriggered: root.guard(function () {
            throw new Error("PLUGIN_LOAD_ASSERT: deadline");
          })
        }
      }
    }
  }
}
