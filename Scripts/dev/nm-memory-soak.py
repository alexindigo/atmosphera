#!/usr/bin/env python3
"""Sample one real shell across a full hour idle, then safe NM profile cycles."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import signal
import sys
import time

from nm_live_support import LiveProfiles, LiveShell, SignalLog, finish_run
from nm_test_support import GuestRun, NmInterruptedError, SOURCE, analysis_canaries, analyze, parse_smaps, wait_for


def renewal_options(event, sender, path, previous):
    """Only a signal advancing lease expiry, not any other DHCP/network fact."""
    if (event.get("sender"), event.get("path"), event.get("iface"), event.get("member")) != (
            sender, path, "org.freedesktop.DBus.Properties", "PropertiesChanged"):
        return None
    args = event.get("args", [])
    if len(args) != 3 or args[0] != "org.freedesktop.NetworkManager.DHCP4Config" or args[2] or set(args[1]) != {"Options"}:
        return None
    options = args[1]["Options"]
    if not isinstance(options, dict) or set(options) != set(previous):
        return None
    if {k: v for k, v in options.items() if k != "expiry"} != {k: v for k, v in previous.items() if k != "expiry"}:
        return None
    try:
        return options if int(options["expiry"]) > int(previous["expiry"]) else None
    except (KeyError, TypeError, ValueError):
        return None


def renewal_canaries():
    import copy
    old = dict(expiry="100", ip_address="192.0.2.2", routers="192.0.2.1", domain_name_servers="192.0.2.1", dhcp_lease_time="3600")
    event = dict(sender=":1.3", path="/dhcp/1", iface="org.freedesktop.DBus.Properties", member="PropertiesChanged",
                 args=["org.freedesktop.NetworkManager.DHCP4Config", {"Options": dict(old, expiry="1900")}, []])
    assert renewal_options(event, ":1.3", "/dhcp/1", old)
    bad = [dict(event, sender=":1.4"), dict(event, path="/dhcp/2"), dict(event, member="Other")]
    for field in ("ip_address", "routers", "domain_name_servers", "dhcp_lease_time", "expiry"):
        changed = copy.deepcopy(event)
        changed["args"][1]["Options"][field] = "99" if field == "expiry" else "different"
        bad.append(changed)
    for index, value in ((0, "org.freedesktop.NetworkManager.IP4Config"), (2, ["Options"])):
        changed = copy.deepcopy(event)
        changed["args"][index] = value
        bad.append(changed)
    changed = copy.deepcopy(event)
    changed["args"][1]["Other"] = 1
    bad.append(changed)
    changed = copy.deepcopy(event)
    del changed["args"][1]["Options"]["routers"]
    bad.append(changed)
    assert all(renewal_options(e, ":1.3", "/dhcp/1", old) is None for e in bad)
    return len(bad) + 1


def network_facts(observed):
    return {key: observed[key] for key in ("available", "epoch", "owner", "counts", "profiles", "active", "devices",
                                         "operations", "vpn", "connecting", "disconnecting", "error")}


def stop_capture(monitor):
    """Join the relay and its pinned privileged child before key-bearing calls."""
    assert monitor.poll() is None, "capture terminated before explicit teardown"
    monitor.send_signal(signal.SIGTERM)
    monitor.wait(timeout=15)
    assert monitor.poll() is not None, "capture not joined"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--idle-seconds", type=int, default=3600)
    parser.add_argument("--cycles", type=int, default=30)
    parser.add_argument("--interval", type=float, default=30)
    args = parser.parse_args()
    assert args.idle_seconds >= 3600 and args.cycles >= 30 and args.interval > 0, "preserve full plan measurement"
    owner = GuestRun(args.guest_profile, args.work)
    lock = (owner.profile.workspace / "nm-memory.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    shell = profiles = signals = None
    samples = []
    state = dict(phase="starting", completedCycles=0, targetCycles=args.cycles,
                 idleTargetSeconds=args.idle_seconds, interval=args.interval, runnerPid=os.getpid())
    renewals = []
    owner.receipt["contract"] = dict(argv=sys.argv, idleSeconds=args.idle_seconds,
                                     cycles=args.cycles, interval=args.interval,
                                     collectorSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    owner.write()
    def status():
        state["heartbeatMonotonic"] = time.monotonic()
        temporary = owner.work / "status.pending"
        temporary.write_text(json.dumps(state, indent=2) + "\n")
        temporary.replace(owner.work / "status.json")
    def stop(signum, frame):
        raise NmInterruptedError("soak interrupted: " + str(signum))
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    def sample(phase):
        assert signals.thread.is_alive() and not signals.failure, "NM signal observer failed"
        observed = shell.state()
        assert observed["available"] and (observed["epoch"], observed["owner"]) == state["nmIdentity"], "NM owner changed during soak"
        memory = parse_smaps((Path("/proc") / str(shell.process.pid) / "smaps_rollup").read_text())
        value = dict(monotonic=time.monotonic(), phase=phase, **memory,
                      shellPid=shell.process.pid, shellStart=shell.identity.start,
                      counts=observed["counts"], operations=observed["operations"])
        previous_time = samples[-1]["monotonic"] if samples else value["monotonic"]
        value["nmSignalsSincePreviousSample"] = [dict(e, wallUnix=e["monotonic"] + time.time() - time.monotonic())
                                                for e in signals.events if previous_time < e["monotonic"] <= value["monotonic"]]
        samples.append(value)
        with (owner.work / "memory.jsonl").open("a") as output:
            output.write(json.dumps(value) + "\n")
        state["sampleCount"] = len(samples)
        state["lastSample"] = value
        status()
    def report(name):
        result = analyze(samples)
        metrics = result["metrics"]
        result["completedCycles"] = state["completedCycles"]
        result["dhcpRenewals"] = renewals
        result["allPhaseSampleCount"] = len(samples)
        result["allPhaseMetrics"] = {
            field: dict(minKiB=min(s[field] for s in samples), maxKiB=max(s[field] for s in samples),
                        initialKiB=samples[0][field], finalKiB=samples[-1][field],
                        finalDeltaKiB=samples[-1][field] - samples[0][field])
            for field in ("Pss_Anon", "SwapPss")}
        result["idleTrend"] = "positive measured slope" if metrics["Pss_Anon"]["slopeKiBPerHour"] > 0 else "non-positive measured slope"
        (owner.work / (name + ".json")).write_text(json.dumps(result, indent=2) + "\n")
        (owner.work / (name + ".md")).write_text(
            "# NM memory observation\n\n"
            f"Idle: {result['idleSeconds']:.1f} seconds, {result['sampleCount']} samples. "
            f"Cycles: {state['completedCycles']}/{args.cycles}.\n\n"
            f"Retained expiry-only DHCP renewals: {len(renewals)}.\n\n"
            f"Pss_Anon: {metrics['Pss_Anon']['minKiB'] / 1024:.2f}-"
            f"{metrics['Pss_Anon']['maxKiB'] / 1024:.2f} MiB; "
            f"slope {metrics['Pss_Anon']['slopeKiBPerHour'] / 1024:.2f} MiB/hour.\n\n"
            f"SwapPss: {metrics['SwapPss']['minKiB'] / 1024:.2f}-"
            f"{metrics['SwapPss']['maxKiB'] / 1024:.2f} MiB. "
            f"Historical +/-20 MiB comparison: {result['historicalPlusMinus20MiB']}.\n\n"
            f"Idle trend: {result['idleTrend']}; an envelope comparison alone does not establish flat memory.\n\n"
            f"All phases: {len(samples)} samples; final Pss_Anon change "
            f"{result['allPhaseMetrics']['Pss_Anon']['finalDeltaKiB'] / 1024:.2f} MiB; "
            f"final SwapPss change {result['allPhaseMetrics']['SwapPss']['finalDeltaKiB'] / 1024:.2f} MiB.\n\n"
            f"Analysis cost: {result['analysisSeconds']:.6f} seconds. "
            "This is not 24-hour stability and does not attribute whole-shell memory to NM.\n")
        state["analysis"] = result
        status()
        return result
    try:
        owner.check("full-scale-analysis-positive-negative-canaries", bool(analysis_canaries()))
        owner.check("dhcp-renewal-positive-negative-canaries", renewal_canaries() == 13)
        wire = runpy.run_path(str(SOURCE / "Scripts/dev/nm-idle-wire.py"))
        owner.check("wire-parser-positive-negative-canaries", wire["parser_canaries"]())
        monitor = owner.launch([sys.executable, "-B", SOURCE / "Scripts/dev/nm-idle-wire.py", "--monitor-child",
                                str(args.idle_seconds + 600)], "system-bus")
        log = owner.work / "system-bus.log"
        wait_for(lambda: "NameAcquired" in log.read_text(), "memory wire monitor ready", seconds=10)
        signals = SignalLog(owner, track_names=True)
        profiles = LiveProfiles(owner)
        shell = LiveShell(owner)
        state["shellIdentity"] = shell.identity.record()
        state["phase"] = "warmup"
        status()
        time.sleep(60)
        baseline = shell.state()["counts"]
        state["baselineCounts"] = baseline
        observed = shell.state()
        state["nmIdentity"] = (observed["epoch"], observed["owner"])
        facts = network_facts(observed)
        network = profiles.network()
        before = wire["system_names"](shell.process.pid)
        from gi.repository import Gio, GLib
        def property_value(path, interface, name):
            return signals.bus.call_sync("org.freedesktop.NetworkManager", path, "org.freedesktop.DBus.Properties", "Get",
                                         GLib.Variant("(ss)", (interface, name)), None, Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
        management = next(d for d in observed["devices"].values() if d["ifname"] == "enp1s0")
        dhcp_path = property_value(management["path"], "org.freedesktop.NetworkManager.Device", "Dhcp4Config")
        options = property_value(dhcp_path, "org.freedesktop.NetworkManager.DHCP4Config", "Options")
        owner.receipt["idleBaseline"] = dict(facts=facts, network=network, dhcpPath=dhcp_path, dhcpOptions=options, bus=before)
        owner.write()
        start_offset = log.stat().st_size
        state["phase"] = "idle"
        sample("idle")
        begin = samples[-1]["monotonic"]
        wall_offset = time.time() - time.monotonic()
        event_index = len(signals.events)
        interim = False
        next_sample = begin + args.interval
        while samples[-1]["monotonic"] - begin < args.idle_seconds:
            time.sleep(max(0, next_sample - time.monotonic()))
            assert monitor.poll() is None, "memory wire capture terminated early"
            sample("idle")
            next_sample += args.interval
            if not interim and samples[-1]["monotonic"] - begin >= 600:
                report("interim-report")
                interim = True
            changes = []
            pending = signals.events[event_index:]
            event_index += len(pending)
            for event in pending:
                updated = renewal_options(event, before["nmOwner"], dhcp_path, options)
                if updated is None:
                    changes.append(event)
                    continue
                assert profiles.network() == network, "DHCP renewal changed management address/routes/DNS/state"
                assert network_facts(shell.state()) == facts, "DHCP renewal changed other published network facts"
                options = updated
                renewal = dict(event=event, wallUnix=event["monotonic"] + wall_offset,
                               previousSample=samples[-2]["monotonic"], nextSample=samples[-1]["monotonic"],
                               sampleIndex=len(samples) - 1, counts=samples[-1]["counts"], requiredShellNmCalls=0)
                renewals.append(renewal)
                with (owner.work / "dhcp-renewals.jsonl").open("a") as output:
                    output.write(json.dumps(renewal) + "\n")
            samples[-1]["dhcpRenewalCount"] = len(renewals)
            state["dhcpRenewalCount"] = len(renewals)
            assert network_facts(shell.state()) == facts, "other network facts changed during idle"
            assert not changes, "NM transition interrupted idle; retain nm-signals.jsonl and classify"
            assert samples[-1]["counts"] == baseline, "NM record counts changed during idle; preserve and classify"
            assert samples[-1]["operations"] == 0, "NM operation remained busy during idle"
        owner.check("full-hour-uninterrupted-idle", samples[-1]["monotonic"] - begin >= args.idle_seconds and interim)
        end = time.monotonic()
        end_offset = log.stat().st_size
        after = wire["system_names"](shell.process.pid)
        rows = wire["messages"](log.read_bytes()[start_offset:end_offset].decode())
        (owner.work / "measured-system-bus.log").write_bytes(log.read_bytes()[start_offset:end_offset])
        result = wire["classify"](rows, set(before["shellNames"]), {"org.freedesktop.NetworkManager", before["nmOwner"]})
        membership = [e for e in signals.name_owners if begin <= e["monotonic"] <= end]
        unresolved = [e for e in membership if e.get("new") and "pid" not in e]
        new_shell = [e for e in membership if e.get("pid") == shell.process.pid]
        startup = wire["classify"](wire["messages"](log.read_bytes()[:start_offset].decode()), set(before["shellNames"]),
                                   {"org.freedesktop.NetworkManager", before["nmOwner"]})
        owner.check("wire-observed-seed-and-continuous-shell-membership", monitor.poll() is None
                    and any(r["member"] == "ListConnections" for r in startup["nmCalls"])
                    and before["shellNames"] == after["shellNames"] and before["nmOwner"] == after["nmOwner"]
                    and not wire["owned_name_changes"](rows, set(before["shellNames"])) and not unresolved and not new_shell,
                    before=before, after=after, unresolved=unresolved, newShellNames=new_shell)
        owner.check("zero-idle-and-renewal-shell-nm-calls-or-setup-churn", not result["nmCalls"] and not result["setupChurn"], **result)
        raw_signals = [r for r in rows if r["kind"] == "signal" and r["sender"] == before["nmOwner"]]
        owner.check("all-raw-idle-nm-signals-accounted-as-expiry-only-renewals", len(raw_signals) == len(renewals),
                    rawSignalCount=len(raw_signals), renewalCount=len(renewals))
        owner.check("renewals-have-no-record-growth-or-other-network-changes", shell.state()["counts"] == baseline
                    and network_facts(shell.state()) == facts and profiles.network() == network, renewals=renewals)
        # The broad monitor must not see nmcli's later private-key marshalling.
        # Its relay waits for the pinned root monitor, so this joins both owners.
        stop_capture(monitor)
        owner.check("idle-capture-joined-before-any-profile-key-command", monitor.poll() is not None)
        state["phase"] = "cycles"
        status()
        for index in range(args.cycles):
            identity = profiles.add()
            wait_for(lambda: identity in shell.state()["vpn"], "cycle add")
            profiles.command("connection", "up", "uuid", identity)
            wait_for(lambda: shell.state()["vpn"][identity]["active"], "cycle observed up")
            profiles.command("connection", "down", "uuid", identity)
            wait_for(lambda: not shell.state()["vpn"][identity]["active"], "cycle observed down")
            profiles.delete(identity)
            wait_for(lambda: shell.state()["counts"] == baseline, "all cycle records retired")
            state["completedCycles"] = index + 1
            sample("cycles")
        state["phase"] = "settling"
        status()
        time.sleep(30)
        sample("settled")
        result = report("final-report")
        owner.check("thirty-complete-cycles-baseline-records", state["completedCycles"] == args.cycles and shell.state()["counts"] == baseline)
        owner.check("same-shell-pid-start-throughout", len({(s["shellPid"], s["shellStart"]) for s in samples}) == 1)
        errors = [line for line in (owner.work / "live-shell.log").read_text().splitlines()
                  if re.search(r"TypeError|ReferenceError|binding loop", line, re.I)
                  and 'QML XdgIcon at @Services/System/HostService.qml[29:3]: Binding loop detected for property "name":' not in line]
        owner.check("no-new-runtime-exceptions-or-binding-loops", not errors, errors=errors)
        # Preserve the numerical finding even when it falls outside the historic
        # envelope; liveness alone can never turn that result into a pass.
        owner.check("short-run-historical-envelope-comparison", result["historicalPlusMinus20MiB"], analysis=result)
        state["phase"] = "complete"
    except BaseException as error:
        state["phase"] = "failed"
        state["error"] = repr(error)
        owner.receipt["error"] = repr(error)
        raise
    finally:
        try:
            finish_run(owner, profiles, shell, signals)
        finally:
            status()
            lock.close()


if __name__ == "__main__":
    main()
