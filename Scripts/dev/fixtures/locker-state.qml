import QtQuick
import Quickshell
import "../../../Helpers/LockerLifecycle.js" as Lifecycle

ShellRoot {
  Timer {
    interval: 0
    running: true
    onTriggered: {
      var cases = [];
      function fixture(adapter) {
        return {
          now: 1,
          takeover: true,
          descriptor: {
            generation: "g1",
            phase: "starting",
            authRole: null,
            snapshot: {
              adapter: adapter || "bundled"
            },
            requestedAt: 0,
            emergencyAt: 3,
            deadline: 30,
            handoverCommitted: false,
            probeEvents: {},
            sleepWindow: 0,
            units: {}
          },
          units: {}
        };
      }
      function unit(v, role, state) {
        v.descriptor.units[role] = {
          name: role,
          identity: {
            InvocationID: role + "-i1"
          },
          startedAt: 3,
          grant: false,
          everSecure: false,
          client: {
            ready: false,
            requested: false,
            secure: false,
            terminal: false
          }
        };
        Object.assign(v.descriptor.units[role].client, state || {});
        v.descriptor.units[role].everSecure = state?.secure === true;
        v.units[role] = {
          sameInvocation: true,
          gone: false
        };
        return v.descriptor.units[role];
      }
      function check(name, v, state, effect, role, confirmed) {
        var result = Lifecycle.decide(v);
        if (result.state !== state || (result.effect?.kind || "") !== (effect || "") || (result.effect?.role || "") !== (role || "") || result.confirmed !== (confirmed === true))
          throw new Error(name + ": " + JSON.stringify(result));
        cases.push(name);
      }
      try {
        var v = fixture();
        check("new-generation", v, "starting", "launch", "real");
        v.now = 30;
        check("no-late-first-launch", v, "fallback", "launch", "emergency");
        v.now = 1;
        unit(v, "real");
        check("duplicate-does-not-launch", v, "starting");
        v.descriptor.units.real.client.ready = true;
        check("prepared-is-not-secure", v, "starting", "grant", "real");
        v.descriptor.units.real.grant = true;
        check("grant-is-not-secure", v, "starting");
        v.now = 3;
        check("inflight-at-three", v, "fallback", "launch", "emergency");
        unit(v, "emergency");
        check("emergency-starting", v, "fallback");
        v.descriptor.units.real.client.secure = true;
        check("fast-real-wins", v, "engaged", "", "", true);
        v.now = 100000;
        check("engaged-never-expires", v, "engaged", "", "", true);
        v = fixture();
        unit(v, "real", {
               ready: true
             });
        unit(v, "emergency", {
               secure: true,
               requested: true
             });
        v.now = 5;
        check("ready-handover", v, "handing-over", "handover", "", true);
        v.takeover = false;
        check("no-restore-retains-emergency", v, "engaged", "stop", "real", true);
        v.takeover = true;
        v.descriptor.units.real.client.ready = false;
        check("slow-preparation-emergency", v, "engaged", "", "", true);
        v.now = 30;
        check("unready-thirty", v, "engaged", "stop", "real", true);
        v.descriptor.units.real.client.ready = true;
        check("ready-exactly-thirty-no-grant", v, "engaged", "stop", "real", true);
        v = fixture();
        unit(v, "real", {
               ready: true
             });
        v.now = 2.9;
        check("ready-before-emergency-deadline", v, "starting", "grant", "real");
        v.now = 29.9;
        check("ready-without-secure-holder-after-emergency-deadline", v, "fallback", "launch", "emergency");
        v.now = 30;
        check("ready-on-deadline", v, "fallback", "stop", "real");
        v.now = 30.1;
        check("ready-after-deadline", v, "fallback", "stop", "real");
        v.descriptor.units.real.grant = true;
        check("escaped-grant-not-killed-blindly", v, "fallback", "launch", "emergency");
        v = fixture();
        unit(v, "real", {
               ready: true
             });
        unit(v, "emergency", {
               secure: false,
               requested: true,
               terminal: true
             });
        v.descriptor.handoverCommitted = true;
        v.descriptor.handoverAt = 5;
        v.now = 5.5;
        check("exit-barrier-before-grant", v, "handing-over");
        v.now = 7;
        check("bounded-handover-exit", v, "handing-over", "stop", "emergency");
        v.units.emergency.gone = true;
        check("grant-only-after-empty", v, "handing-over", "grant", "real");
        v.descriptor.units.real.grant = true;
        v.descriptor.units.real.grantedAt = 7;
        check("handover-grant-awaits-secure", v, "handing-over");
        v.now = 9.9;
        check("handover-grant-acquisition-window", v, "handing-over");
        v.now = 10;
        check("stalled-granted-candidate-retired", v, "handing-over", "stop", "real");
        v.descriptor.units.real.client.secure = true;
        check("secure-granted-candidate-kept", v, "engaged", "", "", true);
        v.descriptor.units.real.client.secure = false;
        v.now = 7;
        v.units.real.gone = true;
        check("granted-client-failure-recovery", v, "fallback", "launch", "emergency");
        v.units.real.gone = false;
        v.descriptor.units.real.grant = false;
        v.now = 30;
        check("handover-misses-original-deadline", v, "handing-over", "stop", "real");
        v = fixture();
        v.realLaunchFailed = true;
        check("failed-exec-immediate-emergency", v, "fallback", "launch", "emergency");
        v = fixture();
        unit(v, "real");
        v.units.real.gone = true;
        check("early-exit-immediate-emergency", v, "fallback", "launch", "emergency");
        v = fixture();
        unit(v, "real", {
               authenticated: true,
               terminal: true,
               locked: false,
               secure: false
             });
        v.units.real.gone = true;
        v.descriptor.phase = "unlocking";
        v.descriptor.authRole = "real";
        check("authenticated-settlement", v, "unlocking", "settle");
        v.descriptor.units.real.client.terminal = false;
        check("crash-is-not-authenticated-teardown", v, "recovering", "recover");
        v.authenticatedUnlockObserved = true;
        check("correlated-unlock-observation", v, "unlocking", "settle");
        v.units.real.gone = false;
        v.descriptor.units.real.client.ready = true;
        check("unlock-fence-revokes-ready", v, "unlocking");
        v.descriptor.phase = "settled";
        check("late-ready-cannot-reopen", v, "unlocked");
        for (var adapter of ["opaque", "contract"]) {
          v = fixture(adapter);
          if (adapter === "opaque") {
            check("opaque-real-launch-before-deadline", v, "starting", "launch", "real");
            v.now = 3;
            // Retryable hook work before the real launch cannot defer the deadline.
            check("opaque-deadline-outranks-unlaunched-real", v, "fallback", "launch", "emergency");
            v.descriptor.probeEvents.deadline = "emergency-i0";
            check("opaque-real-launch-after-deadline-probe", v, "starting", "launch", "real");
            delete v.descriptor.probeEvents.deadline;
            v.now = 1;
            unit(v, "real");
          }
          v.now = 3;
          check(adapter + "-probe-at-deadline", v, "fallback", "launch", "emergency");
          unit(v, "emergency", {
                 requested: true,
                 terminal: true,
                 settlement: "finished"
               });
          v.descriptor.probeEvents.deadline = "emergency-i1";
          v.units.emergency.gone = true;
          v.now = 3.5;
          v.descriptor.units.emergency.client.terminal = false;
          check(adapter + "-probe-exit-without-report-is-unknown", v, "fallback", "launch", "emergency");
          v.descriptor.units.emergency.client.terminal = true;
          check(adapter + "-refusal-is-unconfirmed", v, "engaged-unconfirmed(external)");
          v.lockedHint = true;
          check(adapter + "-hint-is-not-confirmation", v, "engaged-unconfirmed(external)");
          v.now = 4;
          check(adapter + "-no-periodic-retry", v, "engaged-unconfirmed(external)");
          v.now = 40;
          check(adapter + "-unconfirmed-never-expired", v, "engaged-unconfirmed(external)");
          v.descriptor.sleepWindow = 1;
          check(adapter + "-sleep-window-one-probe", v, "fallback", "launch", "emergency");
          if (Lifecycle.decide(v).effect.events.join(",") !== "sleep:1")
            throw new Error("sleep probe event identity lost");
          v.descriptor.probeEvents["sleep:1"] = "emergency-i2";
          check(adapter + "-sleep-window-no-repeat", v, "engaged-unconfirmed(external)");
          v.descriptor.unconfirmedRequests = 1;
          check(adapter + "-request-while-unconfirmed-probes-once", v, "fallback", "launch", "emergency");
          if (Lifecycle.decide(v).effect.events.join(",") !== "request:1")
            throw new Error("request probe event identity lost");
          v.descriptor.probeEvents["request:1"] = "emergency-i2r";
          check(adapter + "-request-probe-no-repeat", v, "engaged-unconfirmed(external)");
          delete v.descriptor.unconfirmedRequests;
          delete v.descriptor.probeEvents["request:1"];
          if (adapter === "opaque") {
            v.units.real.gone = true;
            v.takeover = false;
            check("opaque-exit-without-native-refusal-is-not-unlock", v, "fallback", "launch", "emergency");
            v.descriptor.units.emergency.protocolOutcome = "finished";
            check("opaque-refused-holder-exit-without-takeover-is-unlock", v, "resolving-unlock", "note-unlock");
            v.sessionUnlockObserved = true;
            check("no-takeover-persisted-exit-unlock-settles", v, "unlocking", "settle");
            v.sessionUnlockObserved = false;
            v.descriptor.retiredInvocations = [v.descriptor.units.emergency];
            v.descriptor.units.emergency = {
              identity: {
                InvocationID: "emergency-race"
              },
              client: {
                requested: true
              }
            };
            v.units.emergency = {
              sameInvocation: true,
              gone: false
            };
            check("no-takeover-exit-with-probe-in-flight-notes-unlock", v, "resolving-unlock", "note-unlock");
            v.sessionUnlockObserved = true;
            check("no-takeover-exit-with-probe-in-flight-waits", v, "resolving-probe");
            v.descriptor.units.emergency.client.secure = true;
            check("no-takeover-probe-wins-unlock-race-retained", v, "engaged", "probe-race", "", true);
            v.sessionUnlockObserved = false;
            v.descriptor.probeRaceWon = true;
            check("no-takeover-race-consumed-keeps-secure-probe", v, "engaged", "", "", true);
            delete v.descriptor.probeRaceWon;
            v.descriptor.units.emergency = v.descriptor.retiredInvocations[0];
            delete v.descriptor.retiredInvocations;
            delete v.descriptor.units.emergency.protocolOutcome;
            v.units.emergency.gone = true;
            v.takeover = true;
            check("opaque-candidate-exit-probes-immediately", v, "fallback", "launch", "emergency");
            v.descriptor.probeEvents["exit:real-i1"] = "emergency-i3";
            check("opaque-candidate-exit-no-repeat", v, "engaged-unconfirmed(external)");
            v.units.real.gone = false;
          } else {
            v.contractFailed = true;
            check("contract-failure-event", v, "fallback", "launch", "emergency");
            v.descriptor.probeEvents["contract-failed"] = "emergency-i3";
            check("contract-failure-no-repeat", v, "engaged-unconfirmed(external)");
            v.contractFailed = false;
          }
          v.now = 4;
          v.units.emergency.gone = false;
          v.descriptor.units.emergency.client.terminal = false;
          v.descriptor.units.emergency.client.secure = true;
          check(adapter + "-probe-secure", v, "engaged", adapter === "opaque" ? "stop" : "", adapter === "opaque" ? "real" : "", true);
          v.units.emergency.gone = true;
          v.descriptor.units.emergency.client.terminal = true;
          v.descriptor.units.emergency.client.secure = false;
          v.descriptor.contractSecured = true;
          v.descriptor.contractVersion = 1;
          check(adapter + "-v1-secure-claim-not-confirmation", v, "engaged-unconfirmed(external)");
          v.descriptor.contractVersion = 2;
          if (adapter === "contract") {
            check("contract-v2-secured-confirms", v, "engaged", "", "", true);
            v.contractFailed = true;
            check("contract-v2-owner-loss-withdraws-confirmation", v, "engaged-unconfirmed(external)");
            v.contractFailed = false;
            // A restored secured request is queried before any unseen event
            // can probe; a failed query or unsecured request keeps recovery.
            v.contractPending = true;
            v.descriptor.sleepWindow = 3;
            check("contract-v2-restored-query-defers-probe", v, "reconciling");
            v.contractFailed = true;
            check("contract-v2-failed-query-probes", v, "fallback", "launch", "emergency");
            v.contractFailed = false;
            v.descriptor.contractSecured = false;
            check("contract-v2-unsecured-pending-probes", v, "fallback", "launch", "emergency");
            v.descriptor.contractSecured = true;
            delete v.descriptor.sleepWindow;
            v.contractPending = false;
          } else {
            check("opaque-ignores-contract-secured", v, "engaged-unconfirmed(external)");
          }
          delete v.descriptor.contractSecured;
          delete v.descriptor.contractVersion;
          v.descriptor.units.emergency.everSecure = true;
          check(adapter + "-emergency-crash-is-not-unlock", v, "fallback", "launch", "emergency");
          v.descriptor.units.emergency.everSecure = false;
          v.sessionUnlockObserved = true;
          check(adapter + "-observed-unlock", v, "unlocking", "settle");
          v.descriptor.sleepWindow = 2;
          check(adapter + "-unlock-never-probes-even-with-pending-event", v, "unlocking", "settle");
          v.units.emergency.gone = false;
          v.descriptor.units.emergency.client.terminal = false;
          check(adapter + "-unlock-with-probe-in-flight-waits", v, "resolving-probe");
          v.descriptor.units.emergency.client.secure = true;
          check(adapter + "-probe-wins-unlock-race-retained", v, "engaged", "probe-race", "", true);
        }
        v = fixture();
        unit(v, "real", {
               ready: true
             });
        unit(v, "emergency", {
               secure: true,
               requested: true
             });
        v.now = 5;
        var before = JSON.stringify(v);
        var afterRestart = JSON.parse(before);
        check("restart-retains-original-handover", afterRestart, "handing-over", "handover", "", true);
        if (JSON.stringify(afterRestart) !== before)
          throw new Error("decision mutated generation identity/deadlines");
        console.log("LOCKER_STATE_RESULT " + JSON.stringify(cases));
        Qt.quit();
      } catch (error) {
        console.error(String(error));
        Qt.exit(1);
      }
    }
  }
}
