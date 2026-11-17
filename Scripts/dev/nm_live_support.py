"""Owned real-shell and harmless live NM fixtures for the guest-only NM proofs."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import threading
import time
import uuid

from guest_profile import ProcessIdentity, protect_owned_process
from nm_test_support import SOURCE, run, wait_for
from qml_probe import inject_probe, probe_owner_path


def finish_run(owner, *resources):
    """Attempt every restoration even when one earlier teardown fails."""
    primary = sys.exception()
    errors = []
    for resource in resources:
        if resource:
            try:
                resource.close()
            except BaseException as error:
                errors.append(dict(resource=type(resource).__name__, error=repr(error)))
    if errors:
        owner.receipt["error"] = owner.receipt.get("error", "resource restoration failed")
    owner.receipt["restorationErrors"] = errors
    try:
        if not owner.close() and (primary is None or not owner.receipt.get("cleanupComplete")):
            errors.append(dict(resource="owned-children", error="runner cleanup or acceptance failed"))
    except BaseException as error:
        errors.append(dict(resource="owned-children", error=repr(error)))
    # This also covers a constructor that failed before returning its shell.
    try:
        run(["niri", "msg", "action", "load-config-file", "--path", "/home/tester/.config/niri/config.kdl"],
            env=dict(os.environ, **owner.profile.session_environment()))
    except BaseException as error:
        errors.append(dict(resource="niri", error=repr(error)))
        owner.receipt["error"] = owner.receipt.get("error", "niri restoration failed")
        owner.receipt["passed"] = False
    if errors:
        owner.receipt["passed"] = False
    owner.write()
    if errors:
        message = "NM proof restoration failed: " + repr(errors)
        if primary is not None:
            primary.add_note(message)
        else:
            raise RuntimeError(message)


MENU_PROBE = r'''
  function nmTestSnapshot() {
    function texts(item) {
      var result = [];
      if (item.text !== undefined && item.visible && item.width > 0 && item.height > 0)
        result.push(String(item.text));
      for (var child of item.children || []) result = result.concat(texts(child));
      return result;
    }
    var rows = [];
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i);
      if (!item) continue;
      var point = item.mapToGlobal(item.width / 2, item.height / 2);
      rows.push({action: item.modelData.action, texts: texts(item),
        visible: root.visible && item.visible, width: item.width, height: item.height,
        x: point.x, y: point.y});
    }
    return {visible: root.visible, rows: rows};
  }
'''

PILL_PROBE = r'''
  function nmTestSnapshot() {
    return {text: textItem.text, textVisible: textItem.visible,
      textWidth: textItem.width, textHeight: textItem.height,
      icon: iconCircle.children[0].icon, glyph: iconCircle.children[0].children[0].text,
      iconVisible: iconCircle.children[0].visible,
      width: root.width, height: root.height};
  }
'''

VPN_PROBE = r'''
  property var nmTestFrame: ({})
  property int nmTestRequested: 0
  property int nmTestCaptured: 0
  FrameAnimation {
    running: root.nmTestCaptured !== root.nmTestRequested
    onTriggered: Qt.callLater(function () {
      var point = root.mapToGlobal(root.width / 2, root.height / 2);
      root.nmTestFrame = {sequence: root.nmTestRequested,
        pill: pill.nmTestSnapshot(), menu: contextMenu.nmTestSnapshot(),
        x: point.x, y: point.y, visible: root.visible,
        connecting: VPNService.connecting, disconnecting: VPNService.disconnecting,
        error: VPNService.lastError};
      root.nmTestCaptured = root.nmTestRequested;
    })
  }
  IpcHandler {
    target: "nmWidget"
    function request(): int { return ++root.nmTestRequested; }
    function frame(): string { return JSON.stringify(root.nmTestFrame); }
  }
'''

PANEL_PROBE = r'''
  property var nmTestFrame: ({})
  property int nmTestRequested: 0
  property int nmTestCaptured: 0
  function nmTestTexts(item) {
    var result = [];
    if (!item.visible || item.opacity === 0) return result;
    if (item.text !== undefined && item.width > 0 && item.height > 0) {
      var point = item.mapToGlobal(item.width / 2, item.height / 2);
      result.push({text: String(item.text), x: point.x, y: point.y, width: item.width, height: item.height});
    }
    if (item._resolved !== undefined && item.icon !== undefined && item.width > 0 && item.height > 0)
      result.push({text: "", icon: String(item.icon), source: item._resolved?.source || "",
        width: item.width, height: item.height});
    for (var child of item.children || []) result = result.concat(nmTestTexts(child));
    return result;
  }
  FrameAnimation {
    running: mainColumn.nmTestCaptured !== mainColumn.nmTestRequested
    onTriggered: Qt.callLater(function () {
      mainColumn.nmTestFrame = {sequence: mainColumn.nmTestRequested,
        visible: root.isPanelVisible && root.effectivelyVisible,
        mode: root.panelViewMode, texts: mainColumn.nmTestTexts(mainColumn),
        scanning: NetworkService.scanningActive, error: NetworkService.lastError};
      mainColumn.nmTestCaptured = mainColumn.nmTestRequested;
    })
  }
  IpcHandler {
    target: "nmPanel"
    function configure(mode: string, ifname: string) {
      root.panelViewMode = mode;
      root.ethernetInfoExpanded = true;
      if (ifname) NetworkService.activeEthernetIf = ifname;
    }
    function ipVersion(version: int) { root.ipVersion = version; }
    function request(): int { return ++mainColumn.nmTestRequested; }
    function frame(): string { return JSON.stringify(mainColumn.nmTestFrame); }
    function scan() { NetworkService.scan(); }
    function connect(text: string) {
      var a = JSON.parse(text);
      NetworkService.connect(a.ssid, a.password || "", a.hidden || false, a.security || "", a.identity || "", a.enterprise || {});
    }
  }
'''

SHELL_PROBE = r'''
  property var nmTestAvailability: []
  property var nmTestToasts: []
  Connections {
    target: NmState
    function onAvailableChanged() { shellRoot.nmTestAvailability = shellRoot.nmTestAvailability.concat([NmState.available]); }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      shellRoot.nmTestToasts = shellRoot.nmTestToasts.concat([{title: title, description: description, type: type}]);
    }
  }
  IpcHandler {
    target: "nmLive"
    function state(): string {
      return JSON.stringify({pid: Quickshell.processId, ready: IPCService.screenDetector !== null,
        available: NmState.available, epoch: NmState.epoch, owner: NmState._owner,
        counts: NmState.recordCounts, profiles: NmState.profiles,
        active: NmState.activeConnections, devices: NmState.devices,
        seeds: NmState.nmTestSeeds, availability: shellRoot.nmTestAvailability, toasts: shellRoot.nmTestToasts,
        operations: Object.keys(NmState._operations).length,
        vpn: VPNService.connections, connecting: VPNService.connecting,
        disconnecting: VPNService.disconnecting, error: VPNService.lastError});
    }
    function networkPoint(): string {
      var widget = BarService.lookupWidget("Network", Quickshell.screens[0].name);
      var point = widget.mapToGlobal(widget.width / 2, widget.height / 2);
      return JSON.stringify({x: point.x, y: point.y});
    }
    function stop() { Qt.quit(); }
  }
'''


class SignalLog:
    """Subscribe before actions; timestamp receipt on Python's monotonic clock."""
    def __init__(self, owner, track_names=False):
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        self.GLib = GLib
        self.events = []
        self.file = (owner.work / "nm-signals.jsonl").open("x")
        self.context = GLib.MainContext.new()
        self.ready = threading.Event()
        self.failure = None
        self.stopping = False
        self.name_owners = []
        def worker():
            self.context.push_thread_default()
            try:
                self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
                def received(bus, sender, path, iface, member, values, data):
                    unpacked = values.unpack()
                    if track_names and member == "NameOwnerChanged" and unpacked[0].startswith(":"):
                        event = dict(monotonic=time.monotonic(), name=unpacked[0], old=unpacked[1], new=unpacked[2])
                        if unpacked[2]:
                            try:
                                event["pid"] = self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                    "GetConnectionUnixProcessID", GLib.Variant("(s)", (unpacked[0],)), None,
                                    Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
                            except GLib.Error as error:
                                event["unresolved"] = str(error)
                        self.name_owners.append(event)
                        self.file.write(json.dumps(dict(nameMembership=event)) + "\n")
                        self.file.flush()
                    if iface.startswith("org.freedesktop.NetworkManager") or (
                            iface == "org.freedesktop.DBus.Properties" and path.startswith("/org/freedesktop/NetworkManager")) or (
                            member == "NameOwnerChanged" and values.unpack()[0] == "org.freedesktop.NetworkManager"):
                        event = dict(monotonic=time.monotonic(), sender=sender, path=path,
                                     iface=iface, member=member, args=values.unpack())
                        self.events.append(event)
                        self.file.write(json.dumps(event) + "\n")
                        self.file.flush()
                subscription = self.bus.signal_subscribe(None, None, None, None, None,
                                                         Gio.DBusSignalFlags.NONE, received, None)
                # Round trip after AddMatch: readiness is not just thread liveness.
                self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                   "GetId", None, None, Gio.DBusCallFlags.NONE, 3000, None)
                self.ready.set()
                while not self.stopping:
                    self.context.iteration(True)
                self.bus.signal_unsubscribe(subscription)
            except BaseException as error:
                self.failure = repr(error)
                self.ready.set()
            finally:
                self.context.pop_thread_default()
        self.thread = threading.Thread(target=worker, daemon=False)
        self.thread.start()
        try:
            assert self.ready.wait(10) and not self.failure, self.failure
        except BaseException as error:
            try:
                self.close()
            except BaseException as cleanup:
                error.add_note("SignalLog constructor cleanup failed: " + repr(cleanup))
            raise

    def close(self):
        self.stopping = True
        self.context.wakeup()
        self.thread.join(10)
        self.file.close()
        assert not self.thread.is_alive() and not self.failure, self.failure


class LiveShell:
    def __init__(self, owner, bus=None):
        self.owner = owner
        self.env = dict(owner.env, QT_QPA_PLATFORM="wayland", XDG_CURRENT_DESKTOP="niri",
                        ATMOSPHERA_DEBUG="0", DISPLAY="")
        if bus:
            self.env.update(DBUS_SYSTEM_BUS_ADDRESS=bus.address, DBUS_SESSION_BUS_ADDRESS=bus.address)
        assert not owner.profile.console.records, "preserve an existing console; this runner needs an idle guest session"
        self.shell = owner.work / "shell"
        shutil.copytree(SOURCE, self.shell, ignore=shutil.ignore_patterns(".git", ".envrc", "__pycache__"))
        def inject(path, probe, root_id="root", imports=""):
            path = self.shell / path
            text = path.read_text()
            path.write_text(inject_probe(imports + text, probe, root_id=root_id))
        inject("Modules/Bar/Widgets/VPN.qml", VPN_PROBE, imports="import Quickshell.Io\n")
        inject("Widgets/NPopupContextMenu.qml", MENU_PROBE)
        inject("Modules/Bar/Extras/BarPillHorizontal.qml", PILL_PROBE)
        inject("Modules/Bar/Extras/BarPill.qml", "function nmTestSnapshot() { return pillLoader.item.nmTestSnapshot(); }")
        inject("Modules/Panels/Network/NetworkPanel.qml", PANEL_PROBE, root_id="mainColumn", imports="import Quickshell.Io\n")
        inject("Modules/Panels/Settings/Tabs/Connections/WifiSubTab.qml", r'''
  IpcHandler {
    target: "nmWifiDetails"
    function details(ssid: string, version: int) { root.infoSsid = ssid; root.ipVersion = version; }
  }
''', imports="import Quickshell.Io\n")
        nm_path = self.shell / "Services/Networking/NmState.qml"
        text = inject_probe(nm_path.read_text(), "property int nmTestSeeds: 0", root_id="root")
        anchor = "function _listProfiles() {"
        assert text.count(anchor) == 1
        nm_path.write_text(text.replace(anchor, anchor + "\n    nmTestSeeds++;"))
        entry = probe_owner_path(self.shell)
        text = "import Quickshell.Io\nimport qs.Services.Networking\n" + entry.read_text()
        entry.write_text(inject_probe(text, SHELL_PROBE))
        defaults = json.loads((self.shell / "Configs/defaults.json").read_text())
        defaults["general"].update(showChangelogOnStartup=False, animationDisabled=True)
        defaults["inputMethod"].update(launchFcitx5=False, legacyI18nChecked=True)
        defaults["bar"].update(widgets={"left": [], "center": [
            {"id": "VPN", "displayMode": "alwaysShow"}], "right": [{"id": "Network"}]},
            edgeScrolling=False, position="top", barType="simple")
        directory = owner.work / "config/atmosphera"
        directory.mkdir(parents=True)
        (directory / "settings.json").write_text(json.dumps(defaults))
        self.process = owner.launch(["qs", "-p", self.shell, "--no-color"], "live-shell", self.env)
        self.identity = ProcessIdentity.read(self.process.pid)
        owner.receipt["shellIdentity"] = self.identity.record()
        owner.write()
        def ready():
            try:
                return self.state().get("ready") and self.state().get("profiles")
            except (subprocess.SubprocessError, ValueError):
                assert self.process.poll() is None, "shell exited: read live-shell.log"
                return False
        wait_for(ready, "real shell seed and UI", seconds=90)
        self.pointer = None
        wait_for(lambda: self.frame()["pill"]["iconVisible"], "production icon plugin ready", seconds=30)

    def ipc(self, target, method, *values):
        result = run(["qs", "ipc", "--pid", self.process.pid, "call", target, method, *values], env=self.env, check=False)
        if result.returncode:
            with (self.owner.work / "ipc-failures.jsonl").open("a") as output:
                output.write(json.dumps(dict(target=target, method=method, rc=result.returncode,
                                             stdout=result.stdout, stderr=result.stderr)) + "\n")
            result.check_returncode()
        return result.stdout.strip()

    def state(self):
        assert self.process.poll() is None, "shell exited"
        current = ProcessIdentity.read(self.process.pid)
        assert (current.pid, current.start, current.uid, current.pgid) == (
            self.identity.pid, self.identity.start, self.identity.uid, self.identity.pgid), "shell identity changed"
        return json.loads(self.ipc("nmLive", "state"))

    def frame(self):
        sequence = int(self.ipc("nmWidget", "request"))
        def captured():
            value = json.loads(self.ipc("nmWidget", "frame"))
            return value if value.get("sequence", 0) >= sequence else None
        value = wait_for(captured, "rendered VPN frame", seconds=5)
        value["observedMonotonic"] = time.monotonic()
        with (self.owner.work / "widget-frames.jsonl").open("a") as output:
            output.write(json.dumps(value) + "\n")
        return value

    def start_pointer(self):
        build = self.owner.work / "pointer-build"
        build.mkdir()
        protocol = SOURCE / "Scripts/dev/wlr-virtual-pointer-unstable-v1.xml"
        for mode, name in (("client-header", "virtual-pointer-client.h"), ("private-code", "virtual-pointer-protocol.c")):
            run(["wayland-scanner", mode, protocol, build / name], env=self.env)
        flags = run(["pkg-config", "--cflags", "--libs", "wayland-client"], env=self.env).stdout.split()
        run(["cc", "-I", build, SOURCE / "Scripts/dev/edge-scroll-test-pointer.c",
             build / "virtual-pointer-protocol.c", *flags, "-o", build / "pointer"], env=self.env)
        log = (self.owner.work / "pointer.log").open("xb")
        self.owner.logs.append(log)
        self.pointer = subprocess.Popen([str(build / "pointer")], env=self.env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=log, text=True, bufsize=1, start_new_session=True)
        self.owner.children.append((self.pointer, protect_owned_process(self.pointer)))
        assert select.select([self.pointer.stdout], [], [], 10)[0]
        assert self.pointer.stdout.readline().strip() == "READY"
        outputs = json.loads(run(["niri", "msg", "-j", "outputs"], env=self.env).stdout)
        logical = [o["logical"] for o in outputs.values() if o["logical"]]
        self.extent = (max(o["x"] + o["width"] for o in logical), max(o["y"] + o["height"] for o in logical))

    def pointer_command(self, value):
        with (self.owner.work / "pointer-commands.jsonl").open("a") as output:
            output.write(json.dumps(dict(monotonic=time.monotonic(), command=value)) + "\n")
        self.pointer.stdin.write(value + "\n")
        self.pointer.stdin.flush()
        assert select.select([self.pointer.stdout], [], [], 10)[0]
        assert self.pointer.stdout.readline().strip() == "OK"

    def click(self, point, button=272):
        if not self.pointer:
            self.start_pointer()
        self.pointer_command(f"move {round(point['x'])} {round(point['y'])} {self.extent[0]} {self.extent[1]}")
        time.sleep(.05)
        self.pointer_command(f"button {button} 1")
        self.pointer_command(f"button {button} 0")

    def menu(self):
        if not self.frame()["menu"]["visible"]:
            self.click(self.frame(), 273)
        return wait_for(lambda: (f if (f := self.frame())["menu"]["visible"] else None), "right-click VPN menu")

    def action(self, action):
        frame = self.menu()
        row = next(r for r in frame["menu"]["rows"] if r["action"] == action)
        assert row["visible"] and row["texts"] and row["width"] > 0 and row["height"] > 0, row
        self.click(row)

    def panel(self, mode="ethernet", ifname=""):
        self.click(json.loads(self.ipc("nmLive", "networkPoint")))
        def configure():
            try:
                self.ipc("nmPanel", "configure", mode, ifname)
                return True
            except subprocess.CalledProcessError:
                return False
        wait_for(configure, "NetworkPanel constructed")
        return wait_for(lambda: (f if (f := self.panel_frame())["visible"] else None), "real NetworkPanel visible")

    def panel_frame(self):
        sequence = int(self.ipc("nmPanel", "request"))
        def captured():
            value = json.loads(self.ipc("nmPanel", "frame"))
            return value if value.get("sequence", 0) >= sequence else None
        value = wait_for(captured, "rendered NetworkPanel frame", seconds=5)
        value["observedMonotonic"] = time.monotonic()
        with (self.owner.work / "panel-frames.jsonl").open("a") as output:
            output.write(json.dumps(value) + "\n")
        return value

    def close(self):
        if self.process.poll() is None:
            self.ipc("nmLive", "stop")
            assert self.process.wait(timeout=15) == 0, "normal shell exit"
        run(["niri", "msg", "action", "load-config-file", "--path", "/home/tester/.config/niri/config.kdl"], env=self.env)


class LiveProfiles:
    def __init__(self, owner):
        self.owner = owner
        self.uuids = []
        self.ledger = owner.work / "fixture-ledger.json"
        self.before = self.network()
        self.authorization = Path("/etc/polkit-1/rules.d/49-atmosphera-nm-events.rules")
        assert not self.authorization.exists(), "foreign authorization fixture exists"
        rule = ('polkit.addRule(function(action, subject) {\n'
                '  if (subject.user === "tester" && ["org.freedesktop.NetworkManager.network-control",\n'
                '      "org.freedesktop.NetworkManager.settings.modify.system",\n'
                '      "org.freedesktop.NetworkManager.settings.modify.own",\n'
                '      "org.freedesktop.NetworkManager.wifi.scan"].indexOf(action.id) >= 0)\n'
                '    return polkit.Result.YES;\n});\n')
        local = owner.work / "nm-polkit.rules"
        local.write_text(rule)
        try:
            run(["sudo", "-n", "install", "-m", "0644", local, self.authorization])
            wait_for(lambda: run(["nmcli", "-t", "general", "permissions"]).stdout.split(
                "org.freedesktop.NetworkManager.settings.modify.system:")[1].splitlines()[0] == "yes", "guest polkit fixture ready")
            self.save()
        except BaseException as error:
            try:
                run(["sudo", "-n", "rm", "-f", "--", self.authorization])
            except BaseException as cleanup:
                error.add_note("LiveProfiles constructor cleanup failed: " + repr(cleanup))
            raise

    def network(self):
        return dict(routes=run(["ip", "-j", "route", "show", "default"]).stdout,
                    dns=Path("/etc/resolv.conf").read_text(),
                    management=run(["nmcli", "-t", "-f", "GENERAL.CONNECTION,GENERAL.STATE", "device", "show", "enp1s0"]).stdout)

    def save(self):
        self.ledger.write_text(json.dumps(dict(uuids=self.uuids, networkBefore=self.before), indent=2))

    def command(self, *args, check=True):
        return run(["nmcli", "--wait", "10", *args], seconds=15, check=check)

    def add(self, name="nm-events-wg", failed=False):
        identity = str(uuid.uuid4())
        self.uuids.append(identity)
        self.save()  # ownership precedes mutation, including interrupted add.
        if failed:
            self.command("connection", "add", "type", "vpn", "vpn-type", "org.example.AtmospheraMissingPlugin",
                         "con-name", name, "connection.uuid", identity, "connection.autoconnect", "no")
        else:
            self.command("connection", "add", "type", "wireguard", "ifname", "nme-wg0", "con-name", name,
                         "connection.uuid", identity, "connection.autoconnect", "no", "ipv4.method", "manual",
                         "ipv4.addresses", "198.18.0.1/32", "ipv4.never-default", "yes", "ipv4.ignore-auto-dns", "yes",
                         "ipv6.method", "disabled", "ipv6.never-default", "yes", "ipv6.ignore-auto-dns", "yes",
                         "wireguard.peer-routes", "no")
            # The key is never persisted in source, logs or results. nmcli's argv
            # remains local to the isolated guest and is not included in errors.
            key = run(["wg", "genkey"]).stdout.strip()
            try:
                result = self.command("connection", "modify", "uuid", identity, "wireguard.private-key", key, check=False)
            except subprocess.SubprocessError:
                raise RuntimeError("install disposable guest-only key command failed") from None
            assert result.returncode == 0, "install disposable guest-only key"
        return identity

    def delete(self, identity):
        self.command("connection", "delete", "uuid", identity)
        self.uuids.remove(identity)
        self.save()

    def close(self):
        errors = []
        after = None
        try:
            for identity in self.uuids[:]:
                try:
                    result = self.command("connection", "delete", "uuid", identity, check=False)
                    if result.returncode not in (0, 10):
                        errors.append(dict(uuid=identity, rc=result.returncode, stderr=result.stderr))
                    else:
                        self.uuids.remove(identity)
                except subprocess.SubprocessError as error:
                    errors.append(dict(uuid=identity, error=repr(error)))
            self.save()
            after = self.network()
        finally:
            run(["sudo", "-n", "rm", "--", self.authorization])
        self.owner.receipt["fixtureCleanup"] = dict(errors=errors, networkAfter=after, networkUnchanged=after == self.before)
        self.owner.write()
        assert not errors and after == self.before, "fixture cleanup changed management routes/DNS/state"


class LiveEthernet:
    """A task-hotplugged virtio NIC, never the receipt's management NIC."""
    def __init__(self, owner, profiles):
        receipt = json.loads((owner.profile.workspace / "ethernet-fixture.json").read_text())
        assert receipt["guestUuid"] == owner.profile.uuid
        assert receipt["mac"] != owner.profile.mac
        interfaces = [p.parent.name for p in Path("/sys/class/net").glob("*/address") if p.read_text().strip() == receipt["mac"]]
        assert len(interfaces) == 1, "task Ethernet NIC identity unavailable"
        self.ifname = interfaces[0]
        assert self.ifname != "enp1s0"
        assert run(["nmcli", "-g", "GENERAL.TYPE", "device", "show", self.ifname]).stdout.strip() == "ethernet"
        self.profiles = profiles
        self.uuid = str(uuid.uuid4())
        profiles.uuids.append(self.uuid)
        profiles.save()
        profiles.command("connection", "add", "type", "ethernet", "ifname", self.ifname,
                         "con-name", "nm-events-ethernet", "connection.uuid", self.uuid,
                         "connection.autoconnect", "no", "ipv4.method", "manual", "ipv4.addresses", "198.19.0.2/24",
                         "ipv4.never-default", "yes", "ipv4.ignore-auto-dns", "yes", "ipv6.method", "disabled",
                         "ipv6.never-default", "yes", "ipv6.ignore-auto-dns", "yes")

    def up(self):
        self.profiles.command("connection", "up", "uuid", self.uuid)

    def change_address(self):
        self.profiles.command("device", "modify", self.ifname, "ipv4.addresses", "198.19.0.3/24")

    def down(self):
        self.profiles.command("connection", "down", "uuid", self.uuid)
