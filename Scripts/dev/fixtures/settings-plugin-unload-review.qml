import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Plugins
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  readonly property var modelData: Quickshell.screens[0]
  SettingsBootstrap {
    id: bootstrap
  }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: root
        property bool started: false
        property var api: null
        property var originalOwner: null
        property var main: null
        property var panel: null
        property var instanceApi: null
        readonly property var slot: slotLoader.item
        property bool ownerAtUnload: false
        property bool receipt: false
        property bool unloaded: false
        property bool completed: false
        property bool held: false
        property bool failedSave: false
        property var editor: null
        property var previewSession: null
        property var popup: null
        property var popupHost: null
        property bool popupOpeningRefused: false
        property bool popupSubmitted: false
        property int discardedEditorCount: 0
        property bool editorApplied: false
        readonly property string mode: Quickshell.env("PLUGIN_UNLOAD_CASE")
        readonly property bool placement: mode === "placement" || mode === "placement-held"
        readonly property bool cold: Quickshell.env("PLUGIN_UNLOAD_COLD") === "1"
        readonly property string name: "notes-scratchpad"
        readonly property string expected: "unsaved scratchpad destruction consumer"
        readonly property var address: ({
                                          kind: "bar",
                                          list: "global",
                                          section: "left",
                                          index: 0
                                        })
        function check(ok, label) {
          if (!ok)
            throw new Error("PLUGIN_UNLOAD_ASSERT: " + label);
        }
        function fail(error) {
          console.error(String(error));
          Qt.exit(2);
        }
        function guard(callback) {
          try {
            callback();
          } catch (error) {
            fail(error);
          }
        }
        function passed() {
          console.log("PLUGIN_UNLOAD: PASS");
          Qt.exit(0);
        }
        function begin() {
          if (started || !Settings.isLoaded)
            return;
          started = true;
          Service._openSettingsOwner(name, function (owner) {
            guard(function () {
              check(owner && owner.status === "Ready", "actual native owner");
              var manifest = JSON.parse(Quickshell.env("PLUGIN_UNLOAD_MANIFEST"));
              api = Service.createPluginAPI(name, manifest, owner, {}, {}, {});
              originalOwner = owner;
              var registered = Object.assign({}, Service.loadedPlugins);
              registered[name] = {
                manifest: manifest,
                api: api
              };
              Service.loadedPlugins = registered;
              if (cold) {
                if (placement || mode.startsWith("editor-instance")) {
                  PluginInstances.openRuntime(api, address, function (result) {
                    guard(function () {
                      var value = mode === "editor-instance-discard" ? "instance initial" : mode === "editor-instance-reset" ? "original" : expected;
                      check(result.status === "opened" && result.editor.values.scratchpadContent === value, "cold placement consumer");
                      result.editor.detach();
                      console.log("PLUGIN_UNLOAD: COLD_PASS");
                      Qt.exit(0);
                    });
                  });
                } else {
                  check(api.pluginSettings.scratchpadContent === (mode === "manual-unsaved" || mode === "popup-open-refused" || mode.startsWith("editor-") && mode !== "editor-apply-held" ? "original" : expected), "cold shared consumer");
                  console.log("PLUGIN_UNLOAD: COLD_PASS");
                  Qt.exit(0);
                }
                return;
              }
              if (mode === "closed-api") {
                owner.detach();
                api.saveSettings(function (result) {
                  guard(function () {
                    check(result.status === "failed", "closed API delivers a failed receipt");
                    passed();
                  });
                });
                return;
              }
              if (mode.startsWith("popup-")) {
                if (mode === "popup-open-refused") {
                  popupHost = popupHostFactory.createObject(root);
                  popup = popupFactory.createObject(popupHost.contentItem, {
                                                      screen: Quickshell.screens[0]
                                                    });
                  check(popupHost.showDialog(popup), "actual pending host adopted");
                  instanceApi = PluginInstances.apiFor(name, address);
                  popup.settingsCompleted.connect(function (result) {
                    root.popupOpeningRefused = result.status === "failed";
                  });
                  check(popup.openInstanceSettings(manifest, instanceApi), "invalid placement editor open queued");
                } else {
                  popup = popupFactory.createObject(popupWindow.contentItem, {
                                                      screen: Quickshell.screens[0]
                                                    });
                  check(popup.openPluginSettings(manifest), "actual popup open requested");
                }
                popupCheck.start();
                return;
              }
              if (mode.startsWith("editor-")) {
                editorCase();
                return;
              }
              Service.pluginContainer = root;
              var installed = Object.assign({}, Registry.installedPlugins);
              installed[name] = manifest;
              Registry.installedPlugins = installed;
              var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
              check(component.status === Component.Ready, component.errorString());
              main = PluginLoader.createObject(name, "main", component, root, api, {});
              check(main !== null, "actual notes Main");
              api.mainInstance = main;
              var loaded = Object.assign({}, Service.loadedPlugins);
              loaded[name] = {
                manifest: manifest,
                api: api,
                mainInstance: main
              };
              Service.loadedPlugins = loaded;
              if (mode === "manual-unsaved") {
                api.pluginSettings.scratchpadContent = "unrequested manual edit";
                retire();
                return;
              }
              if (placement) {
                Settings.data.bar.widgets.left = [
                      {
                        id: "plugin:" + name
                      }
                    ];
                Settings.saveResult(function (saved) {
                  guard(function () {
                    check(saved.status !== "failed", "placement baseline");
                    instanceApi = PluginInstances.apiFor(name, address);
                    function ready() {
                      if (!instanceApi.settingsReady)
                        return;
                      instanceApi.settingsReadyChanged.disconnect(ready);
                      Qt.callLater(function () {
                        root.guard(function () {
                          root.createPanel(root.instanceApi);
                        });
                      });
                    }
                    instanceApi.settingsReadyChanged.connect(ready);
                    ready();
                  });
                });
              } else
                createPanel(api);
            });
          });
        }
        function createPanel(selectedApi) {
          if (placement)
            selectedApi.runtime.completed.connect(function (result) {
              if (["saved", "nothing_to_save"].indexOf(result.status) !== -1)
                root.receipt = true;
            });
          var component = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
          check(component.status === Component.Ready, component.errorString());
          if (mode === "panel-slot") {
            slot.currentPluginId = name;
            slot.currentPluginApi = api;
            slot.contentLoader = panelLoader;
            slot.finalizePluginLoad(name, component, api);
            panel = slot.pluginInstance;
          } else {
            panel = PluginLoader.createObject(name, "panel", component, mode === "destruction" || mode === "reload-held" || mode === "failed-save" ? main : root, selectedApi, {
                                                screen: Quickshell.screens[0]
                                              });
          }
          check(panel !== null, "actual scratchpad Panel");
          Qt.callLater(function () {
            guard(function () {
              panel.textContent = expected;
              retire();
            });
          });
        }
        Component {
          id: popupFactory
          NPluginSettingsPopup {}
        }
        Component {
          id: popupHostFactory
          PopupMenuWindow {
            shellScreen: Quickshell.screens[0]
          }
        }
        PanelWindow {
          id: popupWindow
          visible: root.mode.startsWith("popup-")
          implicitWidth: 800
          implicitHeight: 600
        }
        Timer {
          id: popupCheck
          interval: 50
          repeat: true
          onTriggered: root.guard(function () {
            if (root.mode === "popup-open-refused") {
              if (!root.popupOpeningRefused)
                return;
              root.check(!root.popup.visible && !root.popupHost.visible && root.popupHost.popupContentItem === null, "refused unopened editor releases actual transparent host");
              root.passed();
              return;
            }
            if (!root.popupSubmitted) {
              if (!root.popup || !root.popup.visible || !root.popup.settingsPage)
                return;
              root.popupSubmitted = true;
              root.popup.applySettings();
              root.check(root.popup.busy, "actual popup Apply is busy");
              if (root.mode === "popup-close-held")
                root.popup.close();
              else
                root.popup.destroy();
              Service.unloadPlugin(root.name, true, function (result) {
                root.guard(function () {
                  root.check(root.held, "popup release cannot complete retirement before held write");
                  root.check(result.status !== "failed", "released popup editor lets retirement settle");
                  root.check((Service._pluginEntries[root.name] || []).length === 0, "no retained popup consumer");
                  persisted.reload();
                  persisted.waitForJob();
                  root.check(JSON.parse(persisted.text()).scratchpadContent === root.expected, "popup Apply persisted before retirement");
                  root.passed();
                });
              });
              return;
            }
            root.check(!root.completed && root.api.pluginSettings !== null, "native hold retains preference owner");
            root.held = true;
            console.log("PLUGIN_UNLOAD: HELD_PASS");
            stop();
          })
        }
        function editorCase() {
          if (mode === "editor-preview-lifetime") {
            editor = api.createSettingsEditor();
            check(editor && editor.ready, "actual preview draft");
            previewSession = api.createSettingsPreview(editor);
            check(previewSession && previewSession.update({
                                                            scratchpadContent: expected
                                                          }), "actual provided-editor preview");
            check(editor.discard(), "provided editor explicitly discarded first");
            editorCheck.start();
            return;
          }
          if (mode.startsWith("editor-instance")) {
            Settings.data.bar.widgets.left = [
                  {
                    id: "plugin:" + name,
                    instanceSettings: {
                      scratchpadContent: "instance initial"
                    }
                  }
                ];
            Settings.saveResult(function (result) {
              guard(function () {
                check(result.status !== "failed", "instance editor baseline");
                instanceApi = PluginInstances.apiFor(name, address);
                function ready() {
                  if (!instanceApi.settingsReady)
                    return;
                  instanceApi.settingsReadyChanged.disconnect(ready);
                  Qt.callLater(function () {
                    root.guard(root.instanceEditorCase);
                  });
                }
                instanceApi.settingsReadyChanged.connect(ready);
                ready();
              });
            });
            return;
          }
          if (mode === "editor-discard") {
            for (var i = 0; i < 8; ++i) {
              var discarded = api.createSettingsEditor();
              check(discarded && discarded.ready, "actual shared draft " + i);
              discarded.Component.destruction.connect(function () {
                root.discardedEditorCount++;
              });
              check(discarded.discard(), "discard accepted " + i);
            }
            editorCheck.start();
            return;
          }
          editor = api.createSettingsEditor();
          check(editor && editor.ready, "actual retained shared draft");
          editor.values.scratchpadContent = expected;
          if (mode === "editor-apply-held")
            editor.apply(editor.values, function (result) {
              guard(function () {
                check(result.status === "saved", "actual editor publication");
                editorApplied = true;
                check(editor.discard(), "settled editor closes");
              });
            });
          Service.unloadPlugin(name, true, function (result) {
            guard(function () {
              check(held, "editor lifetime prevents early unload completion");
              check(editor === null, "closed editor QObject destroyed before preference owner");
              check(result.status !== "failed" && (mode !== "editor-apply-held" || editorApplied), "editor publication settles before retirement");
              persisted.reload();
              persisted.waitForJob();
              check(JSON.parse(persisted.text()).scratchpadContent === (mode === "editor-unload" ? "original" : expected), "editor disk contract");
              completed = true;
              passed();
            });
          });
          editorCheck.start();
        }
        function instanceEditorCase() {
          if (mode === "editor-instance-reset") {
            editor = instanceApi.resetSettings(function (result) {
              guard(function () {
                check(result.status !== "failed" && result.refreshState === "current", "one-shot actual instance Reset");
                editorApplied = true;
                editorCheck.start();
              });
            });
          } else {
            editor = instanceApi.createSettingsEditor();
            editor.whenReady(function (result) {
              guard(function () {
                check(result.status === "opened", "actual instance editor opened");
                editor.values.scratchpadContent = expected;
                check(editor.discard(), "instance editor explicit discard");
                editorCheck.start();
              });
            });
          }
          check(editor !== null && editor !== false, "instance editor returned");
          editor.Component.destruction.connect(function () {
            root.discardedEditorCount++;
          });
        }
        function retire() {
          if (mode === "placement-held") {
            enableFile.setText("1");
            enableFile.waitForJob();
          }
          if (mode === "reload-held")
            check(Service.reloadPlugin(name), "reload accepted");
          else
            Service.unloadPlugin(name, true, function (result) {
              guard(function () {
                check(ownerAtUnload, "unload observers retain preferences");
                if (mode === "failed-save" && result.status === "failed") {
                  failedSave = true;
                  check(!api.settingsOwner.closed && Service._settingsOwners[name] === api.settingsOwner, "failed work retained without recreation");
                  api.saveSettings(function (saved) {
                    guard(function () {
                      check(saved.status !== "failed", "explicit same-owner Retry");
                      Service.unloadPlugin(name, true, finish);
                    });
                  });
                  return;
                }
                finish(result);
              });
            });
          if (placement)
            lateDestruction.start();
          if (mode === "reload-held")
            heldCheck.start();
        }
        function finish(result) {
          guard(function () {
            check(result.status !== "failed", "publication settled before unload completion");
            check(mode !== "failed-save" || failedSave, "actual failed publication preceded explicit Retry");
            check(receipt === (mode !== "manual-unsaved"), "requested publication receipt");
            check(api.settingsOwner === null || api.settingsOwner.closed, "owner retired after last consumer");
            if (placement)
              check(instanceApi === null, "placement API destroyed last");
            if (mode === "panel-slot")
              check(slot.currentPluginId === "" && panelLoader.item === null, "independent panel-slot content retired");
            persisted.reload();
            persisted.waitForJob();
            check(JSON.parse(persisted.text()).scratchpadContent === (placement || mode === "manual-unsaved" ? "original" : expected), "shared disk publication");
            completed = true;
            passed();
          });
        }
        Connections {
          target: Service
          function onPluginUnloaded(pluginId) {
            if (pluginId !== root.name)
              return;
            root.ownerAtUnload = root.api.pluginSettings !== null;
            root.unloaded = true;
          }
          function onPluginSettingsCompleted(pluginId, result) {
            if (pluginId === root.name && ["saved", "nothing_to_save"].indexOf(result.status) !== -1)
              root.receipt = true;
          }
          function onPluginLoaded(pluginId) {
            if (pluginId === root.name && root.mode === "reload-held")
              root.guard(function () {
                root.check(root.held, "no replacement owner before held native publication");
                root.check(!root.originalOwner || root.originalOwner.closed, "original preference owner retired");
                root.check(Service.getPluginAPI(pluginId).settingsOwner !== root.originalOwner, "replacement uses a different native owner");
                root.check(Service.getPluginAPI(pluginId).pluginSettings.scratchpadContent === root.expected, "replacement owner reads final destruction save");
                root.completed = true;
                root.passed();
              });
          }
        }
        Timer {
          id: editorCheck
          interval: 150
          onTriggered: root.guard(function () {
            if (root.mode === "editor-preview-lifetime") {
              root.check(root.editor === null, "provided preview editor destroyed first");
              root.check(!root.previewSession.update({
                                                       scratchpadContent: "obsolete"
                                                     }) && root.previewSession.close(), "late preview closure safely releases its subscription");
              root.check(root.api.pluginSettings.scratchpadContent === "original", "preview never published");
              root.passed();
              return;
            }
            if (root.mode.startsWith("editor-instance")) {
              root.check(root.discardedEditorCount === 1 && root.editor === null, "one-shot and discarded instance editor QObjects destroyed");
              var row = Settings.data.bar.widgets.left[0];
              if (root.mode === "editor-instance-reset")
                root.check(root.editorApplied && row.instanceSettings === undefined, "Reset published override removal");
              else
                root.check(row.instanceSettings.scratchpadContent === "instance initial", "discard retained original placement");
              root.passed();
              return;
            }
            if (root.mode === "editor-discard") {
              root.check(root.discardedEditorCount === 8, "discarded QObjects are destroyed");
              root.passed();
              return;
            }
            root.check(!root.completed && root.editor && root.editor.ready && root.editor.values.scratchpadContent === root.expected && root.api.pluginSettings !== null, "unload preserves the live editor and unsaved input");
            root.held = true;
            if (root.mode === "editor-unload")
              root.editor.apply(root.editor.values, function (result) {
                root.guard(function () {
                  root.check(result.status === "failed" && root.editor.dirty && root.editor.values.scratchpadContent === root.expected, "unloaded editor refuses new Apply without losing input");
                  root.check(root.editor.discard(), "explicit unsaved-editor discard");
                });
              });
            else
              console.log("PLUGIN_UNLOAD: HELD_PASS");
          })
        }
        Timer {
          id: lateDestruction
          interval: 150
          onTriggered: root.guard(function () {
            root.check(root.unloaded && !root.completed && root.api.pluginSettings !== null && root.instanceApi.settingsReady, "independent placement lifetime retained");
            root.panel.destroy();
            if (root.mode === "placement-held")
              heldCheck.start();
          })
        }
        Timer {
          id: heldCheck
          interval: 150
          onTriggered: root.guard(function () {
            root.check(root.unloaded && !root.completed && root.api.pluginSettings !== null && !Service.isPluginLoaded(root.name), "pending real publication owns retirement");
            root.held = true;
            console.log("PLUGIN_UNLOAD: HELD_PASS");
          })
        }
        Loader {
          id: panelLoader
          active: false
        }
        Loader {
          id: slotLoader
          active: Settings.isLoaded
          sourceComponent: PluginPanelSlot {
            screen: Quickshell.screens[0]
            visible: false
          }
        }
        FileView {
          id: persisted
          path: Settings.configDir + "settings/plugins/notes-scratchpad.json"
          printErrors: false
        }
        FileView {
          id: enableFile
          path: Quickshell.env("PLUGIN_UNLOAD_ENABLE")
          printErrors: false
        }
        Connections {
          target: Settings
          function onSettingsLoaded() {
            root.begin();
          }
        }
        Component.onCompleted: Qt.callLater(begin)
        Timer {
          interval: 25000
          running: true
          onTriggered: root.fail("unload deadline " + root.mode)
        }
      }
    }
  }
}
