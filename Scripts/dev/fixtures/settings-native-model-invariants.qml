import QtQuick
import Quickshell
import AtmospheraSettingsTest 1.0

// The historical trace IDs now exercise the installed native owner through real
// ConfigFacade QObjects. Fault controls are test-only; no preference mirror.
QtObject {
  id: probe
  property var owners: []
  property var waiters: []
  property int serial: 0
  property int errors: 0
  property string active: ""
  property var selected: null
  readonly property var boundDefault: selected && selected.ready ? selected.defaultValue(["ui", "scale"]) : undefined
  property Component factory: Component { NativeModelOwner {} }
  function check(ok, message) { if (!ok) throw new Error(message); }
  function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function wait(predicate) {
    return new Promise(function (resolve, reject) {
      probe.waiters = probe.waiters.concat([{predicate: predicate, resolve: resolve, reject: reject, since: Date.now()}]);
    });
  }
  function call(owner, method, args) {
    return new Promise(function (resolve) { owner[method].apply(owner, (args || []).concat([resolve])); });
  }
  function make(properties) {
    var options = Object.assign({directory: Quickshell.env("MODEL_NATIVE_ROOT") + "/owner-" + (++serial)}, properties || {});
    var owner = factory.createObject(probe, options);
    check(owner !== null, "native owner construction"); owners.push(owner);
    return wait(function () { return owner.ready || owner.error !== ""; }).then(function () {
      check(owner.ready, "native owner ready: " + owner.error); return owner;
    });
  }
  function settle(owner) { return call(owner, "save").then(function (result) { check(result.status !== "failed", "native settlement: " + result.error); return result; }); }
  property var cases: [
    ["instance-and-alias-isolation", function () {
      var a, b;
      return make({schemaDefault: 3}).then(function (owner) { a = owner; return make(); }).then(function (owner) {
        b = owner;
        var queried = a.value(["bar", "records"]); queried[0].values.push("detached");
        var inspected = a.info(["ui", "scale"]); inspected.latestInput = "999";
        check(a.defaultValue(["ui", "scale"]) === 3 && b.defaultValue(["ui", "scale"]) === 1, "query/input/instance alias leaked");
        check(a.bar.records[0].values.length === 1 && a.info(["ui", "scale"]).latestInput === "0", "detached query mutated native owner");
        a.ui.scale = 2;
        check(b.ui.scale === 1 && b.info(["ui", "scale"]).latestInput === "0", "instance bookkeeping leaked");
        return settle(a);
      });
    }],
    ["frozen-capture-and-ABA", function () {
      var h, pending, original, receipt, identity;
      return make().then(function (owner) {
        h = owner; h.arm("rename", "ui"); h.ui.scale = 1.25; original = JSON.stringify(h.inputs());
        pending = call(h, "save"); return wait(function () { return h.held; });
      }).then(function () {
        var alias = h.inputs(); alias[0].value = 99;
        check(JSON.stringify(h.inputs()) === original, "held native capture/input alias changed work");
        h.ui.scale = 1.75; h.ui.scale = 1.25; h.release(); return pending;
      }).then(function (result) {
        receipt = result; check(result.status === "saved" && result.inputPrefix === "1", "first frozen save prefix changed");
        check(h.ui.scale === 1.25 && h.info(["ui", "scale"]).latestInput === "3", "old completion erased newer ABA operation");
        identity = h.identity("ui"); return settle(h);
      }).then(function (result) {
        check(result.status === "saved" && result.inputPrefix === "3" && h.identity("ui") !== identity,
          "retained ABA operation was not republished/covered: " + JSON.stringify({status: result.status, prefix: result.inputPrefix, coverage: result.coverage, identityChanged: h.identity("ui") !== identity}));
        check(JSON.parse(h.readRaw("ui")).scale === 1.25, "ABA final file");
      });
    }],
    ["stale-duplicate-wrong-owner-completion", function () {
      var h, first, second, callbacks = 0;
      return make().then(function (owner) { h = owner; return call(h, "holdReplies", [true]); }).then(function () {
        h.ui.scale = 1.4; first = call(h, "save").then(function (result) { callbacks++; return result; });
        h.ui.scale = 1.7; second = call(h, "save").then(function (result) { callbacks++; return result; });
        return wait(function () { return h.readRaw("ui") !== "" && JSON.parse(h.readRaw("ui")).scale === 1.7; });
      }).then(function () { return call(h, "releaseReplies", [1]); }).then(function () {
        check(h.ui.scale === 1.7, "stale read rolled back current consumer"); return call(h, "holdReplies", [false]);
      }).then(function () { return Promise.all([first, second]); }).then(function () {
        h.replay(0, false); h.replay(h.packetCount() - 1, true); h.replay(h.packetCount() - 1, false);
        check(callbacks === 2 && h.ui.scale === 1.7 && JSON.parse(h.readRaw("ui")).scale === 1.7, "stale/duplicate/wrong-owner delivery mutated owner or callbacks");
      });
    }],
    ["publication-uncertainty-retention", function () {
      var h, pending, identity, failed, originalBytes;
      return make().then(function (owner) {
        h = owner; h.arm("readback", "ui"); h.ui.scale = 1.7; pending = call(h, "save");
        return wait(function () { return h.held; });
      }).then(function () {
        check(JSON.parse(h.readRaw("ui")).scale === 1.7, "controlled output was not published before readback fault");
        h.release("controlled-readback"); return pending;
      }).then(function (result) {
        check(result.status === "failed" && result.publicationState === "uncertain" && result.evidence.length > 0, "publication uncertainty was lost");
        failed = result; identity = h.identity("ui"); originalBytes = h.readRaw("ui"); return call(h, "save");
      }).then(function (result) {
        // Native decision24 verifies the exact own witness; later saves retry
        // failed ordinary work (#19). Keep the original failure and evidence.
        check(result.status === "saved" && result.inputPrefix === failed.inputPrefix && Number(result.requestId) > Number(failed.requestId),
          "verified native own-output retry did not acknowledge its original prefix");
        check(h.ui.scale === 1.7 && h.readRaw("ui") === originalBytes && h.evidenceContains(originalBytes) &&
              h.failures().some(function (failure) { return failure.requestId === failed.requestId && failure.status === "failed" && failure.publicationState === "uncertain"; }),
          "verified retry lost latest value, exact own-output evidence or original failure history");
        console.log("NATIVE_OWN_RECOVERY|" + JSON.stringify({failed: failed, recovered: result, beforeIdentity: identity, afterIdentity: h.identity("ui")}));
        return call(h, "close");
      }).then(function (result) {
        check(result.status !== "failed", "verified own-output close failed");
        return make({directory: h.directory});
      }).then(function (cold) {
        check(cold.ui.scale === 1.7 && cold.readRaw("ui") === originalBytes, "verified own-output latest choice missed cold consumer");
      });
    }],
    ["late-conflict-through-retention", function () {
      var h, pending, late = '{"scale":1,"foreign":2}\n';
      return make().then(function (owner) {
        h = owner; h.writeRaw("ui", '{"scale":1}\n'); return call(h, "reload");
      }).then(function () { return call(h, "holdReplies", [true]); }).then(function () {
        h.arm("rename", "ui"); h.ui.scale = 1.7; pending = call(h, "save"); return wait(function () { return h.held; });
      }).then(function () {
        h.writeRaw("ui", '{"scale":1,"foreign":1}\n'); h.release("controlled-preimage");
        return wait(function () { return !h.held; });
      }).then(function () {
        h.writeRaw("ui", late); h.reload(function () {});
        return wait(function () { return h.evidenceContains(late); });
      }).then(function () { return call(h, "holdReplies", [false]); }).then(function () { return pending; }).then(function (result) {
        check(result.status === "failed" && h.evidenceContains(late) && h.readRaw("ui") === late && h.ui.scale === 1.7,
          "late complete conflict escaped retention/terminal boundary");
      });
    }],
    ["ordered-setup-suffix-coverage", function () {
      var h, first, second, submitted, token, capture, failedA;
      return make().then(function (owner) {
        h = owner; h.arm("write", "general"); h.general.scaleRatio = 1.1;
        first = call(h, "save"); return wait(function () { return h.held; });
      }).then(function () {
        h.general.scaleRatio = 1.2; second = call(h, "save");
        submitted = call(h, "retain", ["setup", [["general"]], []]);
        h.release("controlled-A-preparation"); return Promise.all([first, second, submitted]);
      }).then(function (results) {
        check(results[0].status === "failed" && results[1].status === "saved" && JSON.parse(h.readRaw("general")).scaleRatio === 1.2,
          "A-failed/B-success schedule was not established");
        failedA = results[0];
        check(results[2].status === "retained", "setup work retained"); token = results[2].groupToken; capture = h.group(token).capturePrefix;
        return call(h, "saveGroup", [token, false]);
      }).then(function (result) {
        // Integration decision18: B already saved the latest choice. The
        // wizard's own failed-save Retry barrier has separate deployment cases.
        check(result.status === "nothing_to_save" && h.group(token).state === "succeeded"
              && h.group(token).capturePrefix === capture && h.group(token).attempts.length === 1,
          "setup did not acknowledge the already saved latest choice");
        check(h.failures().some(function (failure) { return failure.requestId === failedA.requestId && failure.status === "failed"; }),
          "later successful choice erased the recorded A failure");
        check(h.general.scaleRatio === 1.2, "setup erased newer local suffix");
        check(JSON.parse(h.readRaw("general")).scaleRatio === 1.2, "setup used obsolete suffix coverage");
      });
    }],
    ["notification-reentry-and-fresh-pump", function () {
      var h, nested, reentered = false;
      return make().then(function (owner) {
        h = owner;
        h.valuesChanged.connect(function () {
          if (reentered) return; reentered = true; h.general.scaleRatio = 1.2; nested = call(h, "save");
        });
        h.ui.scale = 1.7; return call(h, "save");
      }).then(function () { return nested; }).then(function () {
        check(reentered && JSON.parse(h.readRaw("ui")).scale === 1.7 && JSON.parse(h.readRaw("general")).scaleRatio === 1.2,
          "notification reentry lost invocation-boundary captures");
      });
    }],
    ["bridge-real-QObject-immediate-nested-capture", function () {
      var h, nested, armed = true, baseline = false, called = false;
      return make().then(function (owner) {
        h = owner;
        h.ui.changed.connect(function () {
          if (!armed) return; armed = false;
          baseline = h.ui.scale === 1.4 && h.value(["ui", "scale"]) === 1.4;
          h.ui.scale = 1.7;
          nested = new Promise(function (resolve) { h.save(function (result) { called = true; resolve(result); throw new Error("controlled nested completion throw"); }); });
        });
        h.writeRaw("ui", '{"scale":1.4}\n'); return call(h, "reload");
      }).then(function () { return nested; }).then(function () {
        check(baseline && called && h.ui.scale === 1.7 && JSON.parse(h.readRaw("ui")).scale === 1.7,
          "real QObject baseline/nested capture/callback throw contract failed");
      });
    }],
    ["bridge-opaque-list-failed-save-invalidation", function () {
      var h, pending, observed = false;
      return make().then(function (owner) {
        h = owner; h.valuesChanged.connect(function (paths) { if (paths.some(function (path) { return path[0] === "bar"; })) observed = true; });
        h.arm("write", "bar"); h.bar.records[0].values.push("local-opaque"); pending = call(h, "save");
        return wait(function () { return h.held; });
      }).then(function () { h.release("controlled-preparation"); return pending; }).then(function (result) {
        check(result.status === "failed" && observed, "failed save lost opaque-list effective invalidation");
        check(h.bar.records[0].values.indexOf("local-opaque") !== -1 && h.failures().length > 0,
          "actual in-place QObject-list edit was not captured/retained");
      });
    }],
    ["bridge-token-detachment-and-empty-save-reentry", function () {
      var h, order = [], signals = 0;
      return make().then(function (owner) {
        h = owner; h.completed.connect(function () { signals++; });
        return new Promise(function (resolve) {
          h.save(function (first) {
            order.push("first"); check(first.status === "nothing_to_save" && h.callbackCount === 0 && signals === 1, "callback still registered or signal not first");
            h.save(function (next) { order.push("nested"); resolve(next); });
          });
        });
      }).then(function (result) {
        check(result.status === "nothing_to_save" && equal(order, ["first", "nested"]) && h.callbackCount === 0 && signals === 2,
          "empty-save token delivery duplicated/erased reentry");
      });
    }],
    ["bridge-revision-backed-default-query", function () {
      return make().then(function (owner) { selected = owner; check(boundDefault === 1, "default binding initial value"); return make({schemaDefault: 2}); }).then(function (owner) {
        selected = owner; check(boundDefault === 2, "default query did not invalidate on owner/schema load");
        var invalid = factory.createObject(probe, {directory: Quickshell.env("MODEL_NATIVE_ROOT") + "/invalid", invalidSchema: true}); owners.push(invalid); selected = invalid;
        return wait(function () { return invalid.error !== ""; });
      }).then(function () { check(boundDefault === undefined, "default query retained stale data after failed owner/schema load"); selected = null; });
    }],
    ["bridge-failed-assignment-baseline-restoration", function () {
      var h, restored = false;
      return make().then(function (owner) { h = owner; return call(h, "reject", [["ui", "scale"], true]); }).then(function () {
        h.completed.connect(function (result) {
          if (result.status === "failed" && result.error === "test-admission") restored = h.ui.scale === 1 && h.value(["ui", "scale"]) === 1;
        });
        h.ui.scale = 1.4; check(h.ui.scale === 1.4, "intended local value absent before worker assignment");
        return wait(function () { return restored; });
      }).then(function () { check(h.info(["ui", "scale"]).intentRevision === "0", "failed assignment became accepted intent"); });
    }]
  ]
  function run(index) {
    if (index === cases.length) { console.log("SETTINGS_MODEL_REGRESSION: " + (errors ? "FAIL" : "PASS")); Qt.exit(errors ? 1 : 0); return; }
    active = cases[index][0];
    Promise.resolve().then(cases[index][1]).then(function () {
      console.log("SETTINGS_MODEL_TRACE|" + JSON.stringify({id: active, status: "PASS", owner: "native-installed-core"}));
      run(index + 1);
    }).catch(function (error) {
      errors++;
      console.error("SETTINGS_MODEL_TRACE|" + JSON.stringify({id: active, status: "FAIL", error: String(error)}));
      for (var owner of owners) { owner.release("test-abort"); owner.holdReplies(false, function () {}); }
      run(index + 1);
    });
  }
  property Timer pump: Timer {
    interval: 5; repeat: true; running: true
    onTriggered: {
      var remaining = [];
      for (var item of probe.waiters) {
        try {
          if (item.predicate()) item.resolve();
          else if (Date.now() - item.since > 5000) item.reject(new Error("native control/consumer timeout: " + probe.active));
          else remaining.push(item);
        } catch (error) { item.reject(error); }
      }
      probe.waiters = remaining;
    }
  }
  Component.onCompleted: run(0)
}
