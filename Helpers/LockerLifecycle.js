.pragma library

// The lock owner's policy is a pure decision over one reconciled generation.
// Effects are serialized by LockOwnerService; the unit adapter only fences and
// executes them. Global LockedHint is deliberately not an engagement input.
function decision(state, holder, confirmed, kind, role) {
    return {state: state, holder: holder || "", confirmed: confirmed === true,
        effect: kind ? {kind: kind, role: role || ""} : null};
}

function decide(view) {
    var d = view.descriptor;
    if (!d || d.phase === "settled")
        return decision("unlocked");
    var units = d.units || {};
    var observations = view.units || {};
    var real = units.real;
    var emergency = units.emergency;
    function live(role) {
        return !!(units[role] && observations[role] && observations[role].sameInvocation && !observations[role].gone);
    }
    function client(role) { return units[role]?.client || {}; }
    function secure(role) { return live(role) && client(role).secure === true && !client(role).terminal; }
    function effect(state, holder, confirmed, kind, role) { return decision(state, holder, confirmed, kind, role); }
    var realLive = live("real");
    var emergencyLive = live("emergency");
    var bundled = d.snapshot.adapter === "bundled";
    var opaque = !bundled;
    var now = view.now;

    function probeEvents() {
        var seen = d.probeEvents || {};
        var events = [];
        function add(key) { if (key && !seen[key]) events.push(key); }
        if (now >= d.emergencyAt) add("deadline");
        if (real && !realLive) add("exit:" + real.identity.InvocationID);
        if (view.realLaunchFailed) add("launch-failed");
        if (view.contractFailed) add("contract-failed");
        if (d.sleepWindow) add("sleep:" + d.sleepWindow);
        return events;
    }
    function probe(kind, events, state) {
        var result = effect(state || "fallback", "", false, kind, "emergency");
        result.effect.events = events;
        return result;
    }

    if (d.phase === "unlocking") {
        if (!realLive && !emergencyLive) {
            var auth = units[d.authRole]?.client;
            if ((auth && auth.terminal && auth.authenticated && !auth.locked && !auth.secure) || view.authenticatedUnlockObserved)
                return effect("unlocking", "", false, "settle");
            return effect("recovering", "", false, "recover");
        }
        return decision("unlocking");
    }

    if (opaque && view.sessionUnlockObserved) {
        // The external authentication and this probe's protocol connection do
        // not share an atomic boundary. Resolve a request already in flight;
        // never kill a possibly secure probe or launch one due to unlock.
        if (emergencyLive) {
            if (secure("emergency"))
                return effect("engaged", "emergency", true, "probe-race");
            return decision("resolving-probe");
        }
        if (emergency && emergency.everSecure && !client("emergency").authenticated)
            return effect("recovering", "", false, "recover");
        return effect("unlocking", "", false, "settle");
    }

    if (secure("real"))
        return decision("engaged", "real", true);

    if (d.handoverCommitted) {
        if (emergencyLive) {
            if (now >= d.handoverAt + 2)
                return effect("handing-over", "", false, "stop", "emergency");
            return decision("handing-over");
        }
        if (realLive && !real.grant) {
            if (now >= d.deadline)
                return effect("handing-over", "", false, "stop", "real");
            return effect("handing-over", "", false, "grant", "real");
        }
        if (!realLive)
            return effect("fallback", "", false, "launch", "emergency");
        return decision("handing-over");
    }

    if (secure("emergency")) {
        if (realLive) {
            if (opaque || !view.takeover || now >= d.deadline)
                return effect("engaged", "emergency", true, "stop", "real");
            if (client("real").ready && !real.grant)
                return effect("handing-over", "emergency", true, "handover");
        }
        return decision("engaged", "emergency", true);
    }

    if (opaque) {
        // Reserved internal boundary for a future matching-request contract
        // acknowledgement. No D-Bus interface extension is made here.
        if (view.contractAck && view.contractAck.generation === d.generation && view.contractAck.secure === true)
            return decision("engaged", "external", true);
        if (emergency && emergency.everSecure && !emergencyLive && !client("emergency").authenticated)
            return effect("fallback", "", false, "launch", "emergency");
        if (!real && d.snapshot.adapter !== "contract" && !view.realLaunchFailed)
            return effect("starting", "", false, "launch", "real");
        var events = probeEvents();
        if (events.length && emergencyLive && !client("emergency").terminal)
            return probe("cover-probe-events", events);
        if (events.length && !emergencyLive)
            return probe("launch", events);
        var refused = emergency && !emergencyLive && !emergency.everSecure && client("emergency").terminal && client("emergency").requested && client("emergency").settlement === "finished";
        if (refused)
            return decision("engaged-unconfirmed(external)", "external", false);
        return decision(emergencyLive ? "fallback" : "starting");
    }

    if (!real && !view.realLaunchFailed && now < d.deadline)
        return effect("starting", "", false, "launch", "real");
    if (realLive && !real.grant && now >= d.deadline)
        return effect("fallback", "", false, "stop", "real");
    if (!emergencyLive && (view.realLaunchFailed || (real && !realLive) || now >= d.deadline))
        return effect("fallback", "", false, "launch", "emergency");
    if (realLive && client("real").ready && !real.grant && !emergency && now < d.deadline)
        return effect("starting", "", false, "grant", "real");
    if (now >= d.emergencyAt && !emergencyLive && (!emergency || now >= emergency.startedAt + 1))
        return effect("fallback", "", false, "launch", "emergency");
    return decision(emergency ? "fallback" : "starting");
}
