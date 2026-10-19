"""Shared guest-only F4 transport, reusing F3's isolated-bus recipe.

The real frontend daemon must route to this exact Atmosphera process. Every
suite owns a fresh disk-backed profile, private bus and bounded children.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")
SCRIPTS = Path(__file__).resolve().parent


def guest():
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    assert "52:54:00:50:b3:8b" in [p.read_text().strip() for p in Path("/sys/class/net").glob("*/address")]
    assert Path(os.environ["TMPDIR"]).resolve().is_relative_to(ROOT)


class Run:
    def __init__(self, source, label):
        guest()
        assert re.fullmatch(r"f4-[a-z0-9.-]+", label)
        self.source = Path(source).resolve()
        assert self.source.is_relative_to(ROOT / "sources") and self.source.is_dir()
        self.runtime, self.output = ROOT / "runtime" / label, ROOT / "evidence" / label
        assert not self.runtime.exists() and not self.output.exists()
        self.runtime.mkdir(); self.output.mkdir()
        self.shell = self.runtime / "shell"
        shutil.copytree(self.source, self.shell, symlinks=True)
        self.profile = self.runtime / "profile"
        for name in ("config", "cache", "state", "data", "tmp"):
            (self.profile / name).mkdir(parents=True)
        defaults = json.loads((self.source / "Configs/defaults.json").read_text())
        defaults["general"]["showChangelogOnStartup"] = False
        (self.profile / "config/settings.json").write_text(json.dumps(defaults))
        self.fixtures = self.runtime / "Chosen"
        self.fixtures.mkdir()
        (self.fixtures / "Chosen.txt").write_text("F4 consumer fixture\n")
        # The actual settings picker filters PNG/SVG. Reuse F3's valid 1px PNG.
        import struct
        import zlib
        def chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        (self.fixtures / "Icon.png").write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\x00\x00\x80\xff\xff")) + chunk(b"IEND", b""))
        self.env = dict(os.environ, TMPDIR=str(self.profile / "tmp"),
                        XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1",
                        NIRI_SOCKET=str(next(Path("/run/user/1000").glob("niri.*.sock"))),
                        LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", XDG_CURRENT_DESKTOP="niri",
                        XDG_CONFIG_HOME=str(self.profile / "config"), XDG_DATA_HOME=str(self.profile / "data"),
                        ATMOSPHERA_CONFIG_DIR=str(self.profile / "config") + "/",
                        ATMOSPHERA_CACHE_DIR=str(self.profile / "cache") + "/",
                        ATMOSPHERA_STATE_DIR=str(self.profile / "state") + "/",
                        ATMOSPHERA_SETTINGS_FILE=str(self.profile / "config/settings.json"),
                        ATMOSPHERA_DEBUG="0", F4_FIXTURES=str(self.fixtures),
                        YDOTOOL_SOCKET=str(self.runtime / "input.sock"),
                        DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(self.runtime / "bus.sock"))
        self.processes, self.logs, self.cases, self.commands = [], [], [], []
        self.complete = False
        self.failure = ""
        self.qs = None
        self.probe = self.shell / "f4-probe.qml"

    def launch(self, argv, log):
        f = (self.output / log).open("w")
        self.logs.append(f)
        self.commands.append(list(map(str, argv)))
        p = subprocess.Popen(list(map(str, argv)), env=self.env, cwd=self.shell, stdout=f, stderr=subprocess.STDOUT)
        self.processes.append(p)
        return p

    def command(self, argv):
        return subprocess.run(["timeout", "12", *map(str, argv)], env=self.env, cwd=self.shell,
                              capture_output=True, text=True, check=True, timeout=18).stdout.strip()

    def ipc(self, member, *args):
        return self.command(["qs", "-p", self.probe, "ipc", "call", "f4", member, *args])

    def state(self):
        return json.loads(self.ipc("state"))

    def wait(self, predicate, seconds=12):
        end = time.monotonic() + seconds
        last = None
        while time.monotonic() < end:
            try:
                last = self.state()
                if predicate(last):
                    return last
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.15)
        raise AssertionError("Timed out: " + json.dumps(last))

    def check(self, name, condition, detail=None):
        self.cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name

    def key(self, code, modifier=None):
        self.command(["ydotool", "key", *([f"{modifier}:1"] if modifier else []),
                      f"{code}:1", f"{code}:0", *([f"{modifier}:0"] if modifier else [])])
        time.sleep(.2)

    def bus(self, method, signature, *args):
        return self.command(["busctl", "--address=" + self.env["DBUS_SESSION_BUS_ADDRESS"], "call",
                             "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                             method, signature, *args])

    def start(self, frontend=True, qml=None):
        self.probe.write_text(qml if qml is not None else (SCRIPTS / "fixtures/filechooser-portal.qml").read_text())
        # Same session policy as /usr/share/dbus-1/session.conf, without service
        # activation directories. All services are explicit owned children;
        # after daemon loss the missing-service case cannot autoactivate one.
        config = self.runtime / "bus.conf"
        config.write_text('<busconfig><type>session</type><listen>' + self.env["DBUS_SESSION_BUS_ADDRESS"] +
                          '</listen><auth>EXTERNAL</auth><policy context="default">'
                          '<allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/>'
                          '<allow own="*"/></policy></busconfig>')
        self.launch(["timeout", "720", "dbus-daemon", "--nofork", "--config-file=" + str(config)], "bus.log")
        deadline = time.monotonic() + 8
        while not (self.runtime / "bus.sock").exists() and time.monotonic() < deadline:
            time.sleep(.1)
        self.launch(["sudo", "-n", "env", "TMPDIR=" + self.env["TMPDIR"], "timeout", "720", "ydotoold",
                     "--socket-path=" + self.env["YDOTOOL_SOCKET"], "--socket-perm=0666"], "input.log")
        self.qs = self.launch(["timeout", "720", "qs", "-p", self.probe], "shell.log")
        self.wait(lambda s: not s["requests"])
        self.launch(["timeout", "720", "busctl", "--address=" + self.env["DBUS_SESSION_BUS_ADDRESS"],
                     "--json=short", "monitor"], "wire.jsonl")
        pid = int(self.bus("GetConnectionUnixProcessID", "s", "org.freedesktop.impl.portal.desktop.atmosphera").split()[1])
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
        self.check("backend-is-this-atmosphera-process", str(self.probe) in cmdline, {"pid": pid, "command": cmdline})
        if frontend:
            self.start_frontend()
        return self

    def start_frontend(self):
        self.portal = self.launch(["timeout", "720", "/usr/lib/xdg-desktop-portal", "--replace", "--verbose"], "portal.log")
        time.sleep(3)
        self.frontend_pid = int(self.bus("GetConnectionUnixProcessID", "s", "org.freedesktop.portal.Desktop").split()[1])
        self.check("frontend-is-owned-test-daemon", Path(f"/proc/{self.frontend_pid}/stat").read_text().split()[3] == str(self.portal.pid), {"pid": self.frontend_pid, "parent": self.portal.pid})

    def call(self, method, **options):
        out = self.output / f"{len(self.commands)}-{method}.json"
        proc = self.launch(["timeout", "40", "python3", "-B", SCRIPTS / "filechooser-portal-regression.py", "--call", method,
                            "--options", json.dumps(options), "--out", out], out.stem + ".log")
        self.wait(lambda s: len(s["requests"]) == 1 and s["requests"][0]["status"] == "ready")
        s = self.state()["requests"][0]
        self.check(method + "-routed-to-Atmosphera", s["title"] == "F4 " + method, s)
        return proc, out

    def result(self, proc, out):
        proc.wait(timeout=35)
        data = json.loads(out.read_text())
        self.check(data["method"] + "-response-once", proc.returncode == 0 and data["count"] == 1, data)
        self.wait(lambda s: not s["requests"])
        return data

    def finish(self):
        self.ipc("quit")
        self.qs.wait(timeout=12)
        errors = [l for l in (self.output / "shell.log").read_text().splitlines()
                  if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", l)]
        self.check("runtime-errors", self.qs.returncode == 0 and not errors, errors)
        self.complete = True

    def close(self):
        if self.qs and self.qs.poll() is None:
            try:
                self.ipc("quit"); self.qs.wait(timeout=12)
            except Exception as error:
                self.failure += " graceful quit: " + repr(error)
        for proc in reversed(self.processes):
            if proc.poll() is None and proc is not self.qs:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
        for f in self.logs:
            f.close()
        (self.output / "recipe.json").write_text(json.dumps({"source": str(self.source), "runtime": str(self.runtime),
            "commands": self.commands, "environment": {k: v for k, v in self.env.items() if k.startswith(("ATMOSPHERA_", "XDG_", "DBUS_", "F4_", "TMPDIR", "YDOTOOL_", "WAYLAND_", "NIRI_"))}}, indent=2))
        (self.output / "probe.qml").write_text(self.probe.read_text() if self.probe.exists() else "")
        (self.output / "result.json").write_text(json.dumps({"complete": self.complete, "passed": self.complete and all(c["pass"] for c in self.cases),
            "cases": self.cases, "failure": self.failure, "qs_exit": self.qs.poll() if self.qs else None}, indent=2))
