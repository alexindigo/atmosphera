#!/usr/bin/env python3
"""Production NM records against a private controlled protocol service."""
import argparse
import json
import re
import shutil
from pathlib import Path

from nm_test_support import GuestRun, PrivateBus, SOURCE, run, wait_for
from qml_probe import bootstrap_fixture

NM = "org.freedesktop.NetworkManager"
ROOT = "/org/freedesktop/NetworkManager"
PROFILE = ROOT + "/Settings/1"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    owner = GuestRun(args.guest_profile, args.work)
    try:
        bus = PrivateBus(owner)
        second_profile = ROOT + "/Settings/2"
        removed_profile = ROOT + "/Settings/3"
        bus.control("put", path=removed_profile, iface=NM + ".Settings.Connection", settings={"connection": {"uuid": "removed-before-seed", "id": "Removed", "type": "vpn"}})
        bus.control("delay", path=ROOT + "/Settings", method="ListConnections")
        shell = owner.work / "shell"
        shutil.copytree(SOURCE, shell, ignore=shutil.ignore_patterns(".git", ".envrc"))
        (shell / "shell.qml").write_text(bootstrap_fixture((SOURCE / "Scripts/dev/fixtures/nm-backend.qml").read_text()))
        child = owner.launch(["qs", "-p", shell], "backend-shell", bus.env)
        def ipc(method, *values):
            return run(["qs", "-p", shell, "ipc", "call", "nmBackend", method, *values], env=bus.env)
        def state():
            result = run(["qs", "-p", shell, "ipc", "call", "nmBackend", "state"], env=bus.env, check=False)
            (owner.work / "latest-ipc.json").write_text(json.dumps(dict(rc=result.returncode, stdout=result.stdout, stderr=result.stderr)))
            if result.stdout.strip().startswith("{"):
                return json.loads(result.stdout)
            assert child.poll() is None, "backend shell exited; read backend-shell.log"
            return {}
        def until(predicate, description):
            return wait_for(lambda: (s if predicate(s := state()) else None), description, seconds=60)
        def profile(name, kind="wireguard", ssid=None):
            settings = {"connection": {"uuid": "fixture-uuid", "id": name, "type": kind}}
            if ssid:
                settings["802-11-wireless"] = {"ssid": list(ssid.encode())}
            return settings
        def calls(member, path=None):
            return [c for c in bus.control("calls") if c["method"] == member and (path is None or c["path"] == path)]
        until(lambda s: s.get("available"), "backend attaches to owner")
        wait_for(lambda: calls("ListConnections"), "held initial enumeration", seconds=60)
        bus.control("put", path=second_profile, iface=NM + ".Settings.Connection", settings={"connection": {"uuid": "added-during-seed", "id": "Added", "type": "vpn"}})
        bus.control("signal", path=ROOT + "/Settings", iface=NM + ".Settings", member="NewConnection", signature="(o)", args=[second_profile])
        bus.control("remove", path=removed_profile)
        bus.control("release")
        initial = until(lambda s: s.get("profiles", {}).get(PROFILE, {}).get("id") == "Initial", "initial profile seed")
        owner.check("owner-and-one-initial-enumeration", initial["available"] and len(calls("ListConnections")) == 1, state=initial)
        owner.check("initial-profile-reaches-vpn-facade", initial["vpn"]["fixture-uuid"]["name"] == "Initial")
        until(lambda s: second_profile in s["profiles"], "add survives seed reply")
        owner.check("subscribe-before-seed-membership-tombstones", removed_profile not in state()["profiles"] and not calls("GetSettings", removed_profile))
        bus.control("signal", path=ROOT + "/Settings", iface=NM + ".Settings", member="NewConnection", signature="(o)", args=[second_profile])
        owner.check("duplicate-add-keeps-one-profile-record", len(calls("GetSettings", second_profile)) == 1)
        deletion = ipc("forget", second_profile).stdout.strip()
        until(lambda s: any(o["id"] == deletion and o["status"] == "completed" for o in s["operations"]), "Delete removal before reply")
        owner.check("delete-removal-before-reply-settles-once", len([o for o in state()["operations"] if o["id"] == deletion and o["status"] != "accepted"]) == 1)
        bus.control("settings", path=PROFILE, settings=profile("Edited"))
        until(lambda s: s["profiles"].get(PROFILE, {}).get("id") == "Edited", "profile Updated")
        owner.check("targeted-profile-update", len(calls("ListConnections")) == 1)
        bus.control("settings", path=PROFILE, settings=profile("Wi-Fi", "802-11-wireless", "Fixture"))
        until(lambda s: s["profiles"].get(PROFILE, {}).get("ssid") == "Fixture", "all-profile type/SSID update")
        until(lambda s: "fixture-uuid" not in s["vpn"] and s["network"]["profiles"].get("Fixture"), "type edit reaches both facades")
        bus.control("settings", path=PROFILE, settings=profile("VPN again"))
        until(lambda s: s["profiles"].get(PROFILE, {}).get("type") == "wireguard", "non-VPN back to VPN")
        owner.check("all-profile-edits-and-type-changes", True)
        bus.control("delay", path=PROFILE, method="GetSettings")
        before = len(calls("GetSettings", PROFILE))
        bus.control("settings", path=PROFILE, settings=profile("Stale in-flight"))
        wait_for(lambda: len(calls("GetSettings", PROFILE)) > before, "held GetSettings")
        for name in ("Burst 1", "Burst 2", "Burst final"):
            bus.control("settings", path=PROFILE, settings=profile(name))
        bus.control("release")
        until(lambda s: s["profiles"].get(PROFILE, {}).get("id") == "Burst final", "final Updated survives coalescing")
        owner.check("updated-burst-final-edit", len(calls("GetSettings", PROFILE)) == before + 2)
        bus.control("configure", activation="success", activationReply="hold")
        operation = ipc("activate", PROFILE).stdout.strip()
        until(lambda s: any(a.get("State") == 2 for a in s.get("active", {}).values()), "signal before acceptance")
        owner.check("no-terminal-success-before-acceptance", not any(o["id"] == operation and o["status"] == "completed" for o in state()["operations"]))
        bus.control("release")
        until(lambda s: any(o["id"] == operation and o["status"] == "completed" for o in s["operations"]), "accepted observed activation")
        owner.check("activation-signal-reply-reversal", True)
        second = ipc("activate", PROFILE).stdout.strip()
        until(lambda s: len(s["active"]) == 2, "duplicate active UUID paths")
        bus.control("release")
        until(lambda s: any(o["id"] == second and o["status"] == "completed" for o in s["operations"]), "second active completion")
        owner.check("duplicate-active-uuid-not-collapsed", len(state()["active"]) == 2)
        operation = ipc("deactivate", "fixture-uuid").stdout.strip()
        until(lambda s: any(o["id"] == operation and o["status"] == "completed" for o in s["operations"]), "all active paths deactivated")
        owner.check("deactivation-observed-all-instances", not state()["active"])
        bus.control("configure", activation="failure", activationReply="normal")
        operation = ipc("activate", PROFILE).stdout.strip()
        until(lambda s: any(o["id"] == operation and o["status"] == "error" for o in s["operations"]), "accepted then failed")
        terminal = [o for o in state()["operations"] if o["id"] == operation and o["status"] != "accepted"]
        owner.check("accepted-then-failed-once", len(terminal) == 1 and not terminal[0]["ok"], results=terminal)
        bus.control("configure", activation="pending", activationReply="normal")
        ipc("vpnConnect", "fixture-uuid")
        pending = until(lambda s: s["vpnConnecting"] and any(a.get("State") == 1 for a in s["active"].values()), "facade remains busy after accepted request")
        failed_path = next(path for path, a in pending["active"].items() if a.get("State") == 1)
        owner.check("request-acceptance-is-not-connected", not pending["vpn"]["fixture-uuid"]["active"])
        bus.control("signal", path=failed_path, iface=NM + ".Connection.Active", member="StateChanged", signature="(uu)", args=[4, 7])
        until(lambda s: not s["vpnConnecting"] and bool(s["vpnError"]), "terminal StateChanged clears facade busy")
        owner.check("facade-accepted-then-failed-statechanged", not state()["vpn"]["fixture-uuid"]["active"])
        # One shared AP/IP graph, driven through real dbusqml Properties and
        # Wireless signals. These are controlled radio facts, not hardware proof.
        device, other = ROOT + "/Devices/10", ROOT + "/Devices/11"
        ap, spare, ip4 = ROOT + "/AccessPoint/1", ROOT + "/AccessPoint/2", ROOT + "/IP4Config/1"
        for path, ssid in ((ap, "Fixture"), (spare, "Other")):
            bus.control("put", path=path, iface=NM + ".AccessPoint", introspect=False,
                        props={"Ssid": ["ay", list(ssid.encode())], "Strength": ["y", 50], "Frequency": ["u", 5180], "Bandwidth": ["u", 80],
                               "Flags": ["u", 1], "WpaFlags": ["u", 0], "RsnFlags": ["u", 0x100]})
        bus.control("put", path=ip4, iface=NM + ".IP4Config", introspect=False,
                    props={"AddressData": ["aa{sv}", [{"address": "198.18.0.4", "prefix": 24}]], "Gateway": ["s", "198.18.0.1"],
                           "NameserverData": ["aa{sv}", [{"address": "198.18.0.53"}]]})
        for path in (device, other):
            bus.control("put", path=path, iface=NM + ".Device", props={"Interface": ["s", "fixture" + path.rsplit("/", 1)[1]], "DeviceType": ["u", 2],
                        "State": ["u", 100], "HwAddress": ["s", "02:00:00:00:00:01"], "ActiveConnection": ["o", "/"], "Ip4Config": ["o", ip4], "Ip6Config": ["o", "/"]})
            bus.control("put", path=path, iface=NM + ".Device.Wireless", props={"Bitrate": ["u", 54000], "ActiveAccessPoint": ["o", ap],
                        "AccessPoints": ["ao", [ap, spare]], "LastScan": ["x", 100]})
        bus.control("change", path=ROOT, iface=NM, props={"Devices": [device, other], "ActiveConnections": []})
        until(lambda s: s["devices"].get(device, {}).get("ipv4") == "198.18.0.4" and s["devices"][device]["wifiSignal"] == "50", "linked AP/IP facts")
        owner.check("shared-records-no-duplicate-proxies", state()["counts"]["accessPoints"] == 2 and state()["counts"]["ipConfigs"] == 1
                    and len(calls("GetAll", ip4)) == 1 and len(calls("GetAll", ap)) == 1)
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Strength": 77, "Frequency": 5955})
        bus.control("change", path=ip4, iface=NM + ".IP4Config", props={"AddressData": [{"address": "198.18.0.5", "prefix": 24}], "Gateway": "198.18.0.2", "NameserverData": [{"address": "198.18.0.54"}]})
        until(lambda s: all(d["ipv4"] == "198.18.0.5" and d["wifiSignal"] == "77" and d["wifiBand"] == "6 GHz" and d["dns4"] == ["198.18.0.54"] for d in s["devices"].values()), "same-path AP/IP changes")
        owner.check("same-path-ap-ip-updates-reach-device-consumers", True)
        until(lambda s: s["network"]["wifi"].get("ipv4") == "198.18.0.5" and s["network"]["networks"].get("Fixture", {}).get("signal") == 77, "network facade same-path projection")
        owner.check("ap-ip-security-reach-network-facade", state()["network"]["networks"]["Fixture"]["security"] == "wpa2-psk")
        # NM's ay is a native QByteArray -> QML ArrayBuffer, including an empty
        # buffer for a hidden AP/profile. Empty native buffers are not the same
        # as []: Qt can reject constructing a Uint8Array view over them.
        for label, raw, expected in (("ascii", b"Fixture", "Fixture"),
                                     ("utf8", "Cafe\u00e9".encode(), "Cafe\u00e9"),
                                     ("non-utf8", b"\xff\x80A", "\ufffd\ufffdA"),
                                     ("hidden-empty", b"", "")):
            settings = profile("Saved " + label, "802-11-wireless")
            settings["802-11-wireless"] = {"ssid": list(raw)}
            bus.control("settings", path=PROFILE, settings=settings)
            bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Ssid": list(raw)})
            snapshot = until(lambda s: s["profiles"].get(PROFILE, {}).get("ssid") == expected
                             and s["aps"].get(ap, {}).get("ssid") == expected, label + " AP/profile SSID")
            owner.check("native-ssid-ap-and-profile-" + label,
                        snapshot["profiles"][PROFILE]["id"] == "Saved " + label, state=snapshot)
        before = len(calls("Get", ap))
        bus.control("change", path=ap, iface=NM + ".AccessPoint", invalidated=["Ssid"])
        wait_for(lambda: len(calls("Get", ap)) == before + 1, "empty ay invalidation read")
        until(lambda s: s["aps"].get(ap, {}).get("ssid") == "", "empty ay after invalidation")
        owner.check("native-empty-ssid-invalidation", True)
        # Also seed an empty AP (rather than only sending PropertiesChanged).
        bus.control("put", path=ROOT + "/AccessPoint/3", iface=NM + ".AccessPoint", introspect=False,
                    props={"Ssid": ["ay", []], "Strength": ["y", 0]})
        bus.control("signal", path=device, iface=NM + ".Device.Wireless", member="AccessPointAdded",
                    signature="(o)", args=[ROOT + "/AccessPoint/3"])
        until(lambda s: ROOT + "/AccessPoint/3" in s["aps"], "hidden AP initial GetAll")
        bus.control("signal", path=device, iface=NM + ".Device.Wireless", member="AccessPointRemoved",
                    signature="(o)", args=[ROOT + "/AccessPoint/3"])
        until(lambda s: ROOT + "/AccessPoint/3" not in s["aps"], "hidden AP retired")
        settings = profile("Empty before seed", "802-11-wireless")
        settings["802-11-wireless"] = {"ssid": []}
        bus.control("put", path=second_profile, iface=NM + ".Settings.Connection", settings=settings)
        bus.control("signal", path=ROOT + "/Settings", iface=NM + ".Settings", member="NewConnection", signature="(o)", args=[second_profile])
        until(lambda s: s["profiles"].get(second_profile, {}).get("ssid") == "", "hidden profile initial GetSettings")
        owner.check("native-empty-ssid-initial-seeds", True)
        shapes = json.loads(ipc("ssidShapes", PROFILE).stdout)
        owner.check("ssid-js-array-buffer-and-absent-shapes", shapes == ["", "", "", "", "A\u00e9", "A\u00e9", "\ufffd\ufffdA"], shapes=shapes)
        bus.control("remove", path=second_profile)
        bus.control("settings", path=PROFILE, settings=profile("Burst final"))
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Ssid": list(b"Fixture")})
        until(lambda s: s["profiles"].get(PROFILE, {}).get("id") == "Burst final"
              and s["network"]["networks"].get("Fixture"), "restore after byte cases")
        bus.control("delay", path=device, method="GetAll")
        before = len(calls("GetAll", device))
        ipc("reconcileDevice", device)
        wait_for(lambda: len(calls("GetAll", device)) == before + 2, "held base/wireless reconciliation")
        bus.control("signal", path=device, iface=NM + ".Device.Wireless", member="AccessPointRemoved", signature="(o)", args=[spare])
        bus.control("release")
        until(lambda s: spare not in s["devices"][device]["accessPoints"], "late inventory cannot resurrect removed AP")
        owner.check("ap-inventory-removal-tombstone", True)
        bus.control("delay", path=ap, method="Get")
        before = len(calls("Get", ap))
        bus.control("change", path=ap, iface=NM + ".AccessPoint", invalidated=["Strength"])
        wait_for(lambda: len(calls("Get", ap)) == before + 1, "single owned invalidation")
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Strength": 88})
        bus.control("release")
        until(lambda s: s["devices"][device]["wifiSignal"] == "88", "newer signal wins invalidated read")
        owner.check("one-invalidation-read-newer-signal-wins", len(calls("Get", ap)) == before + 1)
        profile_enumerations = len(calls("ListConnections"))
        bus.control("configure", scan="before-reply")
        operation = ipc("scan", device).stdout.strip()
        until(lambda s: any(o["id"] == operation and o["status"] == "completed" for o in s["operations"]), "LastScan before request reply")
        owner.check("lastscan-race-no-profile-reload", len(calls("ListConnections")) == profile_enumerations)
        bus.control("deny", path=ROOT, method="AddAndActivateConnection")
        # Both unchanged facade call shapes share one typed NM settings boundary.
        # a{sv} does not carry a schema for its variant payloads: an untyped JS
        # string array otherwise becomes av rather than NM's required as.
        for legacy in (False, True):
            ssid = "Typed EAP " + str(legacy)
            if legacy:
                # The older password sheet derives security from its AP entry.
                bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Ssid": list(ssid.encode()), "RsnFlags": 0x200})
                until(lambda s: s["network"]["networks"].get(ssid, {}).get("security") == "wpa2-eap", "legacy enterprise AP")
            before_requests = len(calls("AddAndActivateConnection"))
            ipc("wifiConnect", json.dumps(dict(legacy=legacy, ssid=ssid, hidden=not legacy,
                identity="fixture@example.invalid", enterprise={"eap": "ttls", "phase2": "pap",
                "anonIdentity": "anonymous@example.invalid", "caCert": "/fixture-ca.pem"})))
            wait_for(lambda: len(calls("AddAndActivateConnection")) > before_requests, "typed enterprise wire request")
            request = calls("AddAndActivateConnection")[-1]
            until(lambda s: not s["network"]["connecting"] and bool(s["network"]["error"]), "rejected enterprise request clears busy")
            types = request["variantTypes"]
            settings = request["settings"]
            owner.check("enterprise-hidden-wire-contract-" + ("legacy" if legacy else "manual"),
                        types["802-1x"]["eap"] == "as" and types["802-1x"]["ca-cert"] == "ay"
                        and types["802-11-wireless"]["ssid"] == "ay" and types["802-11-wireless"]["hidden"] == "b"
                        and settings["802-1x"]["eap"] == ["ttls"] and settings["802-1x"]["phase2-auth"] == "pap"
                        and settings["802-1x"]["ca-cert"][-1] == 0
                        and settings["802-11-wireless"]["hidden"] == (not legacy), request=request)
        bus.control("signal", path=device, iface=NM + ".Device.Wireless", member="AccessPointRemoved", signature="(o)", args=[spare])
        bus.control("signal", path=other, iface=NM + ".Device.Wireless", member="AccessPointRemoved", signature="(o)", args=[spare])
        until(lambda s: s["counts"]["accessPoints"] == 1, "AP retirement")
        bus.control("change", path=ROOT, iface=NM, props={"Devices": [other]})
        until(lambda s: len(s["devices"]) == 1, "first device removal")
        owner.check("shared-linked-record-survives-first-reference", state()["counts"]["ipConfigs"] == 1)
        bus.control("change", path=ROOT, iface=NM, props={"Devices": []})
        until(lambda s: not s["devices"] and not s["ips"] and not s["aps"], "last reference retired")
        owner.check("last-reference-retires-linked-graph", True)
        bus.control("deny", path=PROFILE, method="GetSettings")
        bus.control("signal", path=PROFILE, iface=NM + ".Settings.Connection", member="Updated")
        until(lambda s: PROFILE not in s["profiles"], "permission loss clears summary")
        owner.check("permission-loss-does-not-retain-summary", True)
        bus.control("allow", path=PROFILE, method="GetSettings")
        bus.control("signal", path=PROFILE, iface=NM + ".Settings.Connection", member="Updated")
        until(lambda s: PROFILE in s["profiles"], "permission restoration on Updated")
        bus.control("deny", path=ROOT, method="ActivateConnection")
        operation = ipc("activate", PROFILE).stdout.strip()
        until(lambda s: any(o["id"] == operation and o["status"] == "error" for o in s["operations"]), "rejected activation")
        owner.check("request-error-never-accepted", not any(o["id"] == operation and o["status"] == "accepted" for o in state()["operations"]))
        bus.control("allow", path=ROOT, method="ActivateConnection")
        bus.control("configure", activation="pending", activationReply="hold")
        before_activation = len(calls("ActivateConnection"))
        operation = ipc("activate", PROFILE).stdout.strip()
        wait_for(lambda: len(calls("ActivateConnection")) == before_activation + 1, "in-flight activation")
        activation_calls = len(calls("ActivateConnection"))
        bus.control("lose")
        until(lambda s: not s["available"] and not s["profiles"] and not s["active"], "owner loss clears facts")
        terminal = [o for o in state()["operations"] if o["id"] == operation and o["status"] != "accepted"]
        owner.check("owner-loss-settles-inflight-once", len(terminal) == 1 and not terminal[0]["ok"])
        bus.control("appear")
        until(lambda s: s["available"] and PROFILE in s["profiles"], "new owner after loss")
        owner.check("no-command-replay-after-owner-loss", len(calls("ActivateConnection")) == activation_calls)
        old_epoch = state()["epoch"]
        enumerations = len(calls("ListConnections"))
        bus.control("restart")
        until(lambda s: s.get("epoch", 0) > old_epoch and s.get("profiles", {}).get(PROFILE, {}).get("id") == "Burst final", "new-owner reused paths")
        owner.check("one-new-owner-seed", len(calls("ListConnections")) == enumerations + 1)
        bus.control("delay", path=PROFILE, method="GetSettings")
        before = len(calls("GetSettings", PROFILE))
        bus.control("settings", path=PROFILE, settings=profile("Removed in flight"))
        wait_for(lambda: len(calls("GetSettings", PROFILE)) > before, "removal held read")
        bus.control("remove", path=PROFILE)
        bus.control("release")
        until(lambda s: PROFILE not in s["profiles"], "profile remains removed")
        owner.check("remove-during-getsettings", PROFILE not in state()["profiles"])
        terminal = [o["id"] for o in state()["operations"] if o["status"] != "accepted"]
        owner.check("all-terminal-callbacks-exactly-once", len(terminal) == len(set(terminal)))
        ipc("stop")
        owner.check("normal-backend-exit", child.wait(timeout=10) == 0)
        log = (owner.work / "backend-shell.log").read_text()
        errors = re.findall(r"[^\n]*(?:TypeError|ReferenceError|Binding loop|Cannot create NetworkManager|Cannot create new component)[^\n]*", log)
        owner.check("no-runtime-exceptions-or-binding-loops", not errors, errors=errors)
        warnings = [line for line in log.splitlines() if "DBusUtils::textFromBytes" in line
                    or "Created graphical object was not placed in the graphics scene" in line]
        owner.check("no-byte-decoder-or-graphical-record-warnings", not warnings, warnings=warnings)
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        if "bus" in locals():
            (owner.work / "fixture-calls.json").write_text(json.dumps(bus.control("calls"), indent=2))
        raise
    finally:
        owner.close()


if __name__ == "__main__":
    main()
