// Unit fixture: plugins.json v5 migration planner (M11). Run in a private guest
// copy by plugin-profile-migration-unit.py, which sets
// PLUGIN_PROFILE_MIGRATION_HASHES (JSON: current, old, registry hashes).
// Prints one PLUGIN_PROFILE_MIGRATION|<json> line per case, then the DONE marker.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Helpers/PluginProfileMigration.js" as PluginProfileMigration

Item {
  id: probe

  readonly property string builtinUrl: "file:///etc/xdg/quickshell/atmosphera/builtin/plugins"
  readonly property string oldBuiltinUrl: "file:///etc/xdg/quickshell/atmosphera/Plugins"
  readonly property string registryUrl: "https://github.com/alexindigo/atmosphera-plugins"
  readonly property string wallpapersUrl: "https://github.com/atmosphera/atmosphera-wallpapers"
  readonly property var shippedIds: ["noctalia-icons", "clock", "launcher"]
  readonly property var registryIds: [["pomodoro", true], ["weather", false], ["todo", true], ["calendar", true], ["notes", false], ["timer", true], ["music", true], ["wifi-menu", false], ["emoji", true], ["unit-converter", false], ["rss", true]]

  // Settings.data-shaped holder for case 8: the placement references sit in
  // list<var> properties of JsonObjects, as in Commons/Settings.qml. Filled in
  // runAll from the case 7 references.
  JsonAdapter {
    id: settingsData

    property JsonObject bar: JsonObject {
      property JsonObject widgets: JsonObject {
        property list<var> left: []
        property list<var> center: []
        property list<var> right: []
      }
      property list<var> screenOverrides: []
    }
    property JsonObject controlCenter: JsonObject {
      property JsonObject shortcuts: JsonObject {
        property list<var> left: []
        property list<var> right: []
      }
    }
    property JsonObject desktopWidgets: JsonObject {
      property list<var> monitorWidgets: []
    }
    property JsonObject general: JsonObject {
      property string lockScreenPlugin: ""
    }
  }

  function emit(name, output) {
    console.log("PLUGIN_PROFILE_MIGRATION|" + JSON.stringify({
                                                               "case": name,
                                                               "output": output
                                                             }));
  }

  function registryStates(hash) {
    var states = {};
    for (var i = 0; i < registryIds.length; i++)
      states[hash + ":" + registryIds[i][0]] = {
        "enabled": registryIds[i][1],
        "sourceUrl": registryUrl
      };
    return states;
  }

  // The user-shaped profile: four builtin: keys (one retired), eleven registry
  // keys, one unsourced key, one source.
  function userShaped(hashes) {
    var states = {};
    states["builtin:noctalia-icons"] = {
      "enabled": true,
      "sourceUrl": oldBuiltinUrl
    };
    states["builtin:clock"] = {
      "enabled": false,
      "sourceUrl": oldBuiltinUrl
    };
    states["builtin:launcher"] = {
      "enabled": true,
      "sourceUrl": oldBuiltinUrl
    };
    states["builtin:noctalia-icons-legacy"] = {
      "enabled": true,
      "sourceUrl": oldBuiltinUrl
    };
    var reg = registryStates(hashes.registry);
    for (var key in reg)
      states[key] = reg[key];
    states["digest-watcher"] = {
      "enabled": true,
      "sourceUrl": null
    };
    return {
      states: states,
      sources: [
        {
          "name": "Atmosphera Plugins",
          "url": registryUrl,
          "enabled": true
        }
      ],
      shippedIds: shippedIds,
      builtinSourceUrl: builtinUrl,
      currentHash: hashes.current,
      pluginSettingsFiles: ["builtin:clock", "builtin:clock.config", hashes.registry + ":pomodoro"]
    };
  }

  function runAll() {
    var hashes = JSON.parse(Quickshell.env("PLUGIN_PROFILE_MIGRATION_HASHES") || "{}");
    if (!hashes.current || !hashes.old || !hashes.registry) {
      console.log("PLUGIN_PROFILE_MIGRATION_ERROR|missing hashes");
      Qt.exit(3);
      return;
    }

    // 1. user-shaped
    var userInput = userShaped(hashes);
    var userOutput = PluginProfileMigration.planV5(userInput);
    emit("user-shaped", userOutput);

    // 2. pre-0.6 .../Plugins-hashed keys
    emit("pre-0.6-hashed", PluginProfileMigration.planV5({
                                                           states: {
                                                             [hashes.old + ":clock"]: {
                                                               "enabled": true,
                                                               "sourceUrl": oldBuiltinUrl
                                                             },
                                                             [hashes.old + ":retired-thing"]: {
                                                               "enabled": true,
                                                               "sourceUrl": oldBuiltinUrl
                                                             },
                                                             [hashes.registry + ":weather"]: {
                                                               "enabled": false,
                                                               "sourceUrl": registryUrl
                                                             }
                                                           },
                                                           sources: [
                                                             {
                                                               "name": "Atmosphera Plugins",
                                                               "url": registryUrl,
                                                               "enabled": true
                                                             },
                                                             {
                                                               "name": "Atmosphera Wallpapers",
                                                               "url": wallpapersUrl,
                                                               "enabled": false
                                                             }
                                                           ],
                                                           shippedIds: shippedIds,
                                                           builtinSourceUrl: builtinUrl,
                                                           currentHash: hashes.current,
                                                           pluginSettingsFiles: []
                                                         }));

    // 3. old and current keys both present
    emit("old-and-current", PluginProfileMigration.planV5({
                                                            states: {
                                                              [hashes.old + ":clock"]: {
                                                                "enabled": true,
                                                                "sourceUrl": oldBuiltinUrl
                                                              },
                                                              [hashes.current + ":clock"]: {
                                                                "enabled": false,
                                                                "sourceUrl": builtinUrl
                                                              }
                                                            },
                                                            sources: [
                                                              {
                                                                "name": "Built-in",
                                                                "url": builtinUrl,
                                                                "enabled": true
                                                              },
                                                              {
                                                                "name": "Atmosphera Plugins",
                                                                "url": registryUrl,
                                                                "enabled": true
                                                              },
                                                              {
                                                                "name": "Atmosphera Wallpapers",
                                                                "url": wallpapersUrl,
                                                                "enabled": false
                                                              }
                                                            ],
                                                            shippedIds: shippedIds,
                                                            builtinSourceUrl: builtinUrl,
                                                            currentHash: hashes.current,
                                                            pluginSettingsFiles: [hashes.old + ":clock"]
                                                          }));

    // 4. old-key settings file (with its .config override; the new .config exists, so it stays)
    emit("old-key-settings", PluginProfileMigration.planV5({
                                                             states: {
                                                               "builtin:clock": {
                                                                 "enabled": true,
                                                                 "sourceUrl": oldBuiltinUrl
                                                               }
                                                             },
                                                             sources: [
                                                               {
                                                                 "name": "Atmosphera Plugins",
                                                                 "url": registryUrl,
                                                                 "enabled": true
                                                               },
                                                               {
                                                                 "name": "Atmosphera Wallpapers",
                                                                 "url": wallpapersUrl,
                                                                 "enabled": false
                                                               }
                                                             ],
                                                             shippedIds: shippedIds,
                                                             builtinSourceUrl: builtinUrl,
                                                             currentHash: hashes.current,
                                                             pluginSettingsFiles: ["builtin:clock", "builtin:clock.config", hashes.current + ":clock.config"]
                                                           }));

    // 5. fresh seed: no change
    emit("fresh-seed", PluginProfileMigration.planV5({
                                                       states: {
                                                         [hashes.current + ":noctalia-icons"]: {
                                                           "enabled": true,
                                                           "sourceUrl": builtinUrl
                                                         },
                                                         [hashes.current + ":clock"]: {
                                                           "enabled": true,
                                                           "sourceUrl": builtinUrl
                                                         },
                                                         [hashes.current + ":launcher"]: {
                                                           "enabled": true,
                                                           "sourceUrl": builtinUrl
                                                         },
                                                         [hashes.registry + ":pomodoro"]: {
                                                           "enabled": false,
                                                           "sourceUrl": registryUrl
                                                         }
                                                       },
                                                       sources: [
                                                         {
                                                           "name": "Built-in",
                                                           "url": builtinUrl,
                                                           "enabled": true
                                                         },
                                                         {
                                                           "name": "Atmosphera Plugins",
                                                           "url": registryUrl,
                                                           "enabled": true
                                                         },
                                                         {
                                                           "name": "Atmosphera Wallpapers",
                                                           "url": wallpapersUrl,
                                                           "enabled": false
                                                         }
                                                       ],
                                                       shippedIds: shippedIds,
                                                       builtinSourceUrl: builtinUrl,
                                                       currentHash: hashes.current,
                                                       pluginSettingsFiles: []
                                                     }));

    // 6. already migrated: running the planner on its own output changes nothing
    emit("already-migrated", PluginProfileMigration.planV5({
                                                             states: userOutput.states,
                                                             sources: userOutput.sources,
                                                             shippedIds: shippedIds,
                                                             builtinSourceUrl: builtinUrl,
                                                             currentHash: hashes.current,
                                                             pluginSettingsFiles: [hashes.current + ":clock", hashes.current + ":clock.config", hashes.registry + ":pomodoro"]
                                                           }));

    // 7. settings references: rekeyed, dropped and removed keys, a registry
    // plugin and a core widget that stay, instanceSettings kept on rewrites.
    var refHashes = hashes;
    var refPlan = PluginProfileMigration.planV5({
                                                  states: {
                                                    [refHashes.current + ":noctalia-icons"]: {
                                                      "enabled": true,
                                                      "sourceUrl": builtinUrl
                                                    },
                                                    ["builtin:noctalia-icons"]: {
                                                      "enabled": true,
                                                      "sourceUrl": oldBuiltinUrl
                                                    },
                                                    ["builtin:clock"]: {
                                                      "enabled": false,
                                                      "sourceUrl": oldBuiltinUrl
                                                    },
                                                    ["builtin:launcher"]: {
                                                      "enabled": true,
                                                      "sourceUrl": oldBuiltinUrl
                                                    },
                                                    ["builtin:noctalia-icons-legacy"]: {
                                                      "enabled": true,
                                                      "sourceUrl": oldBuiltinUrl
                                                    },
                                                    [refHashes.registry + ":weather"]: {
                                                      "enabled": false,
                                                      "sourceUrl": registryUrl
                                                    }
                                                  },
                                                  sources: [
                                                    {
                                                      "name": "Atmosphera Plugins",
                                                      "url": registryUrl,
                                                      "enabled": true
                                                    }
                                                  ],
                                                  shippedIds: shippedIds,
                                                  builtinSourceUrl: builtinUrl,
                                                  currentHash: refHashes.current,
                                                  pluginSettingsFiles: []
                                                });
    var refInput = {
      barWidgets: {
        "left": [
          {
            "id": "plugin:builtin:clock",
            "instanceSettings": {
              "format": "24h",
              "tint": {
                "r": 1
              }
            },
            "size": "large"
          },
          {
            "id": "workspaces"
          }
        ],
        "center": [
          {
            "id": "plugin:builtin:launcher",
            "instanceSettings": {
              "pinned": ["a"]
            }
          }
        ],
        "right": [
          {
            "id": "plugin:builtin:noctalia-icons-legacy",
            "instanceSettings": {
              "keep": true
            }
          },
          {
            "id": "plugin:builtin:noctalia-icons",
            "instanceSettings": {
              "variant": "dark"
            },
            "order": 2
          },
          {
            "id": "plugin:" + refHashes.registry + ":weather",
            "instanceSettings": {
              "units": "c"
            }
          }
        ]
      },
      screenOverrides: [
        {
          "name": "DP-1",
          "position": "top",
          "widgets": {
            "left": [
              {
                "id": "plugin:builtin:clock",
                "instanceSettings": {
                  "format": "12h"
                }
              }
            ],
            "center": [],
            "right": [
              {
                "id": "plugin:builtin:noctalia-icons-legacy"
              }
            ]
          }
        },
        {
          "name": "HDMI-1",
          "enabled": false
        }
      ],
      controlCenterShortcuts: {
        "left": [
          {
            "id": "plugin:builtin:clock",
            "instanceSettings": {
              "face": "round"
            }
          }
        ],
        "right": [
          {
            "id": "plugin:" + refHashes.registry + ":todo",
            "instanceSettings": {
              "sort": "due"
            }
          }
        ]
      },
      monitorWidgets: [
        {
          "name": "DP-1",
          "widgets": [
            {
              "id": "plugin:builtin:clock",
              "x": 40,
              "y": 60,
              "instanceSettings": {
                "format": "24h"
              }
            },
            {
              "id": "plugin:" + refHashes.registry + ":pomodoro",
              "x": 0,
              "y": 0
            }
          ]
        },
        {
          "name": "HDMI-1",
          "widgets": []
        }
      ],
      lockScreenPlugin: "builtin:clock"
    };
    var refKeyMap = PluginProfileMigration.keyMapFor(refPlan, refHashes.current);
    var refSettings = PluginProfileMigration.rewriteSettingsReferences(refInput, refKeyMap);
    emit("settings-references", Object.assign({}, refPlan, {
                                                "settings": refSettings
                                              }));

    // 8. the same references held in list<var> properties, shaped like
    // Settings.data (Commons/Settings.qml). QML's list<var> is not a true JS
    // array (Array.isArray is false), so the helper must read it as array-like.
    settingsData.bar.widgets.left = refInput.barWidgets.left;
    settingsData.bar.widgets.center = refInput.barWidgets.center;
    settingsData.bar.widgets.right = refInput.barWidgets.right;
    settingsData.bar.screenOverrides = refInput.screenOverrides;
    settingsData.controlCenter.shortcuts.left = refInput.controlCenterShortcuts.left;
    settingsData.controlCenter.shortcuts.right = refInput.controlCenterShortcuts.right;
    settingsData.desktopWidgets.monitorWidgets = refInput.monitorWidgets;
    settingsData.general.lockScreenPlugin = refInput.lockScreenPlugin;
    var listSettings = PluginProfileMigration.rewriteSettingsReferences({
                                                                          barWidgets: {
                                                                            left: settingsData.bar.widgets.left,
                                                                            center: settingsData.bar.widgets.center,
                                                                            right: settingsData.bar.widgets.right
                                                                          },
                                                                          screenOverrides: settingsData.bar.screenOverrides,
                                                                          controlCenterShortcuts: {
                                                                            left: settingsData.controlCenter.shortcuts.left,
                                                                            right: settingsData.controlCenter.shortcuts.right
                                                                          },
                                                                          monitorWidgets: settingsData.desktopWidgets.monitorWidgets,
                                                                          lockScreenPlugin: settingsData.general.lockScreenPlugin
                                                                        }, refKeyMap);
    emit("settings-references-qml-lists", Object.assign({}, refPlan, {
                                                          "settings": listSettings
                                                        }));

    console.log("PLUGIN_PROFILE_MIGRATION_DONE");
    finish.start();
  }

  Component.onCompleted: runAll()

  Timer {
    id: finish
    interval: 100
    onTriggered: Qt.exit(0)
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(2)
  }
}
