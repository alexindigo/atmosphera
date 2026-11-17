#!/usr/bin/env python3
"""Characterize dbusqml on an isolated bus before relying on its ordering."""
import argparse
import json
import shutil
from pathlib import Path

from nm_test_support import GuestRun, PrivateBus, SOURCE, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    owner = GuestRun(args.guest_profile, args.work)
    try:
        bus = PrivateBus(owner)
        shell = owner.work / "shell"
        shutil.copytree(SOURCE, shell, ignore=shutil.ignore_patterns(".git", ".envrc"))
        (shell / "shell.qml").write_text((SOURCE / "Scripts/dev/fixtures/nm-protocol.qml").read_text())
        child = owner.launch(["qs", "-p", shell], "protocol-shell", bus.env)
        def state():
            result = run(["qs", "-p", shell, "ipc", "call", "nmProtocol", "state"], env=bus.env, check=False)
            if result.returncode == 0 and result.stdout.strip().startswith("{"):
                return json.loads(result.stdout)
            assert child.poll() is None, "protocol shell exited; read protocol-shell.log"
            return None
        wait_for(lambda: (state() or {}).get("ready"), "proxy seed")
        bus.control("change", path="/org/freedesktop/NetworkManager", iface="org.freedesktop.NetworkManager", props={"Connectivity": 2})
        value = wait_for(lambda: (s if (s := state()) and s["seen"] and s["cache"] == 2 else None), "changed value")
        owner.check("signal-before-library-cache", value["seen"] == [dict(payload=2, cache=4)], state=value)
        owner.check("explicit-properties-watcher", value["explicitSeen"])
        before = bus.control("calls")
        bus.control("change", path="/org/freedesktop/NetworkManager", iface="org.freedesktop.NetworkManager", invalidated=["Connectivity"])
        wait_for(lambda: state()["invalidated"], "invalidation waiter")
        after = bus.control("calls")
        gets = [c for c in after[len(before):] if c.get("property") == "Connectivity"]
        owner.check("duplicate-read-canary-detects-mixed-ownership", len(gets) == 2, calls=gets)
        run(["qs", "-p", shell, "ipc", "call", "nmProtocol", "disableAutomatic"], env=bus.env)
        before = after
        bus.control("change", path="/org/freedesktop/NetworkManager", iface="org.freedesktop.NetworkManager", invalidated=["WirelessEnabled"])
        wait_for(lambda: state()["ownedInvalidated"], "explicit invalidation owner")
        after = bus.control("calls")
        gets = [c for c in after[len(before):] if c.get("property") == "WirelessEnabled"]
        owner.check("one-invalidation-read", len(gets) == 1, calls=gets)
        bus.control("put", path="/org/freedesktop/NetworkManager/NoIntrospection", iface="org.freedesktop.NetworkManager.Connection.Active",
                    props={"State": ["u", 1]}, introspect=False)
        result = run(["gdbus", "introspect", "--address", bus.address, "--dest", "org.freedesktop.NetworkManager", "--object-path", "/org/freedesktop/NetworkManager/NoIntrospection"], env=bus.env, check=False)
        owner.check("child-rejects-introspection", result.returncode != 0, stderr=result.stderr)
        bus.control("signal", path="/org/freedesktop/NetworkManager/NoIntrospection", iface="org.freedesktop.NetworkManager.Connection.Active", member="StateChanged", signature="(uu)", args=[2, 0])
        wait_for(lambda: state()["noIntrospectionSeen"], "non-introspecting child signal")
        owner.check("explicit-child-signal-without-introspection", True)
        run(["qs", "-p", shell, "ipc", "call", "nmProtocol", "stop"], env=bus.env)
        owner.check("normal-fixture-exit", child.wait(timeout=10) == 0)
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        owner.close()


if __name__ == "__main__":
    main()
