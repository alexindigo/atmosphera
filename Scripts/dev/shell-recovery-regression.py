#!/usr/bin/env python3
"""Guest-only recovery test: real shell, niri and portal consumer.

Run with --work NEW_DISK_BACKED_DIRECTORY inside the assigned Atmosphera VM.
The runner owns every child and restores the guest's niri base before exit.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from qml_probe import inject_probe
BACKEND = "org.freedesktop.impl.portal.desktop.atmosphera"
OBSERVER = '''
  FloatingWindow {
    visible: true
    implicitWidth: 600
    implicitHeight: 120
    TextInput { anchors.fill: parent; focus: true }
  }
  IpcHandler {
    target: "recoveryTest"
    function state(): string {
      return JSON.stringify({pid: Quickshell.processId, instance: Quickshell.instanceId, generation: "recovery-generation-1",
        initialized: IPCService.screenDetector !== null,
        launcher: Quickshell.screens.some(s => PanelService.isLauncherOpen(s)),
        requests: Object.values(FileChooserPortal.activeRequests).map(e => ({
          status: e.request.browser.status, path: e.request.browser.currentPath})),
        im: InputMethodService.currentIM, inhibitors: IdleInhibitorService.activeInhibitors});
    }
    function choose(path: string): void {
      var r = Object.values(FileChooserPortal.activeRequests)[0].request;
      r.selection.click(r.browser.indexOfPath(path), Qt.NoModifier);
      r.accept();
    }
    function quit(): void { Qt.quit(); }
  }
'''

# The elected-session probe must not exist in a queued shell. Observe that
# negative case from the registration owner, which exists before election.
ELECTION_OBSERVER = '''
  IpcHandler {
    target: "recoveryElection"
    function state(): string {
      return JSON.stringify({pid: Quickshell.processId, instance: Quickshell.instanceId,
        initialized: IPCService.screenDetector !== null});
    }
    function quit(): void { Qt.quit(); }
    function releaseElection(): void {
      root._elected = false;
      SessionBus.asyncCall({service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
        iface: "org.freedesktop.DBus", member: "ReleaseName", arguments: ["app.atmosphera.Shell"], signature: "s", timeout: 1000});
    }
  }
'''


def chooser(out, folder):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "recovery"
    handle = "/org/freedesktop/portal/desktop/request/" + bus.get_unique_name()[1:].replace(".", "_") + "/" + token
    result = {}
    loop = GLib.MainLoop()
    def response(*args):
        code, values = args[-1].unpack()
        result.update(response=code, results=values)
        loop.quit()
    bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response", handle, None, Gio.DBusSignalFlags.NONE, response)
    options = {"handle_token": GLib.Variant("s", token), "current_folder": GLib.Variant("ay", os.fsencode(folder) + b"\0")}
    bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser", "OpenFile",
                  GLib.Variant("(ssa{sv})", ("", "Recovery file chooser", options)), None, Gio.DBusCallFlags.NONE, 8000, None)
    GLib.timeout_add_seconds(15, lambda: (loop.quit(), False)[1])
    loop.run()
    Path(out).write_text(json.dumps(result))
    assert result.get("response") == 0, result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work", required=True, type=Path)
    ap.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument("--inside", action="store_true")
    ap.add_argument("--chooser", nargs=2)
    ap.add_argument("--hold-portal", action="store_true")
    ap.add_argument("--case", choices=("discovery", "smoke", "core-smoke", "fixture", "contention", "recovery", "exit-hang"), default="recovery")
    args = ap.parse_args()
    if args.hold_portal:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", GLib.Variant("(su)", (BACKEND, 4)), None, Gio.DBusCallFlags.NONE, 3000, None)
        (args.work / "holder-pid").write_text(str(os.getpid()))
        GLib.MainLoop().run()
        return
    if args.chooser:
        chooser(*args.chooser)
        return
    assert Path("/sys/class/dmi/id/sys_vendor").read_text().strip() == "QEMU", "VM only"
    assert any(str(args.work.resolve()).startswith(p) for p in ("/home/tester/Projects/shell-recovery/", "/home/tester/Projects/shell-exit/")), "assigned disk-backed workspace required"
    assert not args.work.resolve().is_relative_to(args.source.resolve()), "work must be outside source to avoid recursive copies"
    if not args.inside:
        args.work.mkdir(parents=True, exist_ok=False)
        (args.work / "tmp").mkdir()
        env = dict(os.environ, TMPDIR=str(args.work / "tmp"))
        subprocess.run(["timeout", "--kill-after=60", "200", sys.executable, "-B", __file__, *sys.argv[1:], "--inside"], env=env, check=True, timeout=265)
        return
    root = args.work.resolve()
    shell = root / "shell"
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns(".git"))
    if args.case == "fixture":
        (shell / "shell.qml").write_text((shell / "Scripts/dev/fixtures/filechooser-portal.qml").read_text())
    else:
        text = (shell / "shell.qml").read_text().replace("import QtQuick\n", "import QtQuick\nimport Quickshell.Io\n", 1)
        (shell / "shell.qml").write_text(inject_probe(text, OBSERVER))
        registration = shell / "Services/Session/ShellRegistration.qml"
        if registration.exists():  # Older discovery/contention baselines predate election.
            text = registration.read_text().replace("import QtQuick\n", "import QtQuick\nimport Quickshell.Io\nimport qs.Services.Control\n", 1)
            registration.write_text(inject_probe(text, ELECTION_OBSERVER, root_id="root"))
    for name in ("config/atmosphera", "config/niri", "config/fcitx5", "config/xdg-desktop-portal", "data", "state", "cache", "chosen"):
        (root / name).mkdir(parents=True)
    defaults = json.loads((shell / "Configs/defaults.json").read_text())
    defaults["general"]["showChangelogOnStartup"] = False
    defaults["inputMethod"].update(launchFcitx5=False, legacyI18nChecked=True,
        switches=[{"keys": ["Super+Space"], "target": "keyboard-ru", "mode": "toggle", "label": "Russian"}])
    (root / "config/atmosphera/settings.json").write_text(json.dumps(defaults))
    cli = shell / "Scripts/bash/atmosphera"
    (root / "config/niri/config.kdl").write_text('input { keyboard { xkb { layout "us,ru"; }; }; }\nbinds { Ctrl+Space { spawn "' + str(cli) + '" "ipc" "launcher" "toggle"; }; }\n')
    (root / "config/xdg-desktop-portal/portals.conf").write_text("[preferred]\ndefault=atmosphera\n")
    (root / "config/fcitx5/profile").write_text("[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=keyboard-us\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=keyboard-ru\nLayout=\n\n[GroupOrder]\n0=Default\n")
    fixture = root / "chosen/Chosen.txt"
    fixture.write_text("Recovery consumer fixture\n")
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"), XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
               XDG_CURRENT_DESKTOP="niri", PATH=str(cli.parent) + ":" + os.environ["PATH"], QT_IM_MODULE="fcitx", ATMOSPHERA_DEBUG="0", TMPDIR=str(root / "tmp"), YDOTOOL_SOCKET=str(root / "ydotool.sock"))
    children, logs, cases, shell_fds = [], [], [], {}
    def command(argv, check=True, seconds=12):
        return subprocess.run(["timeout", "--kill-after=2", str(seconds), *map(str, argv)], env=env, capture_output=True, text=True, timeout=seconds + 3, check=check)
    def launch(argv, name):
        log = (root / (name + ".log")).open("w")
        logs.append(log)
        p = subprocess.Popen(["timeout", "180", *map(str, argv)], env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        children.append(p)
        return p
    def wait(predicate, seconds=18):
        end, last = time.monotonic() + seconds, None
        while time.monotonic() < end:
            try:
                last = predicate()
                if last:
                    return last
            except (subprocess.SubprocessError, ValueError, KeyError):
                pass
            time.sleep(.2)
        raise AssertionError("timed out: " + repr(last))
    def state():
        value = json.loads(command(["qs", "-p", shell, "ipc", "call", "filechooserRegression" if args.case == "fixture" else "recoveryTest", "state"]).stdout)
        pid = value.get("pid")
        if pid and pid not in shell_fds:
            shell_fds[pid] = os.pidfd_open(pid)
        return value
    def check(name, condition):
        cases.append({"case": name, "pass": bool(condition)})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    def bus(*argv):
        return command(["busctl", "--user", "--timeout=2", *argv])
    def key(mod):
        command(["ydotool", "key", f"{mod}:1", "57:1", "57:0", f"{mod}:0"])
    def flows(label):
        introspection = bus("introspect", BACKEND, "/org/freedesktop/portal/desktop").stdout
        check(label + "-all-portal-interfaces", all("org.freedesktop.impl.portal." + i in introspection for i in ("Settings", "FileChooser", "Inhibit")))
        check(label + "-settings-consumer", "u " in bus("call", "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "ReadOne", "ss", "org.freedesktop.appearance", "color-scheme").stdout)
        handle = "/org/freedesktop/portal/desktop/request/recovery/" + label.replace("-", "_")
        bus("call", BACKEND, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.Inhibit", "Inhibit", "ossua{sv}", handle, "dev.recovery.Test", "", "8", "0")
        wait(lambda: "portal:" + handle in state()["inhibitors"])
        check(label + "-inhibit-reaches-idle-consumer", True)
        bus("call", BACKEND, handle, "org.freedesktop.impl.portal.Request", "Close")
        wait(lambda: "portal:" + handle not in state()["inhibitors"])
        check(label + "-inhibit-close-releases-consumer", True)
        check(label + "-cli-discovers-path-shell", command([cli, "ipc", "inputmethod", "state"], False).returncode == 0)
        key(29)
        wait(lambda: state()["launcher"])
        check(label + "-launcher-key-opens", state()["launcher"])
        key(29)
        wait(lambda: not state()["launcher"])
        check(label + "-launcher-key-closes", not state()["launcher"])
        check(label + "-input-reset", command([cli, "ipc", "inputmethod", "setIM", "keyboard-us"]).stdout.strip() == "ok")
        wait(lambda: state()["im"] == "keyboard-us")
        key(125)
        wait(lambda: state()["im"] == "keyboard-ru")
        check(label + "-input-key-switches-fcitx5", "keyboard-ru" in bus("call", "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", "CurrentInputMethod").stdout)
        out = root / (label + "-chooser.json")
        p = launch([sys.executable, "-B", __file__, "--work", root, "--chooser", out, fixture.parent], label + "-chooser")
        wait(lambda: state()["requests"] and state()["requests"][0]["status"] == "ready")
        command(["qs", "-p", shell, "ipc", "call", "recoveryTest", "choose", fixture])
        p.wait(timeout=18)
        check(label + "-chooser-consumer-uri", p.returncode == 0 and json.loads(out.read_text())["results"]["uris"] == [fixture.as_uri()])
        owner_pid = bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.freedesktop.Notifications").stdout
        check(label + "-notifications-owner", owner_pid.strip() == "u " + str(state()["pid"]))
        reply = bus("call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "susssasa{sv}i", "Recovery", "0", "", label, "body", "0", "0", "1000")
        check(label + "-notifications-consumer", reply.stdout.startswith("u "))
    failure = None
    switched = False
    def deadline(_signum, _frame):
        raise TimeoutError("recovery deadline reached")
    signal.signal(signal.SIGTERM, deadline)
    try:
        launch(["ydotoold", "--socket-path=" + env["YDOTOOL_SOCKET"]], "input")
        wait(lambda: Path(env["YDOTOOL_SOCKET"]).exists())
        time.sleep(1)
        launch(["fcitx5", "--replace"], "fcitx5")
        holder = None
        if args.case in ("contention", "recovery"):
            holder = launch([sys.executable, "-B", __file__, "--work", root, "--hold-portal"], "holder")
            wait(lambda: (root / "holder-pid").exists())
        started = time.monotonic()
        process = launch(["qs", "-p", shell], "shell")
        if args.case == "fixture":
            wait(lambda: state()["portalReady"])
            launch(["/usr/lib/xdg-desktop-portal", "--replace", "--verbose"], "portal")
            out = root / "fixture-chooser.json"
            consumer = launch([sys.executable, "-B", __file__, "--work", root, "--chooser", out, fixture.parent], "fixture-chooser")
            wait(lambda: state()["requests"] and state()["requests"][0]["status"] == "ready")
            command(["qs", "-p", shell, "ipc", "call", "filechooserRegression", "select", fixture])
            command(["qs", "-p", shell, "ipc", "call", "filechooserRegression", "accept"])
            consumer.wait(timeout=18)
            check("existing-filechooser-fixture-consumer", consumer.returncode == 0 and json.loads(out.read_text())["results"]["uris"] == [fixture.as_uri()])
            command(["qs", "-p", shell, "ipc", "call", "filechooserRegression", "quit"])
            process.wait(timeout=12)
            check("existing-filechooser-fixture-clean-exit", process.returncode == 0)
            return
        initial = wait(lambda: (s := state())["initialized"] and s)
        check("cold-load", process.poll() is None)
        if args.case == "exit-hang":
            wait(lambda: bus("get-property", "app.atmosphera.Shell", "/app/atmosphera/Shell", "app.atmosphera.Shell1", "PortalReady").stdout.strip() == "b true")
            wait(lambda: state()["im"])
            launch(["/usr/lib/xdg-desktop-portal", "--replace", "--verbose"], "portal")
            contender = root / "contender"
            shutil.copytree(shell, contender)
            handoff = launch(["qs", "-p", contender], "normal-handoff")
            time.sleep(.5)
            command(["qs", "ipc", "--pid", str(initial["pid"]), "call", "recoveryElection", "quit"])
            shell = contender
            wait(lambda: (s := state())["pid"] != initial["pid"] and s["initialized"] and s)
            check("queued-shell-survives-normal-handoff", handoff.poll() is None)
            check("normal-handoff-no-term-kill", "SIGTERM" not in (root / "normal-handoff.log").read_text() and "SIGKILL" not in (root / "normal-handoff.log").read_text())
            normal = command([cli, "session", "launch", contender], seconds=30)
            (root / "normal-switch.log").write_text(normal.stdout + normal.stderr)
            switched = True
            shell = contender
            replacement = wait(lambda: (s := state())["pid"] != initial["pid"] and s["initialized"] and s)
            check("normal-exit-no-term-kill", "SIGTERM" not in normal.stderr and "SIGKILL" not in normal.stderr)
            flows("normal")
            # SIGSTOP leaves the process, sockets and all bus names alive. Its
            # graceful IPC request cannot finish; TERM also cannot be handled.
            os.kill(replacement["pid"], signal.SIGSTOP)
            stuck = command([cli, "session", "launch", contender], seconds=35)
            (root / "stopped-switch.log").write_text(stuck.stdout + stuck.stderr)
            check("switcher-escalates-pinned-owner", all(x in stuck.stderr for x in ("PID " + str(replacement["pid"]), "SIGTERM", "SIGKILL")))
            replacement = wait(lambda: (s := state())["pid"] != replacement["pid"] and s["initialized"] and s)
            flows("after-stuck-switch")
            os.kill(replacement["pid"], signal.SIGSTOP)
            other = root / "raw"
            shutil.copytree(shell, other)
            raw = launch(["qs", "-p", other], "stopped-raw")
            shell = other
            recovered = wait(lambda: (s := state())["pid"] != replacement["pid"] and s["initialized"] and s, 45)
            check("raw-spawn-elected", recovered["pid"] != replacement["pid"] and raw.poll() is None)
            text = (root / "stopped-raw.log").read_text()
            check("raw-spawn-escalates-pinned-owner", all(x in text for x in ("PID " + str(replacement["pid"]), "SIGTERM", "SIGKILL")))
            flows("after-stuck-raw")
            os.kill(recovered["pid"], signal.SIGSTOP)
            reuse = command([cli, "run", "-p", other, "-d"], seconds=40)
            (root / "stopped-cli.log").write_text(reuse.stdout + reuse.stderr)
            check("cli-does-not-reuse-unresponsive-owner", "already running" not in reuse.stdout and "SIGKILL" in reuse.stderr)
            recovered = wait(lambda: (s := state())["pid"] != recovered["pid"] and s["initialized"] and s)
            flows("after-stuck-cli")
            duplicate = launch(["qs", "-p", contender], "responsive-duplicate")
            duplicate.wait(timeout=8)
            check("responsive-duplicate-exits", duplicate.returncode == 0)
            check("responsive-owner-not-killed", state()["pid"] == recovered["pid"])
            check("responsive-duplicate-diagnosed", "another shell is running (pid " + str(recovered["pid"]) + ")" in (root / "responsive-duplicate.log").read_text())
            check("responsive-duplicate-no-signals", "SIGTERM" not in (root / "responsive-duplicate.log").read_text() and "SIGKILL" not in (root / "responsive-duplicate.log").read_text())
            # Model Qt's later teardown stage: Shell election released, but
            # Notifications and the same-path Quickshell instance lock remain.
            command(["qs", "ipc", "--pid", str(recovered["pid"]), "call", "recoveryElection", "releaseElection"])
            wait(lambda: command(["busctl", "--user", "--timeout=1", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", "s", "app.atmosphera.Shell"], False).returncode != 0)
            os.kill(recovered["pid"], signal.SIGSTOP)
            check("departed-shell-retains-notifications", bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.freedesktop.Notifications").stdout.strip() == "u " + str(recovered["pid"]))
            departed = command([cli, "run", "-p", other, "-d"], seconds=35)
            (root / "departed-cli.log").write_text(departed.stdout + departed.stderr)
            check("cli-reaps-departed-same-path-instance", all(x in departed.stderr for x in ("PID " + str(recovered["pid"]), "SIGTERM", "SIGKILL", "retained resources")))
            recovered = wait(lambda: (s := state())["pid"] != recovered["pid"] and s["initialized"] and s)
            flows("after-departed-cli")
            command(["qs", "ipc", "--pid", str(recovered["pid"]), "call", "recoveryElection", "releaseElection"])
            wait(lambda: command(["busctl", "--user", "--timeout=1", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", "s", "app.atmosphera.Shell"], False).returncode != 0)
            os.kill(recovered["pid"], signal.SIGSTOP)
            no_name = root / "raw-departed"
            shutil.copytree(shell, no_name)
            launch(["qs", "-p", no_name], "departed-raw")
            shell = no_name
            newer = wait(lambda: (s := state())["pid"] != recovered["pid"] and s["initialized"] and s, 35)
            check("raw-reaps-departed-owner-before-session-init", "SIGKILL" in (root / "departed-raw.log").read_text())
            recovered = newer
            flows("after-departed-raw")
            final_stop = command([cli, "session", "stop"], seconds=30)
            (root / "final-stop.log").write_text(final_stop.stdout + final_stop.stderr)
            switched = False
            check("final-successor-no-term-kill", "SIGTERM" not in final_stop.stderr and "SIGKILL" not in final_stop.stderr)
            stop_only = launch(["qs", "-p", shell], "stop-only-shell")
            last = wait(lambda: (s := state())["pid"] != recovered["pid"] and s["initialized"] and s)
            os.kill(last["pid"], signal.SIGSTOP)
            stopped = command([cli, "session", "stop"], seconds=35)
            (root / "stopped-stop.log").write_text(stopped.stdout + stopped.stderr)
            stop_only.wait(timeout=8)
            check("stop-only-escalates-pinned-owner", all(x in stopped.stderr for x in ("PID " + str(last["pid"]), "SIGTERM", "SIGKILL")))
            check("stop-only-releases-election", command(["busctl", "--user", "--timeout=1", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", "s", "app.atmosphera.Shell"], False).returncode != 0)
            return
        if args.case in ("discovery", "smoke", "core-smoke"):
            if args.case != "core-smoke":
                result = command([cli, "ipc", "inputmethod", "state"], False)
                check("cli-discovers-path-shell", result.returncode == 0)
            wait(lambda: bus("get-property", "app.atmosphera.Shell", "/app/atmosphera/Shell", "app.atmosphera.Shell1", "PortalReady").stdout.strip() == "b true")
            command(["qs", "-p", shell, "ipc", "call", "recoveryTest", "quit"])
            process.wait(timeout=12)
            check("cold-load-clean-exit", process.returncode == 0)
            return
        check("busy-portal-owner-not-replaced", str((root / "holder-pid").read_text()) in bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", BACKEND).stdout)
        if args.case == "recovery":
            check("busy-portal-status-is-not-ready", bus("get-property", "app.atmosphera.Shell", "/app/atmosphera/Shell", "app.atmosphera.Shell1", "Status").stdout.strip() == 's "acquired"')
        os.killpg(holder.pid, signal.SIGTERM)
        holder.wait(timeout=8)
        wait(lambda: str(initial["pid"]) in bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", BACKEND).stdout)
        check("portal-reacquired-after-owner-departure", True)
        if args.case == "contention":
            return
        wait(lambda: (root / "config/niri/atmosphera-session.kdl").exists())
        wait(lambda: state()["im"])
        launch(["/usr/lib/xdg-desktop-portal", "--replace", "--verbose"], "portal")
        wait(lambda: bus("status", "org.freedesktop.portal.Desktop").returncode == 0)
        flows("before")
        contender = root / "contender"
        shutil.copytree(shell, contender)
        session_file = root / "config/niri/atmosphera-session.kdl"
        session_before = session_file.stat().st_mtime_ns
        duplicate = launch(["qs", "-p", contender], "contender")
        duplicate_state = wait(lambda: (s := json.loads(command(["qs", "-p", contender, "ipc", "--newest", "call", "recoveryElection", "state"]).stdout))["pid"] != initial["pid"] and s)
        time.sleep(.5)
        check("queued-shell-does-not-initialize-session", not duplicate_state["initialized"] and session_file.stat().st_mtime_ns == session_before)
        check("queued-shell-has-no-session-probe", "recoveryTest" not in command(["qs", "ipc", "--pid", str(duplicate_state["pid"]), "show"]).stdout)
        check("queued-shell-does-not-replace-owner", str(initial["pid"]) in bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "app.atmosphera.Shell").stdout)
        command(["qs", "ipc", "--pid", str(duplicate_state["pid"]), "call", "recoveryElection", "quit"])
        duplicate.wait(timeout=12)
        check("queued-shell-clean-exit", duplicate.returncode == 0)
        # Quickshell deliberately refuses auto-restart during its first 10 s.
        time.sleep(max(0, 11 - (time.monotonic() - started)))
        os.kill(initial["pid"], signal.SIGSEGV)
        restarted = wait(lambda: (s := state())["instance"] != initial["instance"] and s["initialized"] and s, 35)
        check("quickshell-auto-restarted", restarted["pid"] == initial["pid"] and restarted["instance"] != initial["instance"])
        flows("after-crash")
        qml = shell / "shell.qml"
        qml.write_text(qml.read_text().replace("recovery-generation-1", "recovery-generation-2"))
        wait(lambda: (s := state())["generation"] == "recovery-generation-2" and s["initialized"] and s)
        check("supported-live-reload-completed", True)
        flows("after-reload")
        switch_reply = command([cli, "session", "launch", contender])
        (root / "switch.log").write_text(switch_reply.stdout + switch_reply.stderr)
        switched = True
        shell = contender
        replacement = wait(lambda: (s := state())["pid"] != initial["pid"] and s["initialized"] and s)
        check("switcher-targets-registered-dev-owner", replacement["pid"] != initial["pid"])
        check("launch-reuses-elected-shell", "already running" in command([cli]).stdout)
        wait(lambda: (s := state())["im"] and s)
        flows("after-switch")
        command([cli, "session", "stop"])
        switched = False
        process.wait(timeout=12)
        # Quickshell 0.3.2 falls through to runCommand(argc=1) after its
        # recovered launch returns (src/launch/main.cpp:67,122-123). Its
        # default-config diagnostic/255 is upstream, not another shell crash.
        check("recovered-shell-released-registration", command(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", "s", "app.atmosphera.Shell"], False).returncode != 0)
        check("known-quickshell-recovery-exit", process.returncode == 0 or (process.returncode == 255 and 'Could not find "default" config directory' in (root / "shell.log").read_text()))
    except BaseException as error:
        failure = repr(error)
        raise
    finally:
        # A second termination must not interrupt restoration or receipt writing.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_errors = []
        def cleanup_command(name, argv):
            try:
                reply = command(argv, False)
                if reply.returncode != 0:
                    cleanup_errors.append(f"{name}: exit {reply.returncode}: {reply.stderr[-512:]}")
            except Exception as error:
                cleanup_errors.append(f"{name}: {error!r}")
        if switched:
            cleanup_command("session stop", [cli, "session", "stop"])
        cleanup_command("restore niri", ["niri", "msg", "action", "load-config-file", "--path", "/home/tester/.config/niri/config.kdl"])
        # Switcher children are daemonized, outside launch()'s process groups.
        # pidfds retain their exact identity even after process exit/PID reuse.
        import select
        for pid, fd in shell_fds.items():
            try:
                if not select.select([fd], [], [], 0)[0]:
                    signal.pidfd_send_signal(fd, signal.SIGTERM)
                    if not select.select([fd], [], [], 2)[0]:
                        signal.pidfd_send_signal(fd, signal.SIGKILL)
                        if not select.select([fd], [], [], 5)[0]:
                            cleanup_errors.append(f"shell {pid} did not exit")
            except ProcessLookupError:
                pass
            finally:
                os.close(fd)
        for child in reversed(children):
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except OSError as error:
                cleanup_errors.append(f"terminate child {child.pid}: {error!r}")
        end = time.monotonic() + 8
        for child in reversed(children):
            try:
                child.wait(timeout=max(.1, end - time.monotonic()))
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)
                except (OSError, subprocess.SubprocessError) as error:
                    cleanup_errors.append(f"reap child {child.pid}: {error!r}")
        for log in logs:
            try:
                log.close()
            except OSError as error:
                cleanup_errors.append(f"close log: {error!r}")
        (root / "result.json").write_text(json.dumps({"cases": cases, "failure": failure,
                                                    "cleanup_errors": cleanup_errors}, indent=2))
        if cleanup_errors and failure is None:
            raise RuntimeError("recovery cleanup failed: " + "; ".join(cleanup_errors))


if __name__ == "__main__":
    main()
