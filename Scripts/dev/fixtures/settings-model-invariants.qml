// Inert actual-JS-engine tests. Controlled I/O and a TEST bridge, never the
// production Settings singleton, native filesystem or desktop service graph.
import QtQuick
import "../../../Helpers/QtObj2JS.js" as QtObj2JS
import "../../../Helpers/SettingsModel.js" as SettingsModel
import "../../../Helpers/sha256.js" as Checksum

QtObject {
  id: probe
  property var activeHarness: null
  property var listener: null
  property int queryRevision: 0
  property var boundDefault: {
    void probe.queryRevision;
    return probe.activeHarness ? probe.activeHarness.model.query("default", {
                                                                   "path": "ui.scale"
                                                                 }) : undefined;
  }
  property QtObject consumer: QtObject {
    property QtObject ui: QtObject {
      property real scale: 1
      onScaleChanged: {
        if (probe.listener)
          probe.listener();
      }
    }
    property QtObject bindings: QtObject {
      property string environment: "none"
    }
    property QtObject bar: QtObject {
      property string position: "top"
      property list<var> records: [
        {
          "id": "opaque",
          "values": [false, 0, null, ""]
        }
      ]
    }
    property QtObject general: QtObject {
      property real scaleRatio: 1
    }
    property QtObject wallpaper: QtObject {
      property string directory: "/model/wallpaper"
    }
  }
  property Timer watchdog: Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.log("SETTINGS_MODEL_WATCHDOG");
      Qt.exit(2);
    }
  }

  function copy(value) {
    return SettingsModel.detached(value);
  }
  function assertThat(value, message) {
    if (!value)
      throw new Error(message);
  }
  function equal(left, right) {
    return JSON.stringify(left) === JSON.stringify(right);
  }
  function initial() {
    return {
      "ui": {
        "scale": 1
      },
      "bindings": {
        "environment": "none"
      },
      "general": {
        "scaleRatio": 1
      },
      "bar": {
        "position": "top",
        "records": [
          {
            "id": "opaque",
            "values": [false, 0, null, ""]
          }
        ]
      },
      "wallpaper": {
        "directory": "/model/wallpaper"
      }
    };
  }
  function stateFor(raw, identity) {
    return raw === null ? {
                            "exists": false,
                            "identity": "missing",
                            "sha256": "",
                            "raw": "",
                            "valid": true,
                            "data": {}
                          } : {
      "exists": true,
      "identity": identity,
      "sha256": Checksum.sha256(raw),
      "raw": raw,
      "valid": true,
      "data": JSON.parse(raw)
    };
  }
  function frozen(intent) {
    return copy({
                  "captureId": intent.captureId,
                  "provenance": intent.provenance,
                  "section": intent.section,
                  "path": intent.path,
                  "json": intent.json,
                  "base": intent.base,
                  "foreignEpoch": intent.foreignEpoch,
                  "coveredPaths": intent.coveredPaths
                });
  }
  function harness(seed, live) {
    var h = {
      "model": SettingsModel.create({
                                      "session": "controlled",
                                      "settingsFile": "/model/settings.json",
                                      "overridesDir": "/model/settings/",
                                      "cacheDir": "/model/cache/"
                                    }),
      "data": copy(initial()),
      "fs": {},
      "prepared": {},
      "callbacks": {},
      "callbackSerial": 0,
      "depth": 0,
      "held": [],
      "hold": null,
      "beforeIo": null,
      "failPrepare": null,
      "events": [],
      "io": [],
      "publicationSerial": 0,
      "live": live === true
    };
    seed = seed || {};
    h.current = function () {
      return h.live ? QtObj2JS.qtObjectToPlainObject(probe.consumer) : copy(h.data);
    };
    h.register = function (callback) {
      if (!callback)
        return null;
      var token = "external-" + (++h.callbackSerial);
      h.callbacks[token] = callback;
      return token;
    };
    h.dispatch = function (event) {
      event.current = h.current();
      h.depth++;
      try {
        var result = h.model.transition(event);
        if (h === probe.activeHarness)
          probe.queryRevision++;
        for (var i = 0; i < result.orderedEffects.length; i++)
          h.execute(result.orderedEffects[i]);
        return result.returnValue;
      } finally {
        h.depth--;
        if (!h.depth && (event.type !== "pump" || h.model.query("pumpReady")))
          h.dispatch({
                       "type": "pump"
                     });
      }
    };
    h.assign = function (path, value) {
      var parts = path.split("."), target = h.live ? probe.consumer : h.data;
      for (var i = 0; i < parts.length - 1; i++)
        target = target[parts[i]];
      target[parts[parts.length - 1]] = value;
    };
    h.apply = function (path, value) {
      var prepared = h.dispatch({
                                  "type": "leafPrepare",
                                  "path": path,
                                  "value": value
                                });
      if (!prepared)
        return;
      if (prepared.children) {
        for (var i = 0; i < prepared.children.length; i++)
          h.apply(prepared.children[i].path, prepared.children[i].value);
        return;
      }
      var applied = false;
      try {
        h.assign(path, prepared.value);
        applied = true;
      } finally {
        h.dispatch({
                     "type": "leafAssigned",
                     "token": prepared.token,
                     "applied": applied
                   });
      }
    };
    h.complete = function (effect, response) {
      h.dispatch({
                   "type": "ioCompleted",
                   "token": effect.token,
                   "owner": effect.owner,
                   "success": response.ok === true,
                   "payload": response,
                   "error": response.error || ""
                 });
    };
    h.respond = function (effect) {
      var state = h.fs[effect.section] || stateFor(null, "missing"), input = effect.input;
      if (effect.mode === "inspect")
        return {
          "ok": true,
          "state": copy(state)
        };
      if (effect.mode === "retain")
        return {
          "ok": true,
          "retained": "/controlled/retained-" + effect.token
        };
      if (effect.mode === "prepare") {
        if (h.failPrepare && h.failPrepare(effect))
          return {
            "ok": false,
            "error": "controlled preparation failure"
          };
        h.prepared[effect.temporary] = input.raw;
        return {
          "ok": true,
          "base": copy(state),
          "prepared_sha256": Checksum.sha256(input.raw || ""),
          "delete": input.raw === null
        };
      }
      if (effect.mode === "promote") {
        var raw = h.prepared[effect.temporary];
        h.fs[effect.section] = stateFor(raw, "publication-" + (++h.publicationSerial));
        return {
          "ok": true,
          "state": copy(h.fs[effect.section]),
          "publication": {
            "attempted": true,
            "completed": true,
            "uncertain": false
          }
        };
      }
      throw new Error("Uncharacterized controlled effect");
    };
    h.release = function (index, override) {
      var held = h.held.splice(index || 0, 1)[0];
      assertThat(held !== undefined, "missing held operation");
      h.complete(held.effect, override || held.response || h.respond(held.effect));
      return held;
    };
    h.execute = function (effect) {
      if (effect.kind === "io") {
        h.io.push(copy(effect));
        if (h.beforeIo)
          h.beforeIo(effect);
        var hold = h.hold ? h.hold(effect) : "";
        if (hold)
          h.held.push({
                        "effect": copy(effect),
                        "response": hold === "after" ? h.respond(effect) : null
                      });
        else
          h.complete(effect, h.respond(effect));
      } else if (effect.kind === "reload")
        h.dispatch({
                     "type": "readDispatch",
                     "section": effect.section
                   });
      else if (effect.kind === "readNext")
        h.dispatch({
                     "type": "readNext",
                     "token": effect.token
                   });
      else if (effect.kind === "observation") {
        var paths = h.dispatch({
                                 "type": "observationBegin",
                                 "token": effect.token
                               });
        try {
          for (var i = 0; i < paths.length; i++)
            h.dispatch({
                         "type": "observationLeaf",
                         "token": effect.token,
                         "path": paths[i]
                       });
        } finally {
          h.dispatch({
                       "type": "observationEnd",
                       "token": effect.token
                     });
        }
      } else if (effect.kind === "applyValue")
        h.apply(effect.path, effect.value);
      else if (effect.kind === "effective") {
        h.events.push({
                        "kind": "effective",
                        "sections": effect.sections
                      });
        try {
          if (h.onEffective)
            h.onEffective(effect.sections);
        } finally {
          h.dispatch({
                       "type": "effectiveDelivered"
                     });
        }
      } else if (effect.kind === "observed") {
        try {
          var notification;
          while ((notification = h.dispatch({
                                              "type": "observedNext"
                                            })) !== null)
            h.events.push(copy(notification));
        } finally {
          h.dispatch({
                       "type": "observedDelivered"
                     });
        }
      } else if (effect.kind === "saveDelivery" || effect.kind === "readCallback") {
        var callback = h.callbacks[effect.callbackToken], failed = false;
        delete h.callbacks[effect.callbackToken];
        if (effect.kind === "saveDelivery")
          h.events.push({
                          "kind": "signal",
                          "value": h.dispatch({
                                                "type": "saveDeliveryBegin",
                                                "token": effect.token
                                              })
                        });
        try {
          if (callback)
            callback(effect);
        } catch (error) {
          failed = true;
          h.events.push({
                          "kind": "caught-callback"
                        });
        } finally {
          h.dispatch({
                       "type": effect.kind === "saveDelivery" ? "saveDelivered" : "readNext",
                       "token": effect.token,
                       "callbackError": failed
                     });
        }
      } else if (effect.kind === "log" || effect.kind === "saveFailed")
        h.events.push(copy(effect));
      else
        throw new Error("Unexpected controlled effect: " + effect.kind);
    };
    h.save = function (callback) {
      var token = h.register(callback);
      h.dispatch({
                   "type": "captureBegin"
                 });
      try {
        h.dispatch({
                     "type": "save",
                     "callbackToken": token
                   });
      } finally {
        h.dispatch({
                     "type": "captureEnd"
                   });
      }
    };
    h.setup = function (identity, callback) {
      var token = h.register(callback);
      h.dispatch({
                   "type": "setupBegin",
                   "identity": identity
                 });
      try {
        h.dispatch({
                     "type": "setupSubmit",
                     "identity": identity,
                     "callbackToken": token
                   });
      } finally {
        h.dispatch({
                     "type": "captureEnd"
                   });
      }
    };
    h.dispatch({
                 "type": "schema",
                 "schema": h.current()
               });
    h.dispatch({
                 "type": "defaults",
                 "value": h.current()
               });
    h.dispatch({
                 "type": "initialFile",
                 "section": "legacy",
                 "raw": "",
                 "exists": false,
                 "data": {}
               });
    var sections = Object.keys(h.current());
    for (var si = 0; si < sections.length; si++) {
      var section = sections[si], data = seed[section] || {}, exists = Object.prototype.hasOwnProperty.call(seed, section);
      var raw = exists ? JSON.stringify(data) + "\n" : "";
      h.fs[section] = stateFor(exists ? raw : null, "initial-" + section);
      h.dispatch({
                   "type": "initialFile",
                   "section": section,
                   "raw": raw,
                   "exists": exists,
                   "data": data
                 });
    }
    h.dispatch({
                 "type": "loaded"
               });
    return h;
  }
  function modelState(h) {
    return h.model.inspect().state;
  }
  function holdPromotion(h, section) {
    h.hold = function (effect) {
      return effect.mode === "promote" && effect.section === section ? "before" : "";
    };
  }

  function run() {
    var cases = [["instance-and-alias-isolation", function () {
      var a = harness(), b = harness(), event = {
        "type": "defaults",
        "value": {
          "ui": {
            "scale": 3
          }
        }
      };
      a.dispatch(event);
      event.value.ui.scale = 9;
      var queried = a.model.query("default", {
                                    "path": "ui"
                                  });
      queried.scale = 12;
      var inspected = a.model.inspect();
      inspected.state._defaultSettings.ui.scale = 15;
      assertThat(a.model.query("default", {
                                 "path": "ui.scale"
                               }) === 3 && b.model.query("default", {
                                                           "path": "ui.scale"
                                                         }) === 1, "query/input/instance alias leaked");
      a.data.ui.scale = 2;
      a.dispatch({
                   "type": "merge"
                 });
      assertThat(modelState(b)._captureSerial === 0 && modelState(b)._snapshot.ui.scale === 1, "instance bookkeeping leaked");
      assertThat(modelState(a)._acceptedFiles.ui.data.scale === undefined && a.model.inspect().ownership.acceptedSharesWorking.ui === false, "accepted/working alias leaked");
    }], ["frozen-capture-and-ABA", function () {
      var h = harness();
      holdPromotion(h, "ui");
      h.data.ui.scale = 1.25;
      h.save();
      var intent = modelState(h)._activePersist.intent, tuple = frozen(intent), id = intent.captureId;
      intent.base.data.changed = true;
      intent.coveredPaths.scale = -1;
      h.data.ui.scale = 1.75;
      h.dispatch({
                   "type": "merge"
                 });
      h.data.ui.scale = 1.25;
      h.dispatch({
                   "type": "merge"
                 });
      var pending = modelState(h)._pendingPaths.ui.scale;
      assertThat(equal(tuple, frozen(h.model.query("capture", {
                                                     "id": id
                                                   }))) && h.model.query("captureOwned", {
                                                                           "id": id
                                                                         }), "held capture changed or lost owner");
      h.hold = null;
      h.release();
      assertThat(modelState(h)._pendingPaths.ui.scale === pending, "old completion erased newer ABA operation");
      var first = h.fs.ui.identity;
      h.save();
      assertThat(h.fs.ui.data.scale === 1.25 && h.fs.ui.identity !== first && !modelState(h)._pendingPaths.ui, "retained ABA operation was not republished/covered");
    }], ["stale-duplicate-wrong-owner-completion", function () {
      var h = harness({
                        "ui": {
                          "scale": 1
                        }
                      });
      h.hold = function (effect) {
        return effect.mode === "inspect" ? "after" : "";
      };
      h.dispatch({
                   "type": "readDispatch",
                   "section": "ui"
                 });
      var first = copy(h.held[0]);
      var before = modelState(h);
      h.dispatch({
                   "type": "ioCompleted",
                   "token": first.effect.token,
                   "owner": first.effect.owner + 99,
                   "success": true,
                   "payload": first.response
                 });
      assertThat(equal(before, modelState(h)), "wrong-owner completion mutated bookkeeping");
      h.fs.ui = stateFor('{"scale":1.7}\n', "foreign-2");
      h.dispatch({
                   "type": "readDispatch",
                   "section": "ui"
                 });
      h.hold = null;
      h.release(1);
      h.release(0);
      assertThat(h.data.ui.scale === 1.7 && modelState(h)._acceptedFiles.ui.identity === "foreign-2", "stale read rolled back current consumer");
      before = modelState(h);
      h.complete(first.effect, first.response);
      assertThat(equal(before, modelState(h)), "duplicate completion mutated owner");
    }], ["publication-uncertainty-retention", function () {
      var h = harness({
                        "ui": {
                          "scale": 1
                        }
                      });
      holdPromotion(h, "ui");
      h.data.ui.scale = 1.7;
      var result;
      h.save(function (e) {
        result = e;
      });
      var held = h.held[0], own = stateFor(held.effect.input.delete ? null : h.prepared[held.effect.temporary], "unconfirmed-own");
      h.fs.ui = own;
      h.hold = null;
      h.release(0, {
                  "ok": false,
                  "error": "controlled post-publication failure",
                  "state": own,
                  "publication": {
                    "attempted": true,
                    "completed": true,
                    "uncertain": true
                  }
                });
      var intent = modelState(h)._ordinaryIntents.ui[0];
      assertThat(result.success === false && intent.publicationUncertain && intent.unresolvedConflict && intent.publicationWitnesses.length === 1, "publication uncertainty was lost");
      h.save(function (e) {
        result = e;
      });
      assertThat(result.success === false && h.fs.ui.identity === "unconfirmed-own", "unconfirmed compatible output authorized retry");
    }], ["late-conflict-through-retention", function () {
      var h = harness({
                        "ui": {
                          "scale": 1
                        }
                      });
      holdPromotion(h, "ui");
      h.data.ui.scale = 1.7;
      var result;
      h.save(function (e) {
        result = e;
      });
      h.fs.ui = stateFor('{"scale":1,"foreign":1}\n', "foreign-1");
      h.dispatch({
                   "type": "readDispatch",
                   "section": "ui"
                 });
      h.hold = function (e) {
        return e.mode === "retain" ? "before" : "";
      };
      h.release(0, {
                  "ok": false,
                  "error": "controlled preimage disagreement",
                  "state": copy(h.fs.ui),
                  "conflict": true
                });
      assertThat(h.held.length === 1 && !result, "retention was not an outstanding barrier");
      h.fs.ui = stateFor('{"scale":1,"foreign":2}\n', "foreign-2");
      var late = copy(h.fs.ui);
      h.dispatch({
                   "type": "readDispatch",
                   "section": "ui"
                 });
      h.hold = null;
      h.release();
      var intent = modelState(h)._ordinaryIntents.ui[0];
      assertThat(result.success === false && intent.foreignObservations.some(function (state) {
        return equal(state, late);
      }) && intent.retainedObservations["true:" + late.sha256 + ":" + late.identity], "late complete conflict escaped retention/terminal boundary");
    }], ["ordered-setup-suffix-coverage", function () {
      var h = harness();
      h.hold = function (e) {
        return e.mode === "prepare" && e.section === "general" && JSON.parse(e.input.raw).scaleRatio === 1.1 ? "before" : "";
      };
      h.data.general.scaleRatio = 1.1;
      h.save();
      h.data.general.scaleRatio = 1.2;
      h.save();
      var result;
      h.setup("setup", function (e) {
        result = e;
      });
      var original = modelState(h)._setupBundles.setup.intents.map(frozen);
      h.hold = null;
      h.release(0, {
                  "ok": false,
                  "error": "controlled A preparation failure"
                });
      assertThat(result.success === false && h.fs.general.data.scaleRatio === 1.2, "A-failed/B-success schedule was not established");
      var old = copy(modelState(h)._setupBundles.setup.coveredRevisions);
      h.setup("setup", function (e) {
        result = e;
      });
      var bundle = modelState(h)._setupBundles.setup;
      assertThat(result.success === true && bundle.coveredRevisions[0] > old[0] && bundle.coveredRevisions[1] > bundle.coveredRevisions[0] && h.fs.general.data.scaleRatio === 1.2, "setup used obsolete suffix coverage");
      assertThat(equal(original, bundle.intents.map(frozen)), "setup retry recaptured/mutated request work");
    }], ["notification-reentry-and-fresh-pump", function () {
      var h = harness(), reentered = false;
      h.onEffective = function () {
        if (reentered)
          return;
        reentered = true;
        h.data.general.scaleRatio = 1.2;
        h.save();
        assertThat(modelState(h)._activePersist === null, "nested save activated I/O during effective delivery");
      };
      h.data.ui.scale = 1.7;
      h.save();
      assertThat(reentered && h.fs.ui.data.scale === 1.7 && h.fs.general.data.scaleRatio === 1.2, "notification reentry lost invocation-boundary captures");
    }], ["bridge-real-QObject-immediate-nested-capture", function () {
      probe.listener = null;
      probe.consumer.ui.scale = 1;
      var h = harness({}, true);
      probe.activeHarness = h;
      var baselineSeen = false, callback = false, armed = true;
      probe.listener = function () {
        if (!armed)
          return;
        armed = false;
        baselineSeen = modelState(h)._snapshot.ui.scale === 1.4;
        probe.consumer.ui.scale = 1.7;
        h.save(function () {
          callback = true;
          throw new Error("controlled nested completion throw");
        });
        assertThat(modelState(h)._captureDepth > 0 && modelState(h)._activePersist === null, "real listener nested save escaped application scope");
      };
      h.fs.ui = stateFor('{"scale":1.4}\n', "external");
      h.dispatch({
                   "type": "readDispatch",
                   "section": "ui"
                 });
      probe.listener = null;
      assertThat(baselineSeen && callback && h.fs.ui.data.scale === 1.7 && probe.consumer.ui.scale === 1.7 && h.events.some(function (e) {
        return e.kind === "caught-callback";
      }), "real QObject baseline/nested capture/callback throw contract failed");
    }], ["bridge-opaque-list-failed-save-invalidation", function () {
      var h = harness({}, true);
      probe.activeHarness = h;
      h.failPrepare = function () {
        return true;
      };
      probe.consumer.bar.records[0].values.push("local-opaque");
      var result;
      h.save(function (e) {
        result = e;
      });
      assertThat(result.success === false && h.events.some(function (e) {
        return e.kind === "effective" && e.sections.indexOf("bar") !== -1;
      }), "failed save lost opaque-list effective invalidation");
      assertThat(JSON.parse(modelState(h)._ordinaryIntents.bar[0].json).records[0].values.indexOf("local-opaque") !== -1, "actual in-place QObject-list edit was not captured");
    }], ["bridge-token-detachment-and-empty-save-reentry", function () {
      var h = harness(), order = [];
      h.save(function () {
        order.push("first");
        assertThat(Object.keys(h.callbacks).length === 0, "old callback was still registered on invocation");
        h.save(function () {
          order.push("nested");
        });
      });
      assertThat(equal(order, ["first", "nested"]) && Object.keys(h.callbacks).length === 0 && h.events.filter(function (e) {
        return e.kind === "signal";
      }).length === 2, "empty-save token delivery duplicated/erased reentry");
    }], ["bridge-revision-backed-default-query", function () {
      var h = harness();
      probe.activeHarness = h;
      probe.queryRevision++;
      assertThat(probe.boundDefault === 1, "test bridge default binding initial value");
      h.dispatch({
                   "type": "defaults",
                   "value": {
                     "ui": {
                       "scale": 2
                     }
                   }
                 });
      assertThat(probe.boundDefault === 2, "test bridge query did not invalidate on default load");
      h.dispatch({
                   "type": "defaults",
                   "value": null
                 });
      assertThat(probe.boundDefault === undefined, "test bridge query did not invalidate on parse-failure value");
    }], ["bridge-failed-assignment-baseline-restoration", function () {
      var h = harness();
      h.dispatch({
                   "type": "captureBegin"
                 });
      var prepared = h.dispatch({
                                  "type": "leafPrepare",
                                  "path": "ui.scale",
                                  "value": 1.4
                                });
      assertThat(modelState(h)._snapshot.ui.scale === 1.4, "intended baseline absent before assignment");
      h.dispatch({
                   "type": "leafAssigned",
                   "token": prepared.token,
                   "applied": false
                 });
      assertThat(modelState(h)._snapshot.ui.scale === 1, "failed assignment baseline not restored");
      h.dispatch({
                   "type": "captureEnd"
                 });
    }]];
    var failed = false;
    for (var i = 0; i < cases.length; i++) {
      var id = cases[i][0], result = {
        "id": id,
        "status": "PASS",
        "scope": id.indexOf("bridge-") === 0 ? "test bridge + actual model only" : "actual model + controlled effects only"
      };
      try {
        cases[i][1]();
      } catch (error) {
        failed = true;
        result.status = "FAIL";
        result.error = String(error);
      } finally {
        probe.listener = null;
        probe.activeHarness = null;
      }
      console.log("SETTINGS_MODEL_TRACE|" + JSON.stringify(result));
    }
    console.log("SETTINGS_MODEL_REGRESSION: " + (failed ? "FAIL" : "PASS"));
    Qt.exit(failed ? 1 : 0);
  }
  Component.onCompleted: Qt.callLater(probe.run)
}
