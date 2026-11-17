#!/usr/bin/env python3
"""Retain a complete real-shell system-bus idle capture, with attribution canaries."""
import argparse
import json
from pathlib import Path
import re
import os
import signal
import subprocess
import sys
import time

from nm_live_support import LiveShell, SignalLog, finish_run
from nm_test_support import GuestRun, run, wait_for
from guest_profile import ProcessIdentity


HEADER = re.compile(r"^(method call|signal|method return|error) time=([0-9.]+) sender=(\S+) -> destination=(.*?)(?: serial=| error_name=|$)(.*)$")


def messages(text):
    rows = []
    for line in text.splitlines():
        if line.startswith(("method call ", "signal ", "method return ", "error ")):
            match = HEADER.match(line)
            assert match, "unparsed D-Bus header: " + line
            kind, timestamp, sender, destination, suffix = match.groups()
            member = re.search(r"(?:^|[; ])member=([^; ]+)", suffix)
            rows.append(dict(kind=kind, time=float(timestamp), sender=sender, destination=destination,
                             member=member[1] if member else "", raw=line))
        elif rows:
            rows[-1]["raw"] += "\n" + line
    return rows


def classify(rows, senders, destinations):
    methods = [r for r in rows if r["kind"] == "method call" and r["sender"] in senders]
    return dict(nmCalls=[r for r in methods if r["destination"] in destinations],
                setupChurn=[r for r in methods if r["member"] in ("AddMatch", "RemoveMatch", "Introspect")])


def owned_name_changes(rows, names):
    return [r for r in rows if r["member"] == "NameOwnerChanged"
            and set(re.findall(r'^\s+string "([^"]+)"$', r["raw"], re.MULTILINE)).intersection(names)]


def parser_canaries():
    sample = "\n".join([
        "method call time=1.100 sender=:1.42 -> destination=org.freedesktop.NetworkManager serial=1 path=/nm; interface=nm; member=GetAll",
        "method call time=1.200 sender=:1.43 -> destination=:1.7 serial=2 path=/nm; interface=nm; member=GetSettings",
        "method call time=1.300 sender=:1.42 -> destination=org.freedesktop.DBus serial=3 path=/bus; interface=bus; member=AddMatch",
        "method call time=1.400 sender=:1.42 -> destination=:1.7 serial=4 path=/nm; interface=nm; member=Introspect",
        "method call time=1.500 sender=:1.99 -> destination=org.freedesktop.NetworkManager serial=5 path=/nm; interface=nm; member=GetAll",
        "signal time=1.600 sender=:1.7 -> destination=(null destination) serial=6 path=/nm; interface=nm; member=PropertiesChanged"])
    rows = messages(sample)
    result = classify(rows, {":1.42", ":1.43"}, {"org.freedesktop.NetworkManager", ":1.7"})
    assert len(result["nmCalls"]) == 3 and len(result["setupChurn"]) == 2
    assert not any(classify(rows, {":1.100"}, {":1.7"}).values())
    changes = messages('signal time=2.0 sender=org.freedesktop.DBus -> destination=(null destination) serial=7 path=/bus; interface=bus; member=NameOwnerChanged\n'
                       '   string ":1.420"\n   string ""\n   string ":1.420"\n'
                       'signal time=3.0 sender=org.freedesktop.DBus -> destination=(null destination) serial=8 path=/bus; interface=bus; member=NameOwnerChanged\n'
                       '   string ":1.43"\n   string ":1.43"\n   string ""\n')
    assert len(owned_name_changes(changes, {":1.42", ":1.43"})) == 1
    assert not owned_name_changes(changes, {":1.42"}), "unique-name prefixes are not identities"
    try:
        messages("method call truncated")
    except AssertionError:
        return True
    raise AssertionError("malformed-capture canary was not rejected")


def system_names(pid):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    def call(member, parameters=None):
        return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                             member, parameters, None, Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
    names = call("ListNames")
    found = []
    membership = []
    for name in names:
        if not name.startswith(":"):
            continue
        try:
            actual = call("GetConnectionUnixProcessID", GLib.Variant("(s)", (name,)))
        except GLib.Error:
            continue  # Unrelated finite CLI processes can depart during inventory.
        membership.append(dict(name=name, pid=actual))
        if actual == pid:
            found.append(name)
    nm = call("GetNameOwner", GLib.Variant("(s)", ("org.freedesktop.NetworkManager",)))
    assert found, "no shell system-bus connection resolved by PID"
    return dict(shellNames=sorted(found), nmOwner=nm, membership=membership, monotonic=time.monotonic())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=600)
    args = parser.parse_args()
    assert args.seconds >= 600, "full ten-minute wire proof required"
    owner = GuestRun(args.guest_profile, args.work)
    shell = tracker = None
    try:
        owner.check("wire-parser-positive-negative-canaries", parser_canaries())
        monitor = owner.launch([sys.executable, "-B", __file__, "--monitor-child", str(args.seconds + 120)], "system-bus")
        log = owner.work / "system-bus.log"
        wait_for(lambda: "NameAcquired" in log.read_text(), "dbus-monitor installed matches", seconds=10)
        tracker = SignalLog(owner, track_names=True)
        shell = LiveShell(owner)
        # Allow independent services' startup, native property seeds and scans to
        # finish. No test NM reads occur inside the measured interval.
        time.sleep(15)
        before = system_names(shell.process.pid)
        start_offset = log.stat().st_size
        start = time.monotonic()
        owner.receipt["capture"] = dict(before=before, start=start, startOffset=start_offset, requestedSeconds=args.seconds)
        owner.write()
        deadline = start + args.seconds
        while time.monotonic() < deadline:
            assert monitor.poll() is None and shell.process.poll() is None, "capture/shell terminated early"
            time.sleep(min(1, max(0, deadline - time.monotonic())))
        end = time.monotonic()
        end_offset = log.stat().st_size
        after = system_names(shell.process.pid)
        identity = shell.state()
        measured = log.read_bytes()[start_offset:end_offset].decode()
        (owner.work / "measured-system-bus.log").write_text(measured)
        rows = messages(measured)
        membership = [e for e in tracker.name_owners if start <= e["monotonic"] <= end]
        owner.receipt["dynamicNameMembership"] = membership
        new_shell_names = [e for e in membership if e.get("pid") == shell.process.pid]
        unresolved = [e for e in membership if e.get("new") and "pid" not in e]
        owner.check("no-unresolved-or-missed-shell-bus-names", not new_shell_names and not unresolved,
                    newShellNames=new_shell_names, unresolved=unresolved)
        startup = messages(log.read_bytes()[:start_offset].decode())
        initial = classify(startup, set(before["shellNames"]), {"org.freedesktop.NetworkManager", before["nmOwner"]})
        owner.check("capture-observes-shell-seed-not-just-empty-grep", any(r["member"] == "ListConnections" for r in initial["nmCalls"]),
                    seedCalls=initial["nmCalls"])
        owner.check("full-600-second-capture", end - start >= args.seconds and monitor.poll() is None,
                    start=start, end=end, seconds=end - start, startOffset=start_offset, endOffset=end_offset)
        owner.check("complete-stable-pid-name-and-owner-membership", before["shellNames"] == after["shellNames"] and before["nmOwner"] == after["nmOwner"],
                    before=before, after=after)
        # A shell connection may not disappear/reappear unnoticed: retain and
        # reject its NameOwnerChanged record even if inventories happen to match.
        relevant = owned_name_changes(rows, set(before["shellNames"]))
        owner.check("no-shell-name-capture-gap", not relevant, records=relevant)
        nm_signals = [r for r in rows if r["kind"] == "signal" and r["sender"] == before["nmOwner"]]
        owner.check("stable-idle-no-external-nm-change", not nm_signals, signals=nm_signals)
        result = classify(rows, set(before["shellNames"]), {"org.freedesktop.NetworkManager", before["nmOwner"]})
        owner.check("zero-shell-to-nm-methods", not result["nmCalls"], calls=result["nmCalls"])
        owner.check("zero-shell-setup-churn", not result["setupChurn"], calls=result["setupChurn"])
        owner.check("unchanged-shell-pid-start", identity["pid"] == shell.identity.pid)
        owner.receipt["capture"]["after"] = after
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        finish_run(owner, shell, tracker)


def monitor_child(seconds):
    # The normal owned-process guard intentionally refuses root children. Keep
    # its tester-owned relay and explicitly pin/join the privileged capture.
    process = subprocess.Popen(["sudo", "-n", "timeout", "--signal=INT", str(seconds), "dbus-monitor", "--system",
                                "type='method_call'", "type='signal',sender='org.freedesktop.NetworkManager'",
                                "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'"], start_new_session=True)
    expected = ProcessIdentity.read(process.pid)
    def stop(signum, frame):
        if process.poll() is None:
            current = ProcessIdentity.read(process.pid)
            assert (current.pid, current.start, current.pgid) == (expected.pid, expected.start, expected.pgid)
            run(["sudo", "-n", "kill", "-INT", "--", "-" + str(expected.pgid)], check=False)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        return process.wait(timeout=seconds + 10)
    finally:
        if process.poll() is None:
            stop(None, None)
            process.wait(timeout=8)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--monitor-child":
        sys.exit(monitor_child(int(sys.argv[2])))
    main()
