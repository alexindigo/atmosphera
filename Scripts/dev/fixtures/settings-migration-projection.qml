// Inert migration parity and real worker/file/restart witness. No shell effects
// are executed: their ordered descriptors are observed independently of saves.
import ConfigQml 1.0
import QtQuick
import Quickshell
import "../../../Commons/Migrations/SettingsMigrationSource.js" as MigrationSource
import qs.Commons as Main

ShellRoot {
  id: root
  readonly property var spec: JSON.parse(Quickshell.env("I5_MIGRATION_SPEC"))
  property var store: null
  readonly property var cfg: store ? store.values : null
  readonly property real scaleConsumer: store && store.ready ? cfg.general.scaleRatio : 0
  property var observedEffects: []
  property bool started: false

  function check(ok, label) {
    if (!ok)
      throw new Error("I5_MIGRATION_ASSERT: " + label);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function copy(value) {
    return JSON.parse(JSON.stringify(value));
  }
  function merge(target, source) {
    Object.keys(source).forEach(function (key) {
      var value = source[key];
      if (value !== null && typeof value === "object" && !Array.isArray(value) && target[key] !== null && typeof target[key] === "object" && !Array.isArray(target[key]))
        merge(target[key], value);
      else
        Object.defineProperty(target, key, {
                                value: copy(value),
                                enumerable: true,
                                writable: true,
                                configurable: true
                              });
    });
    return target;
  }
  function canonical(value) {
    if (Array.isArray(value) || (value !== null && typeof value === "object" && typeof value.length === "number"))
      return "[" + Array.from(value).map(canonical).join(",") + "]";
    if (value !== null && typeof value === "object")
      return "{" + Object.keys(value).sort().map(function (key) {
        return JSON.stringify(key) + ":" + canonical(value[key]);
      }).join(",") + "}";
    return JSON.stringify(value);
  }
  function parity() {
    // eval is test-only. Production passes the standalone source string to
    // ConfigProjection, whose fresh worker engine supplies identity-tagged atoms.
    var transform = eval("(" + MigrationSource.transform + ")");
    var versions = [27, 28, 32, 33, 35, 36, 37, 38, 40, 42, 43, 44, 45, 46, 47, 48, 49, 50, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62];
    var effects = {
      36: "clear-emoji-usage",
      44: "create-legacy-pam",
      46: "remove-legacy-pam",
      47: "clear-network-stats",
      49: "clear-launcher-usage",
      56: "migrate-color-schemes"
    };
    var components = {};
    versions.forEach(function (version) {
      if (effects[version])
        return;
      var component = Qt.createComponent("./Commons/Migrations/Migration" + version + ".qml");
      check(component.status === Component.Ready, "historical oracle component " + version + ": " + component.errorString());
      components[version] = component.createObject(root);
    });
    var logger = {
      i: function () {},
      d: function () {},
      w: function () {},
      e: function () {}
    };
    spec.cases.forEach(function (test) {
      var original = copy(test.raw);
      var raw = copy(original);
      var adapter = merge(copy(spec.defaults), raw);
      var expectedEffects = [];
      versions.forEach(function (version) {
        if ((original.settingsVersion || 0) >= version)
          return;
        if (effects[version])
          expectedEffects.push({
                                 effectId: "settings-migration-" + version,
                                 version: version,
                                 action: effects[version],
                                 arguments: {}
                               });
        else
          check(components[version].migrate(adapter, logger, raw), test.id + " oracle " + version);
      });
      adapter.settingsVersion = 62;
      var input = {
        raw: copy(original),
        source: {
          presence: "present"
        },
        defaults: copy(spec.defaults),
        lowerValues: copy(spec.defaults),
        values: merge(copy(spec.defaults), original),
        compatibilityRaw: copy(original),
        metadata: {}
      };
      var result = transform(input);
      var effective = merge(copy(spec.defaults), result.values);
      check(canonical(effective) === canonical(adapter), test.id + " historical effective parity\nactual=" + canonical(effective) + "\nexpected=" + canonical(adapter));
      check(canonical(result.compatibilityRaw) === canonical(raw), test.id + " raw-only parity");
      check(canonical(result.effects) === canonical(expectedEffects), test.id + " six ordered effects and version gaps");
      check(result.diagnostics.length === 0, test.id + " diagnostics");
      console.log("I5_MIGRATION_PARITY: " + test.id);
    });
    Object.keys(components).forEach(function (key) {
      components[key].destroy();
    });

    var atom = Object.freeze({
                               decimal: "18446744073709551615"
                             });
    var margin = Object.freeze({
                                 decimal: "0.5"
                               });
    var rawAtoms = JSON.parse('{"settingsVersion":37,"bar":{},"__proto__":{"constructor":false}}');
    rawAtoms.bar.marginVertical = margin;
    rawAtoms.unknown = atom;
    var atomValues = Object.create(null);
    atomValues.bar = {
      marginVertical: margin
    };
    atomValues.unknown = atom;
    atomValues["__proto__"] = rawAtoms["__proto__"];
    var atoms = transform({
                            raw: rawAtoms,
                            values: atomValues,
                            compatibilityRaw: rawAtoms,
                            source: {
                              presence: "present"
                            },
                            lowerValues: spec.defaults
                          });
    check(atoms.values.bar.marginVertical === 9 && atoms.values.unknown === atom && atoms.compatibilityRaw.unknown === atom, "numeric atom identity and explicit arithmetic");
    check(Object.prototype.hasOwnProperty.call(atoms.values, "__proto__") && atoms.values["__proto__"].constructor === false, "own opaque member preserved");
    var absent = transform({
                             raw: {},
                             values: {},
                             compatibilityRaw: {},
                             source: {
                               presence: "absent"
                             },
                             lowerValues: spec.defaults
                           });
    check(canonical(absent) === canonical({
                                            values: {},
                                            compatibilityRaw: {},
                                            effects: [],
                                            diagnostics: []
                                          }), "fresh absence is not v0 legacy");
    console.log("I5_MIGRATIONS: PARITY_PASS");
    Qt.exit(0);
  }
  function verify() {
    Object.keys(spec.expected).forEach(function (path) {
      var value = cfg;
      path.split(".").forEach(function (key) {
        value = value[key];
      });
      check(canonical(value) === canonical(spec.expected[path]), "worker consumer " + path + ": " + canonical(value));
    });
    check(cfg.settingsVersion === 62, "compatibility version is not durable schema version");
  }
  function ready() {
    if (!store || !store.ready || started)
      return;
    started = true;
    try {
      verify();
      check(canonical(observedEffects) === canonical(spec.effects), "worker effect order/count");
      if (spec.restart) {
        check(scaleConsumer === 1.41, "separate cold persisted consumer");
        console.log("I5_MIGRATIONS: RESTART_PASS");
        store.close(function (result) {
          try {
            root.check(result.status === "nothing_to_save", "restart has no startup choices");
            Qt.exit(0);
          } catch (error) {
            root.fail(error);
          }
        });
      } else {
        // Unchanged reload must not redeliver process effects or create choices.
        store.reload(function (result) {
          try {
            root.check(result.status === "reloaded", "worker reload");
            root.verify();
            root.check(canonical(observedEffects) === canonical(spec.effects), "effects deduplicated on unchanged reload");
            root.cfg.general.scaleRatio = 1.41;
            store.save(function (saved) {
              try {
                root.check(saved.status === "saved", "acknowledged sparse publication");
                root.check(scaleConsumer === 1.41, "actual edit consumer");
                console.log("I5_MIGRATION_RECEIPT: " + JSON.stringify(saved));
                store.close(function (closed) {
                  try {
                    root.check(closed.status === "nothing_to_save", "closed without additional choices");
                    console.log("I5_MIGRATIONS: SAVED_PASS");
                    Qt.exit(0);
                  } catch (error) {
                    root.fail(error);
                  }
                });
              } catch (error) {
                root.fail(error);
              }
            });
          } catch (error) {
            root.fail(error);
          }
        });
      }
    } catch (error) {
      fail(error);
    }
  }
  Main.SettingsSources {
    id: routes
    settingsFile: root.spec.directory + "/settings.json"
    overridesDirectory: root.spec.directory + "/settings"
  }
  Component {
    id: storeComponent
    ConfigStore {
      autoSave: false
      evidenceDirectory: root.spec.directory + "/evidence"
      schema: Main.SettingsSchema {
        homeDirectory: "/inert/home"
        defaultFont: "Test Sans"
        fixedFont: "Test Mono"
      }
      sources: routes.sources
      projections: [
        ConfigProjection {
          projectionId: "historical-settings"
          sourceIds: ["legacy"]
          transform: MigrationSource.transform
        },
        ConfigProjection {
          projectionId: "test-worker-raw-contract"
          sourceIds: ["legacy"]
          transform: `function(input) {
            if (input.source.presence === "present") {
              [input.raw, input.values, input.compatibilityRaw].forEach(function(value) {
                if (!Object.isFrozen(value.wide) || value.wide.decimal !== "18446744073709551615"
                    || !Object.prototype.hasOwnProperty.call(value, "__proto__")
                    || value.__proto__.constructor !== false)
                  throw new Error("worker atom/opaque contract");
              });
              if (Number(input.raw.settingsVersion.decimal) < 55 && input.raw.controlCenter
                  && Object.prototype.hasOwnProperty.call(input.raw.controlCenter, "openAtMouseOnBarRightClick")) {
                var original = input.raw.bar && input.raw.bar.rightClickFollowMouse !== undefined
                    ? input.raw.bar.rightClickFollowMouse : input.lowerValues.bar.rightClickFollowMouse;
                if (input.values.bar.rightClickFollowMouse !== original
                    || input.compatibilityRaw.bar.rightClickFollowMouse !== input.raw.controlCenter.openAtMouseOnBarRightClick
                    || Object.prototype.hasOwnProperty.call(input.compatibilityRaw.controlCenter, "openAtMouseOnBarRightClick"))
                  throw new Error("worker raw-only 55 contract");
              }
            }
            return {values: input.values, compatibilityRaw: input.compatibilityRaw, effects: [], diagnostics: []};
          }`
        }
      ]
      onProjectionEffects: function (event) {
        root.observedEffects = root.observedEffects.concat(event.effects);
      }
      onReadyChanged: Qt.callLater(root.ready)
      onStatusChanged: {
        if (status === ConfigStore.Error)
          root.fail("worker initialization: " + error);
      }
    }
  }
  Component.onCompleted: {
    Qt.callLater(function () {
      try {
        if (spec.parity)
          parity();
        else {
          store = storeComponent.createObject(root);
          ready();
        }
      } catch (error) {
        fail(error);
      }
    });
  }
  Timer {
    interval: 25000
    running: true
    onTriggered: root.fail("migration watchdog")
  }
}
