#!/usr/bin/env python3
"""Guest-only real VPN widget/menu lifecycle, actions and NM recovery proofs."""
import argparse
import json
from pathlib import Path
import re
import time

from nm_test_support import GuestRun, PrivateBus, run, wait_for
from nm_live_support import LiveEthernet, LiveProfiles, LiveShell, SignalLog, finish_run

NM = "org.freedesktop.NetworkManager"
ROOT = "/org/freedesktop/NetworkManager"


def controlled_actions(profile, work, restart=False):
    owner = GuestRun(profile, work)
    shell = None
    try:
        bus = PrivateBus(owner)
        shell = LiveShell(owner, bus)
        bus.control("configure", activation="pending", activationReply="normal")
        before_toasts = len(shell.state()["toasts"])
        shell.action("connect:fixture-uuid")
        wait_for(lambda: shell.state()["connecting"] and shell.state()["operations"] == 1 and shell.state()["active"], "accepted pending widget activation")
        frame = shell.frame()
        toasts = [t for t in shell.state()["toasts"][before_toasts:] if t["title"] == "Initial"]
        owner.check("accepted-request-is-not-rendered-connected", frame["pill"]["icon"] == "shield" and not toasts,
                    frame=frame, allToasts=shell.state()["toasts"])
        active = next(iter(shell.state()["active"]))
        bus.control("signal", path=active, iface=NM + ".Connection.Active", member="StateChanged", signature="(uu)", args=[4, 7])
        frame = wait_for(lambda: (f if (f := shell.frame())["error"] and not f["connecting"] else None), "terminal failure reaches widget")
        bus.control("signal", path=active, iface=NM + ".Connection.Active", member="StateChanged", signature="(uu)", args=[4, 7])
        frame = shell.frame()
        toasts = [t for t in shell.state()["toasts"][before_toasts:] if t["title"] == "Initial"]
        owner.check("accepted-then-failed-widget-once-no-success-toast", frame["pill"]["icon"] == "shield" and not frame["connecting"]
                    and len(toasts) == 1 and toasts[0]["type"] == "warning", frame=frame, toasts=toasts)
        if restart:
            bus.control("configure", activation="pending", activationReply="hold")
            bus.control("delay", path=ROOT + "/Settings/1", method="GetSettings")
            bus.control("settings", path=ROOT + "/Settings/1", settings={"connection": {"id": "Stale", "uuid": "fixture-uuid", "type": "wireguard"}})
            shell.action("connect:fixture-uuid")
            wait_for(lambda: shell.state()["connecting"], "in-flight before owner replacement")
            before = shell.state()
            bus.control("restart")
            bus.control("change", path=ROOT, iface=NM, props={"ActiveConnections": []})
            wait_for(lambda: shell.state()["owner"] != before["owner"] and not shell.state()["connecting"], "owner replacement settles widget busy")
            bus.control("remove", path=ROOT + "/Settings/1")
            bus.control("release")
            wait_for(lambda: not shell.state()["profiles"], "late old-owner profile reply cannot resurrect removed profile")
            owner.check("inflight-restart-and-profile-removal", shell.state()["seeds"] == before["seeds"] + 1 and shell.state()["pid"] == before["pid"])
            calls = bus.control("calls")
            owner.check("inflight-activation-never-replayed", sum(c["method"] == "ActivateConnection" for c in calls) == 2)
        owner.check("controlled-same-shell-pid-start", shell.state()["pid"] == shell.identity.pid)
        (owner.work / "fixture-calls.json").write_text(json.dumps(bus.control("calls"), indent=2))
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        finish_run(owner, shell)
    return owner.receipt


def controlled_network(profile, work):
    owner = GuestRun(profile, work)
    shell = None
    try:
        bus = PrivateBus(owner)
        device, ap, ip4, ip6 = (ROOT + "/Devices/10", ROOT + "/AccessPoint/1", ROOT + "/IP4Config/1", ROOT + "/IP6Config/1")
        bus.control("put", path=ap, iface=NM + ".AccessPoint", introspect=False,
                    props={"Ssid": ["ay", list(b"Controlled Wi-Fi")], "Strength": ["y", 50], "Frequency": ["u", 5180],
                           "Bandwidth": ["u", 80], "Flags": ["u", 1], "WpaFlags": ["u", 0], "RsnFlags": ["u", 0x100]})
        for path, address in ((ip4, "198.18.0.4"), (ip6, "2001:db8::4")):
            bus.control("put", path=path, iface=NM + (".IP4Config" if path == ip4 else ".IP6Config"), introspect=False,
                        props={"AddressData": ["aa{sv}", [{"address": address, "prefix": 24 if path == ip4 else 64}]],
                               "Gateway": ["s", "198.18.0.1" if path == ip4 else "2001:db8::1"],
                               "NameserverData": ["aa{sv}", [{"address": "198.18.0.53" if path == ip4 else "2001:db8::53"}]]})
        bus.control("put", path=device, iface=NM + ".Device", props={"Interface": ["s", "controlled-wifi"], "DeviceType": ["u", 2],
                    "State": ["u", 100], "HwAddress": ["s", "02:00:00:00:00:01"], "ActiveConnection": ["o", "/"],
                    "Ip4Config": ["o", ip4], "Ip6Config": ["o", ip6]})
        bus.control("put", path=device, iface=NM + ".Device.Wireless", props={"Bitrate": ["u", 54000], "ActiveAccessPoint": ["o", ap],
                    "AccessPoints": ["ao", [ap]], "LastScan": ["x", 100]})
        bus.control("configure", scan="before-reply")
        bus.control("change", path=ROOT, iface=NM, props={"Devices": [device]})
        shell = LiveShell(owner, bus)
        frame = shell.panel("wifi")
        def text_frame(*expected):
            frame = shell.panel_frame()
            strings = [t["text"] for t in frame["texts"]]
            return frame if all(any(value in text for text in strings) for value in expected) else None
        frame = wait_for(lambda: text_frame("Controlled Wi-Fi"), "controlled AP reaches real NetworkPanel")
        owner.check("controlled-production-network-panel-ap", frame["visible"], frame=frame)
        shell.ipc("nmWifiDetails", "details", "Controlled Wi-Fi", "4")
        frame = wait_for(lambda: text_frame("198.18.0.4", "198.18.0.53"), "controlled IP4 details rendered")
        owner.check("controlled-panel-ip4-dns", frame["visible"], frame=frame)
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Strength": 77, "Frequency": 5955})
        bus.control("change", path=ip4, iface=NM + ".IP4Config", props={"AddressData": [{"address": "198.18.0.5", "prefix": 24}],
                    "NameserverData": [{"address": "198.18.0.54"}]})
        frame = wait_for(lambda: text_frame("198.18.0.5", "198.18.0.54", "6 GHz"), "same-path AP/IP update reaches rendered panel")
        owner.check("controlled-panel-same-path-ap-ip", any(t.get("icon") == "wifi-3" for t in frame["texts"]), frame=frame)
        shell.ipc("nmWifiDetails", "details", "Controlled Wi-Fi", "6")
        frame = wait_for(lambda: text_frame("2001:db8::4", "2001:db8::53"), "IP6 details rendered")
        owner.check("controlled-panel-ip6-dns", True, frame=frame)
        bus.control("change", path=device, iface=NM + ".Device", props={"State": 30})
        frame = wait_for(lambda: text_frame("wpa2-psk"), "inactive AP security rendered")
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"RsnFlags": 0x400})
        frame = wait_for(lambda: text_frame("sae"), "same-path security change rendered")
        owner.check("controlled-panel-same-path-security", True, frame=frame)
        enumerations = sum(c["method"] == "ListConnections" for c in bus.control("calls"))
        scans = sum(c["method"] == "RequestScan" for c in bus.control("calls"))
        bus.control("configure", scan="pending")
        shell.ipc("nmPanel", "scan")
        wait_for(lambda: sum(c["method"] == "RequestScan" for c in bus.control("calls")) > scans,
                 "panel issues an actual RequestScan")
        wait_for(lambda: shell.panel_frame()["scanning"], "panel observes in-flight scan")
        bus.control("change", path=device, iface=NM + ".Device.Wireless", props={"LastScan": 200})
        wait_for(lambda: not shell.panel_frame()["scanning"], "LastScan settles panel scan")
        owner.check("controlled-panel-scan-no-profile-enumeration", sum(c["method"] == "ListConnections" for c in bus.control("calls")) == enumerations)
        bus.control("deny", path=ROOT, method="AddAndActivateConnection")
        # These synthetic strings are deliberately not real account material.
        shell.ipc("nmPanel", "connect", json.dumps(dict(ssid="Hidden EAP fixture", hidden=True, security="wpa2-eap",
                  password="synthetic-test-only", identity="fixture@example.invalid", enterprise={"eap": "ttls", "phase2": "pap",
                  "anonIdentity": "anonymous@example.invalid", "caCert": "/nonexistent/fixture-ca.pem"})))
        def request():
            return next((c for c in reversed(bus.control("calls")) if c["method"] == "AddAndActivateConnection"), None)
        payload = wait_for(request, "enterprise settings arrive at protocol peer")
        values = payload["settings"]
        owner.check("hidden-enterprise-wire-values-and-types", values["802-11-wireless"]["hidden"]
                    and bytes(values["802-11-wireless"]["ssid"]).decode() == "Hidden EAP fixture"
                    and values["802-1x"]["eap"] == ["ttls"] and values["802-1x"]["phase2-auth"] == "pap"
                     and payload["variantTypes"]["802-11-wireless"]["ssid"] == "ay"
                     and payload["variantTypes"]["802-1x"]["eap"] == "as"
                     and payload["variantTypes"]["802-1x"]["ca-cert"] == "ay"
                     and bytes(values["802-1x"]["ca-cert"]) == b"file:///nonexistent/fixture-ca.pem\0", payload=payload)
        frame = wait_for(lambda: (f if (f := shell.panel_frame())["error"] else None), "network request rejection reaches rendered panel")
        owner.check("controlled-network-failure-rendered", any(frame["error"] == t["text"] for t in frame["texts"]), frame=frame)
        # Saved SSID bytes and an empty hidden AP must meet again at the real
        # panel, not merely in NmState's maps. Keep the display name distinct.
        saved, active = ROOT + "/Settings/2", ROOT + "/ActiveConnection/10"
        ssid, name = "Saved Wi-Fi \u00e9", "Profile name \u00e9"
        bus.control("put", path=saved, iface=NM + ".Settings.Connection", settings={
            "connection": {"uuid": "saved-wifi-uuid", "id": name, "type": "802-11-wireless"},
            "802-11-wireless": {"ssid": list(ssid.encode())}})
        bus.control("signal", path=ROOT + "/Settings", iface=NM + ".Settings", member="NewConnection", signature="(o)", args=[saved])
        bus.control("put", path=active, iface=NM + ".Connection.Active", props={
            "Id": ["s", name], "Uuid": ["s", "saved-wifi-uuid"], "Type": ["s", "802-11-wireless"],
            "Connection": ["o", saved], "Devices": ["ao", [device]], "State": ["u", 2],
            "Ip4Config": ["o", ip4], "Ip6Config": ["o", ip6]})
        bus.control("change", path=ROOT, iface=NM, props={"ActiveConnections": [active]})
        bus.control("change", path=device, iface=NM + ".Device", props={"State": 100, "ActiveConnection": active})
        visible_ap = ROOT + "/AccessPoint/2"
        bus.control("put", path=visible_ap, iface=NM + ".AccessPoint", props={"Ssid": ["ay", list(ssid.encode())],
                    "Strength": ["y", 90], "Frequency": ["u", 5180], "Flags": ["u", 0], "WpaFlags": ["u", 0], "RsnFlags": ["u", 0]})
        bus.control("change", path=device, iface=NM + ".Device.Wireless", props={"AccessPoints": [ap, visible_ap]})
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Ssid": []})
        frame = wait_for(lambda: text_frame(ssid, "Connected"), "hidden AP overrides disconnected namesake in real panel")
        owner.check("hidden-empty-ap-saved-ssid-rendered", frame["visible"], frame=frame)
        owner.check("wifi-profile-name-preserved", shell.state()["profiles"][saved]["id"] == name)
        bus.control("change", path=device, iface=NM + ".Device", props={"State": 30})
        bus.control("change", path=ap, iface=NM + ".AccessPoint", props={"Ssid": [255, 128, 65]})
        frame = wait_for(lambda: text_frame("\ufffd\ufffdA"), "non-UTF-8 AP rendered with replacement characters")
        owner.check("non-utf8-ssid-rendered", frame["visible"], frame=frame)
        # Profile names are strings, not ay. Verify the real VPN menu still
        # renders them after the SSID fixture has exercised empty byte buffers.
        bus.control("settings", path=ROOT + "/Settings/1", settings={"connection": {
            "uuid": "fixture-uuid", "id": name, "type": "wireguard"}})
        shell.click(json.loads(shell.ipc("nmLive", "networkPoint")))
        shell.menu()
        def named_menu():
            frame = shell.frame()
            return frame if any(name in text for row in frame["menu"]["rows"] for text in row["texts"]) else None
        frame = wait_for(named_menu, "UTF-8 profile name rendered in VPN menu")
        owner.check("profile-name-rendered", frame["menu"]["visible"], frame=frame)
        shell.close()
        log = (owner.work / "live-shell.log").read_text()
        warnings = [line for line in log.splitlines() if "DBusUtils::textFromBytes" in line
                    or "Created graphical object was not placed in the graphics scene" in line
                    or "TypeError" in line or "ReferenceError" in line]
        owner.check("no-byte-or-graphical-record-runtime-warnings", not warnings, warnings=warnings)
        (owner.work / "fixture-calls.json").write_text(json.dumps(bus.control("calls"), indent=2))
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        if "bus" in locals():
            (owner.work / "fixture-calls.json").write_text(json.dumps(bus.control("calls"), indent=2))
        raise
    finally:
        finish_run(owner, shell)
    return owner.receipt


def lifecycle(owner, shell, profiles, signals, prefix="lifecycle"):
    def observe(label, command, predicate, signal_predicate):
        shell.menu()
        start = time.monotonic()
        value = command()
        def observed():
            frame = shell.frame()
            return frame if predicate(frame) else None
        frame = wait_for(observed, label, seconds=5)
        candidates = [e for e in signals.events if e["monotonic"] >= start and signal_predicate(e)]
        assert candidates, "missing causal daemon signal: " + label
        # Earliest relevant signal gives a conservative propagation upper bound.
        latency = (frame["observedMonotonic"] - candidates[0]["monotonic"]) * 1000
        owner.check(prefix + "-" + label, 0 <= latency <= 1000, latencyMs=latency,
                    signal=candidates[0], frame=frame)
        return value
    def labels(frame):
        return " ".join(t for row in frame["menu"]["rows"] if row["visible"] for t in row["texts"])
    identity = observe("add", profiles.add, lambda f: "nm-events-wg" in labels(f), lambda e: e["member"] == "NewConnection")
    path = next(p for p, v in shell.state()["profiles"].items() if v["uuid"] == identity)
    updated = lambda e: e["path"] == path and e["member"] == "Updated"
    active = lambda e: e["member"] == "PropertiesChanged" and e["path"] == "/org/freedesktop/NetworkManager" and "ActiveConnections" in e["args"][1]
    observe("inactive-rename", lambda: profiles.command("connection", "modify", "uuid", identity, "connection.id", "nm-events-renamed"),
            lambda f: "nm-events-renamed" in labels(f) and "nm-events-wg" not in labels(f), updated)
    observe("up", lambda: profiles.command("connection", "up", "uuid", identity),
            lambda f: f["pill"]["icon"] == "shield-lock" and f["pill"]["text"] == "nm-events-renamed" and f["pill"]["textVisible"]
            and any(r["action"] == "disconnect:" + identity for r in f["menu"]["rows"]), active)
    observe("active-rename", lambda: profiles.command("connection", "modify", "uuid", identity, "connection.id", "nm-events-active"),
            lambda f: "nm-events-active" in labels(f) and f["pill"]["text"] == "nm-events-active", updated)
    observe("down", lambda: profiles.command("connection", "down", "uuid", identity),
            lambda f: f["pill"]["icon"] == "shield" and not f["pill"]["text"] and any(r["action"] == "connect:" + identity for r in f["menu"]["rows"]), active)
    observe("delete", lambda: profiles.delete(identity), lambda f: not any(identity in r["action"] for r in f["menu"]["rows"]),
            lambda e: e["member"] in ("Removed", "ConnectionRemoved") and (e["path"] == path or path in e["args"]))
    # Equal display names remain distinct delegates and command identities.
    first, second = profiles.add("nm-events-duplicate"), profiles.add("nm-events-duplicate")
    def duplicate_rows():
        frame = shell.frame()
        return frame if sum("nm-events-duplicate" in " ".join(r["texts"]) for r in frame["menu"]["rows"]) == 2 else None
    frame = wait_for(duplicate_rows, "duplicate-name delegates")
    owner.check(prefix + "-duplicate-names", {"connect:" + first, "connect:" + second}.issubset({r["action"] for r in frame["menu"]["rows"]}), frame=frame)
    profiles.command("connection", "up", "uuid", first)
    wait_for(lambda: shell.frame()["pill"]["icon"] == "shield-lock", "active duplicate")
    start = time.monotonic()
    profiles.delete(first)
    frame = wait_for(lambda: (f if (f := shell.frame())["pill"]["icon"] == "shield" and not any(first in r["action"] for r in f["menu"]["rows"]) else None), "delete active profile")
    event = next(e for e in signals.events if e["monotonic"] >= start and e["member"] in ("Removed", "ConnectionRemoved"))
    latency = (frame["observedMonotonic"] - event["monotonic"]) * 1000
    owner.check(prefix + "-active-removal", latency <= 1000, latencyMs=latency, frame=frame)
    profiles.delete(second)


def actions(owner, shell, profiles):
    identity = profiles.add()
    wait_for(lambda: identity in shell.state()["vpn"], "profile for real menu action")
    shell.action("connect:" + identity)
    frame = wait_for(lambda: (f if (f := shell.frame())["pill"]["icon"] == "shield-lock" and not f["connecting"] else None), "menu connect observed activated")
    owner.check("real-menu-connect", shell.state()["vpn"][identity]["active"], frame=frame)
    shell.action("disconnect:" + identity)
    frame = wait_for(lambda: (f if (f := shell.frame())["pill"]["icon"] == "shield" and not f["disconnecting"] else None), "menu disconnect observed inactive")
    owner.check("real-menu-disconnect", not shell.state()["vpn"][identity]["active"], frame=frame)
    rejected = profiles.add("nm-events-rejected", failed=True)
    wait_for(lambda: rejected in shell.state()["vpn"], "failed plugin profile")
    before_toasts = len(shell.state()["toasts"])
    shell.action("connect:" + rejected)
    frame = wait_for(lambda: (f if (f := shell.frame())["error"] and not f["connecting"] else None), "rejected activation clears busy")
    owner.check("real-nm-rejected-activation", frame["pill"]["icon"] == "shield" and not shell.state()["vpn"][rejected]["active"], frame=frame)
    toasts = shell.state()["toasts"][before_toasts:]
    owner.check("real-rejection-once-no-connected-toast", len(toasts) == 1 and toasts[0]["type"] == "warning", toasts=toasts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--case", choices=("lifecycle", "actions", "restart", "network", "wifi"), required=True)
    args = parser.parse_args()
    if args.case == "wifi":
        controlled_network(args.guest_profile, args.work)
        return
    owner = GuestRun(args.guest_profile, args.work)
    shell = profiles = signals = None
    try:
        signals = SignalLog(owner)
        profiles = LiveProfiles(owner)
        shell = LiveShell(owner)
        owner.check("real-widget-rendered", shell.frame()["pill"]["iconVisible"] and shell.frame()["pill"]["height"] > 0)
        if args.case == "lifecycle":
            lifecycle(owner, shell, profiles, signals)
        elif args.case == "actions":
            actions(owner, shell, profiles)
        elif args.case == "restart":
            before = shell.state()
            run(["sudo", "-n", "systemctl", "restart", "NetworkManager"], seconds=30)
            wait_for(lambda: shell.state()["available"] and shell.state()["owner"] != before["owner"] and shell.state()["profiles"], "new NM owner", seconds=30)
            events = [e for e in signals.events if e["member"] == "NameOwnerChanged"]
            owner.check("actual-owner-loss-and-replacement", any(not e["args"][2] for e in events) and shell.state()["epoch"] == before["epoch"] + 2,
                        events=events, before=before, after=shell.state())
            owner.check("exactly-one-new-owner-seed", shell.state()["seeds"] == before["seeds"] + 1 and False in shell.state()["availability"])
            lifecycle(owner, shell, profiles, signals, "post-restart")
        else:
            ethernet = LiveEthernet(owner, profiles)
            ethernet.up()
            wait_for(lambda: any(d.get("ifname") == ethernet.ifname and d.get("connected") for d in shell.state()["devices"].values()), "live disposable Ethernet up")
            shell.panel("ethernet", ethernet.ifname)
            def address_frame(address):
                frame = shell.panel_frame()
                return frame if any(address in t["text"] for t in frame["texts"]) else None
            frame = wait_for(lambda: address_frame("198.19.0.2"), "live Ethernet IP rendered")
            owner.check("live-ethernet-panel-address", frame["visible"], frame=frame)
            ethernet.change_address()
            frame = wait_for(lambda: address_frame("198.19.0.3"), "same-device live Ethernet IP edit rendered")
            owner.check("live-ethernet-panel-ip-change", frame["visible"], frame=frame)
            ethernet.down()
            wait_for(lambda: not any(d.get("ifname") == ethernet.ifname and d.get("connected") for d in shell.state()["devices"].values()), "disposable Ethernet disconnected")
            owner.check("live-ethernet-observed-disconnect", True, frame=shell.panel_frame())
        owner.check("unchanged-shell-identity", shell.state()["pid"] == shell.identity.pid)
        log = (owner.work / "live-shell.log").read_text()
        errors = re.findall(r"[^\n]*(?:TypeError|ReferenceError|Binding loop|Failed to load configuration)[^\n]*", log)
        # The unchanged HostService warning is present in the pre-task cold-load
        # evidence as well. Retain it, classify it, and reject every other error.
        known = [e for e in errors if 'QML XdgIcon at @Services/System/HostService.qml[29:3]: Binding loop detected for property "name":' in e]
        owner.check("no-runtime-exceptions", len(errors) == len(known), errors=errors, preexistingHostService=known)
        if args.case in ("actions", "restart", "network"):
            shell.close()
            shell = None
            if args.case == "network":
                result = controlled_network(args.guest_profile, owner.work / "controlled")
            else:
                result = controlled_actions(args.guest_profile, owner.work / "controlled", restart=args.case == "restart")
            owner.check("controlled-consumer-cases", result["passed"], result=str(owner.work / "controlled/result.json"))
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        finish_run(owner, profiles, shell, signals)


if __name__ == "__main__":
    main()
