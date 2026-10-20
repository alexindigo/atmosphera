"""Guest-only boundary for chooser tooling, including the exact-source gate.

Every entry point calls enter() before doing work. Nested drivers inherit the
same checked environment and cgroup; they never discover a login compositor.
"""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
import time

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")


def guest():
    assert os.getuid() == 1000 and pwd.getpwuid(os.getuid()).pw_dir == "/home/tester"
    assert "52:54:00:50:b3:8b" in [p.read_text().strip() for p in Path("/sys/class/net").glob("*/address")]
    assert Path(os.environ["TMPDIR"]).resolve().is_relative_to(ROOT)


def cgroup():
    return Path("/sys/fs/cgroup") / Path("/proc/self/cgroup").read_text().strip().split("::", 1)[1].lstrip("/")


def checked():
    guest()
    base = Path(os.environ["FILECHOOSER_ISOLATION"])
    assert base.resolve().is_relative_to(ROOT / "runtime")
    assert Path.home() == base / "home"
    assert Path(os.environ["XDG_RUNTIME_DIR"]) == base / "run"
    assert os.environ["WAYLAND_DISPLAY"] == "wayland-1"
    assert "NIRI_SOCKET" not in os.environ
    assert os.environ["DBUS_SESSION_BUS_ADDRESS"] == "unix:path=" + str(base / "run/bus")
    assert (cgroup() / "memory.max").read_text().strip() != "max"
    assert (cgroup() / "cpu.max").read_text().split()[0] != "max"
    return base


def enter():
    """Re-exec this entry point in a bounded disposable session, or validate it."""
    guest()
    if "FILECHOOSER_ISOLATION" in os.environ:
        checked()
        return
    args = sys.argv[1:]
    if "--label" in args:
        label = args[args.index("--label") + 1]
    elif "--output" in args:
        label = Path(args[args.index("--output") + 1]).name
    else:
        raise ValueError("isolated entry point requires --label or --output")
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", label)
    base = ROOT / "runtime" / ("i" + hashlib.sha256(label.encode()).hexdigest()[:8])
    output = ROOT / "evidence" / (label + "-isolation")
    base.mkdir(); output.mkdir()
    # Serialize private workloads: multiple individually bounded services must
    # not collectively starve the login session. The lock is held until systemd
    # has reaped the entire service cgroup, including detached shell children.
    with (ROOT / "runtime/.filechooser-isolation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        ram = int(next(l.split()[1] for l in Path("/proc/meminfo").read_text().splitlines() if l.startswith("MemTotal:"))) * 1024
        maximum = ram // 4 // (1024 * 1024) * 1024 * 1024
        high = maximum * 3 // 4
        env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus")
        command = ["systemd-run", "--user", "--wait", "--pipe", "--collect",
                   "--unit=filechooser-" + label, "--service-type=exec",
                   "--setenv=TMPDIR=" + str(ROOT / "tmp"),
                   "-p", f"MemoryMax={maximum}", "-p", f"MemoryHigh={high}",
                   "-p", "MemorySwapMax=0", "-p", "CPUQuota=100%", "-p", "TasksMax=256",
                   "-p", "RuntimeMaxSec=840", "-p", "TimeoutStopSec=10", "-p", "OOMPolicy=stop",
                   "--working-directory=" + str(ROOT), sys.executable, "-B", str(Path(__file__).resolve()),
                   "--session", str(base), str(output), str(Path(sys.argv[0]).resolve()), *args]
        (output / "unit.json").write_text(json.dumps({"command": command, "ram": ram, "memory_max": maximum, "memory_high": high, "cpu_quota": "100%"}, indent=2))
        result = subprocess.run(["timeout", "880", *command], env=env, timeout=890)
    raise SystemExit(result.returncode)


def profile_env(profile):
    """A suite-specific profile within the already isolated service."""
    checked()
    for name in ("config", "cache", "state", "data", "tmp"):
        (profile / name).mkdir(parents=True, exist_ok=True)
    return dict(os.environ, TMPDIR=str(profile / "tmp"),
                XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"),
                XDG_STATE_HOME=str(profile / "state"), XDG_DATA_HOME=str(profile / "data"),
                ATMOSPHERA_CONFIG_DIR=str(profile / "config") + "/",
                ATMOSPHERA_CACHE_DIR=str(profile / "cache") + "/",
                ATMOSPHERA_STATE_DIR=str(profile / "state") + "/",
                ATMOSPHERA_SETTINGS_FILE=str(profile / "config/settings.json"))


def input_command(argv):
    """Translate the existing driver's Linux key vocabulary to virtual keys."""
    checked()
    assert argv[0] == "ydotool"
    if argv[1] == "type":
        return ["wtype", "--", *argv[2:]] if argv[2:3] != ["--"] else ["wtype", *argv[2:]]
    assert argv[1] == "key"
    keys = {1: "Escape", 14: "BackSpace", 15: "Tab", 28: "Return", 30: "a", 35: "h", 38: "l", 57: "space",
            102: "Home", 103: "Up", 105: "Left", 106: "Right", 107: "End", 108: "Down", 111: "Delete"}
    modifiers = {29: "ctrl", 42: "shift", 56: "alt"}
    command = ["wtype"]
    for event in argv[2:]:
        code, down = map(int, event.split(":"))
        command += (["-M" if down else "-m", modifiers[code]] if code in modifiers
                    else ["-P" if down else "-p", keys[code]])
    return command


def session(base, output, argv):
    guest()
    # Keep serialization in the service as well as the invoking client. An
    # interrupted SSH/systemd-run client must not release the workload lock.
    guard = None
    if "FILECHOOSER_ISOLATION" not in os.environ:
        guard = (ROOT / "runtime/.filechooser-service.lock").open("a")
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
    for name in ("home", "run", "tmp", "config", "cache", "state", "data"):
        (base / name).mkdir(mode=0o700)
    env = {"PATH": "/usr/local/bin:/usr/bin", "USER": "tester", "LOGNAME": "tester", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "HOME": str(base / "home"), "TMPDIR": str(base / "tmp"), "XDG_RUNTIME_DIR": str(base / "run"),
           "XDG_CONFIG_HOME": str(base / "config"), "XDG_CACHE_HOME": str(base / "cache"),
           "XDG_STATE_HOME": str(base / "state"), "XDG_DATA_HOME": str(base / "data"),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(base / "run/bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(base / "run/no-system-bus"),
           "FILECHOOSER_ISOLATION": str(base), "XDG_CURRENT_DESKTOP": "sway", "QT_QPA_PLATFORM": "wayland",
           "QT_FORCE_STDERR_LOGGING": "1", "ATMOSPHERA_DEBUG": "0", "ATMOSPHERA_UPGRADELOG_URL": "http://127.0.0.1:9",
           "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_HEADLESS_OUTPUTS": "1",
           "LIBGL_ALWAYS_SOFTWARE": "1", "QT_QUICK_BACKEND": "software"}
    config = base / "sway.conf"
    config.write_text("output HEADLESS-1 mode 1280x800\nseat seat0 fallback true\nxwayland disable\n")
    bus_config = base / "bus.conf"
    bus_config.write_text('<busconfig><type>session</type><listen>' + env["DBUS_SESSION_BUS_ADDRESS"] +
                          '</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*" eavesdrop="true"/>'
                          '<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>')
    children = []
    try:
        for command, name in ((["dbus-daemon", "--nofork", "--config-file=" + str(bus_config)], "bus"),
                              (["sway", "--unsupported-gpu", "-c", str(config)], "compositor")):
            with (output / (name + ".log")).open("w") as log:
                children.append(subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT))
        end = time.monotonic() + 15
        while time.monotonic() < end:
            sockets = list((base / "run").glob("sway-ipc.*.sock"))
            displays = list((base / "run").glob("wayland-*"))
            displays = [p for p in displays if not p.name.endswith(".lock")]
            if sockets and displays and (base / "run/bus").exists():
                break
            assert all(p.poll() is None for p in children), "private session startup failed"
            time.sleep(.1)
        assert len(sockets) == len(displays) == 1
        env.update(SWAYSOCK=str(sockets[0]), WAYLAND_DISPLAY=displays[0].name)
        assert env["WAYLAND_DISPLAY"] == "wayland-1"
        # A headless seat has no keyboard capability until a virtual keyboard
        # connects. Keep one connection alive so focus survives between the
        # driver's short-lived wtype commands; never open /dev/input or uinput.
        with (output / "keyboard.log").open("w") as log:
            children.append(subprocess.Popen(["wtype", "-s", "790000"], env=env, stdout=log, stderr=subprocess.STDOUT))
        end = time.monotonic() + 5
        while time.monotonic() < end:
            inputs = subprocess.run(["timeout", "3", "swaymsg", "-t", "get_inputs", "-r"], env=env, capture_output=True, text=True, check=True, timeout=5)
            if any(i["type"] == "keyboard" for i in json.loads(inputs.stdout)):
                break
            time.sleep(.1)
        else:
            raise AssertionError("private virtual keyboard did not attach")
        (output / "inputs.json").write_text(inputs.stdout)
        (output / "environment.json").write_text(json.dumps(env, indent=2))
        group = cgroup()
        (output / "cgroup.json").write_text(json.dumps({"path": str(group), **{n: (group / n).read_text() for n in ("memory.max", "memory.high", "cpu.max", "pids.max")}}, indent=2))
        return subprocess.run([sys.executable, "-B", *argv], env=env, timeout=800).returncode
    finally:
        if "SWAYSOCK" in env:
            subprocess.run(["timeout", "5", "swaymsg", "exit"], env=env, capture_output=True, timeout=8)
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=8)
        (output / "resources.json").write_text(json.dumps({n: (cgroup() / n).read_text() for n in ("memory.peak", "memory.events", "cpu.stat")}, indent=2))
        if guard is not None:
            guard.close()


if __name__ == "__main__":
    assert sys.argv[1] == "--session"
    raise SystemExit(session(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:]))
