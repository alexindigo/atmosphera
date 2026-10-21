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
import threading
import time

ROOT = Path("/home/tester/Projects/atmosphera-filechooser")
MIB = 1024 * 1024
SAFETY_MARGIN = 512 * MIB


def memory_info():
    return {line.split()[0].rstrip(":"): int(line.split()[1]) * 1024
            for line in Path("/proc/meminfo").read_text().splitlines()
            if line.startswith(("MemTotal:", "MemAvailable:"))}


def admit(budget, available=None):
    """Reserve RAM headroom, not swap or a percentage of installed RAM alone."""
    available = memory_info()["MemAvailable"] if available is None else available
    if budget <= 0 or budget + SAFETY_MARGIN > available:
        raise RuntimeError(f"filechooser admission refused: budget={budget} bytes + "
                           f"safety_margin={SAFETY_MARGIN} bytes exceeds MemAvailable={available} bytes")
    return {"budget": budget, "available": available, "safety_margin": SAFETY_MARGIN}


def systemd_properties(unit, env):
    names = ("OOMScoreAdjust", "MemoryMax", "MemoryHigh", "MemorySwapMax", "CPUQuotaPerSecUSec", "TasksMax", "ControlGroup", "MainPID")
    result = subprocess.run(["timeout", "10", "systemctl", "--user", "show", unit,
                             *["--property=" + n for n in names]], env=env, capture_output=True,
                            text=True, check=True, timeout=15)
    values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    assert values["OOMScoreAdjust"] == "1000", values
    assert all(values[n] not in ("", "infinity", "0") for n in ("MemoryMax", "MemoryHigh", "CPUQuotaPerSecUSec", "TasksMax")), values
    assert values["MemorySwapMax"] == "0", values
    return values


def guest():
    assert os.getuid() == 1000 and pwd.getpwuid(os.getuid()).pw_dir == "/home/tester"
    assert "52:54:00:50:b3:8b" in [p.read_text().strip() for p in Path("/sys/class/net").glob("*/address")]
    assert Path(os.environ["TMPDIR"]).resolve().is_relative_to(ROOT)


def cgroup():
    return Path("/sys/fs/cgroup") / Path("/proc/self/cgroup").read_text().strip().split("::", 1)[1].lstrip("/")


def process_stat(proc):
    # comm may contain spaces and parentheses. Fields after its final ')' begin
    # at field 3; starttime is field 22, not an argv-derived identity.
    text = (proc / "stat").read_text(errors="replace")
    fields = text.rsplit(")", 1)[1].split()
    return {"pid": int(text.split(" ", 1)[0]), "state": fields[0],
            "start_time": int(fields[19]), "flags": int(fields[6])}


def sample_process(proc):
    """Bracket one procfs observation with kernel process identity/liveness."""
    row = {"proc": str(proc)}
    try:
        before = process_stat(proc)
        row["stat_before"] = before
        row["cgroup"] = str(Path("/sys/fs/cgroup") / (proc / "cgroup").read_text().strip().split("::", 1)[1].lstrip("/"))
        row["oom_score_adj"] = (proc / "oom_score_adj").read_text().strip()
        row["command"] = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        after = process_stat(proc)
        row["stat_after"] = after
    except (FileNotFoundError, ProcessLookupError):
        return dict(row, disposition="vanished")
    if (before["pid"], before["start_time"]) != (after["pid"], after["start_time"]):
        return dict(row, disposition="identity_changed")
    # Keep terminated observations as evidence rather than silently discarding
    # them. Only an actual dead/zombie kernel state is non-live; no cgroup-root,
    # empty-argv, timing, or repeated-read exemption applies to a live task.
    return dict(row, pid=after["pid"], start_time=after["start_time"],
                disposition="exited" if after["state"] in ("Z", "X", "x") else "live")


def sample_violation(row, expected):
    return row["disposition"] == "live" and (row["cgroup"] != expected or row["oom_score_adj"] != "1000")


def namespace_command(argv):
    """Keep broad process discovery/signals inside an unprivileged PID tree."""
    return ["unshare", "--user", "--map-current-user", "--pid", "--fork",
            "--mount-proc", "--kill-child", "--forward-signals", *map(str, argv)]


def checked():
    guest()
    base = Path(os.environ["FILECHOOSER_ISOLATION"])
    assert base.resolve().is_relative_to(ROOT / "runtime")
    assert Path.home() == base / "home"
    assert Path(os.environ["XDG_RUNTIME_DIR"]) == base / "run"
    assert os.environ["WAYLAND_DISPLAY"] == "wayland-1"
    assert "NIRI_SOCKET" not in os.environ
    assert os.environ["DBUS_SESSION_BUS_ADDRESS"] == "unix:path=" + str(base / "run/bus")
    assert Path(os.environ["FILECHOOSER_INPUT_SOCKET"]) == base / "run/input.sock"
    assert os.readlink("/proc/self/ns/pid") == os.environ["FILECHOOSER_PID_NAMESPACE"]
    assert os.environ["FILECHOOSER_PID_NAMESPACE"] != os.environ["FILECHOOSER_PARENT_PID_NAMESPACE"]
    assert (cgroup() / "memory.max").read_text().strip() != "max"
    assert (cgroup() / "cpu.max").read_text().split()[0] != "max"
    assert Path("/proc/self/oom_score_adj").read_text().strip() == "1000"
    return base


def _memory_probe(base, output, label, admin_env):
    """The outer launcher owns service-manager access, never the private app."""
    profile = base / "hungry-profile"
    for name in ("home", "tmp", "config", "cache", "state", "data", "run"):
        (profile / name).mkdir(parents=True, mode=0o700)
    env = {"PATH": "/usr/bin", "USER": "tester", "LOGNAME": "tester", "HOME": str(profile / "home"),
           "TMPDIR": str(profile / "tmp"), "XDG_RUNTIME_DIR": str(profile / "run"),
           "XDG_CONFIG_HOME": str(profile / "config"), "XDG_CACHE_HOME": str(profile / "cache"),
           "XDG_STATE_HOME": str(profile / "state"), "XDG_DATA_HOME": str(profile / "data"),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(profile / "run/no-bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(profile / "run/no-system-bus")}
    unit = "filechooser-" + label + "-hungry"
    body = "import os; from pathlib import Path; assert os.getpid()==1; assert Path('/proc/self/oom_score_adj').read_text().strip()=='1000'; print('private pid namespace',os.readlink('/proc/self/ns/pid'),flush=True); x=bytearray(128*1024*1024)"
    argv = ["systemd-run", "--user", "--wait", "--pipe", "--unit=" + unit,
            "-p", "MemoryMax=64M", "-p", "MemoryHigh=64M", "-p", "MemorySwapMax=0", "-p", "CPUQuota=25%",
            "-p", "TasksMax=32", "-p", "OOMScoreAdjust=1000", "-p", "RuntimeMaxSec=20", "-p", "TimeoutStopSec=5", "-p", "OOMPolicy=stop", "--working-directory=" + str(ROOT), "--setenv=TMPDIR=" + env["TMPDIR"],
            *namespace_command(["/usr/bin/env", "-i", *[k + "=" + v for k, v in env.items()], sys.executable, "-B", "-c", body])]
    # This probes the hard limit, not reclaim throttling. A lower MemoryHigh
    # can stall a faulting allocator until the watchdog wins over the OOM test.
    try:
        run = subprocess.run(["timeout", "30", *argv], env=admin_env, capture_output=True, text=True, timeout=35)
    except subprocess.TimeoutExpired as error:
        (output / "hungry.log").write_text(str(error))
        # Reap this exact owned Python-only probe before releasing the reserved
        # budget/serialization lock, including when the control client times out.
        subprocess.run(["timeout", "15", "systemctl", "--user", "stop", unit], env=admin_env, check=True, timeout=20)
        raise
    show = subprocess.run(["timeout", "10", "systemctl", "--user", "show", unit, "-p", "Result", "-p", "MemoryMax", "-p", "MemoryHigh", "-p", "MemoryPeak", "-p", "OOMScoreAdjust", "-p", "MemorySwapMax", "-p", "TasksMax", "-p", "CPUQuotaPerSecUSec"],
                          env=admin_env, capture_output=True, text=True, check=True, timeout=15)
    (output / "hungry.log").write_text(run.stdout + run.stderr + show.stdout)
    subprocess.run(["timeout", "10", "systemctl", "--user", "reset-failed", unit], env=admin_env, check=True, timeout=15)
    return {"passed": run.returncode != 0 and "Result=oom-kill" in show.stdout and "OOMScoreAdjust=1000" in show.stdout and "MemorySwapMax=0" in show.stdout,
            "exit": run.returncode, "unit": unit, "properties": show.stdout, "command": argv}


def _audit_probe(base, output, label, admin_env, main_properties):
    """Fixed negative test: a capped sibling joins only our private namespaces.

    nsenter does not change cgroup membership unless --join-cgroup is requested.
    Namespace FDs pin this owned session, not a console PID or reusable name.
    """
    main_pid = int(main_properties["MainPID"])
    children = Path(f"/proc/{main_pid}/task/{main_pid}/children").read_text().split()
    candidates = []
    for pid in children:
        proc = Path("/proc") / pid
        row = sample_process(proc)
        if row["disposition"] == "live" and "--session" in row["command"] and str(base) in row["command"]:
            assert row["cgroup"] == "/sys/fs/cgroup" + main_properties["ControlGroup"]
            assert os.readlink(proc / "ns/pid") != os.readlink("/proc/self/ns/pid")
            candidates.append(int(pid))
    assert len(candidates) == 1, candidates
    target = candidates[0]
    fds = {name: os.open(f"/proc/{target}/ns/{name}", os.O_RDONLY) for name in ("user", "mnt", "pid")}
    profile = base / "audit-profile"
    for name in ("home", "tmp", "config", "cache", "state", "data", "run"):
        (profile / name).mkdir(parents=True, mode=0o700)
    live, release = base / "audit-probe-live.json", base / "audit-probe-release"
    env = {"PATH": "/usr/bin", "USER": "tester", "LOGNAME": "tester", "HOME": str(profile / "home"),
           "TMPDIR": str(profile / "tmp"), "XDG_RUNTIME_DIR": str(profile / "run"),
           "XDG_CONFIG_HOME": str(profile / "config"), "XDG_CACHE_HOME": str(profile / "cache"),
           "XDG_STATE_HOME": str(profile / "state"), "XDG_DATA_HOME": str(profile / "data"),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(profile / "run/no-bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(profile / "run/no-system-bus")}
    body = ("import json,os,time; from pathlib import Path; "
            "assert os.getuid()==1000; assert Path('/proc/self/oom_score_adj').read_text().strip()=='1000'; "
            f"pending=Path({str(live) + '.pending'!r}); pending.write_text(json.dumps({{'pid':os.getpid(),'namespace':os.readlink('/proc/self/ns/pid')}})); pending.replace({str(live)!r}); "
            "deadline=time.monotonic()+15\n"
            f"while not Path({str(release)!r}).exists():\n"
            " assert time.monotonic()<deadline\n time.sleep(.02)\n")
    unit = "filechooser-" + label + "-outside"
    argv = ["systemd-run", "--user", "--wait", "--pipe", "--collect", "--unit=" + unit,
            "-p", "MemoryMax=64M", "-p", "MemoryHigh=64M", "-p", "MemorySwapMax=0",
            "-p", "CPUQuota=25%", "-p", "TasksMax=32", "-p", "OOMScoreAdjust=1000",
            "-p", "RuntimeMaxSec=20", "-p", "TimeoutStopSec=5", "-p", "OOMPolicy=stop",
            "--working-directory=" + str(ROOT),
            "--setenv=TMPDIR=" + env["TMPDIR"], "nsenter",
            "--user=" + f"/proc/{os.getpid()}/fd/{fds['user']}",
            "--mount=" + f"/proc/{os.getpid()}/fd/{fds['mnt']}",
            "--pid=" + f"/proc/{os.getpid()}/fd/{fds['pid']}", "--preserve-credentials",
            "/usr/bin/env", "-i", *[k + "=" + v for k, v in env.items()], sys.executable, "-B", "-c", body]
    process = None
    completed = False
    try:
        with (output / "outside.log").open("w") as log:
            process = subprocess.Popen(["timeout", "--kill-after=5", "30", *argv], env=admin_env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 12
            while not live.exists():
                assert process.poll() is None and time.monotonic() < deadline, "outside probe startup failed"
                time.sleep(.02)
            properties = systemd_properties(unit, admin_env)
            assert properties["MemoryMax"] == str(64 * MIB) and properties["TasksMax"] == "32"
            (output / "outside-properties.json").write_text(json.dumps(properties, indent=2))
            (base / "audit-probe-attested").touch()
            code = process.wait(timeout=22)
            completed = True
        return {"passed": code == 0, "exit": code, "unit": unit, "properties": properties, "command": argv}
    finally:
        if not completed:
            stop = subprocess.run(["timeout", "15", "systemctl", "--user", "stop", unit], env=admin_env, capture_output=True, timeout=20)
            if stop.returncode:
                state = subprocess.run(["timeout", "5", "systemctl", "--user", "show", unit, "-p", "LoadState"], env=admin_env, capture_output=True, text=True, timeout=8)
                assert "LoadState=not-found" in state.stdout, stop.stderr
            if process is not None:
                process.wait(timeout=15)
        for fd in fds.values():
            os.close(fd)


def enter(memory_probe=False, runtime_seconds=840, detach=False, audit_probe=False, gate_probe=False):
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
    assert 60 <= runtime_seconds <= 7200
    assert not (memory_probe and audit_probe), "one fixed auxiliary probe per reservation"
    assert not (gate_probe and audit_probe), "gate and deliberate escape are separate reservations"
    assert not (detach and (memory_probe or audit_probe or gate_probe)), "probe requires its synchronous controller"
    output.mkdir()
    # Serialize private workloads: multiple individually bounded services must
    # not collectively starve the login session. The lock is held until systemd
    # has reaped the entire service cgroup, including detached shell children.
    with (ROOT / "runtime/.filechooser-isolation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with (ROOT / "runtime/.filechooser-gate.lock").open("a") as gate_lock:
            fcntl.flock(gate_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # A detached service retains this second lock after its SSH launcher
        # exits. Check it before admission/start, not only after starting a unit.
        with (ROOT / "runtime/.filechooser-service.lock").open("a") as service_lock:
            try:
                fcntl.flock(service_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("filechooser admission refused: another private workload owns the guest budget")
        ram = memory_info()["MemTotal"]
        maximum = ram // 4 // (1024 * 1024) * 1024 * 1024
        high = maximum * 3 // 4
        # The fixed auxiliary probe is the only additional unit allowed while
        # this lock is held; reserve its entire budget at the same admission.
        admission = admit(maximum + (64 * MIB if memory_probe or audit_probe else 0))
        (output / "admission.json").write_text(json.dumps(admission, indent=2))
        base.mkdir()
        env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus")
        command = ["systemd-run", "--user", *([] if detach else ["--wait", "--pipe", "--collect"]),
                    "--unit=filechooser-" + label, "--service-type=exec",
                    "--setenv=TMPDIR=" + str(ROOT / "tmp"),
                    "--setenv=FILECHOOSER_SESSION_SECONDS=" + str(runtime_seconds - 40),
                    "--setenv=FILECHOOSER_PARENT_PID_NAMESPACE=" + os.readlink("/proc/self/ns/pid"),
                    "-p", f"MemoryMax={maximum}", "-p", f"MemoryHigh={high}",
                    "-p", "MemorySwapMax=0", "-p", "CPUQuota=100%", "-p", "TasksMax=256",
                    "-p", "OOMScoreAdjust=1000", "-p", f"RuntimeMaxSec={runtime_seconds}", "-p", "TimeoutStopSec=10", "-p", "OOMPolicy=stop",
                    *(["-p", "StandardOutput=append:" + str(output / "service.log"), "-p", "StandardError=inherit"] if detach else []),
                   "--working-directory=" + str(ROOT), *namespace_command([
                       sys.executable, "-B", str(Path(__file__).resolve()),
                       "--session", str(base), str(output), str(Path(sys.argv[0]).resolve()), *args])]
        (output / "unit.json").write_text(json.dumps({"command": command, "ram": ram, "memory_max": maximum, "memory_high": high, "cpu_quota": "100%"}, indent=2))
        process = subprocess.Popen(["timeout", str(runtime_seconds + 40), *command], env=env)
        deadline = time.monotonic() + 25
        while not (output / "supervisor-ready").exists():
            if (process.poll() is not None and (not detach or process.returncode != 0)) or time.monotonic() >= deadline:
                raise RuntimeError("isolated supervisor failed before resource attestation")
            time.sleep(.05)
        values = systemd_properties("filechooser-" + label, env)
        assert int(values["MemoryMax"]) == maximum and int(values["MemoryHigh"]) == high and values["TasksMax"] == "256", values
        (output / "systemd-properties.json").write_text(json.dumps(values, indent=2))
        (output / "supervisor-admitted").touch()
        if detach:
            code = process.wait(timeout=15)
            assert code == 0
            print(json.dumps({"unit": "filechooser-" + label, "output": str(output), "detached": True, "properties": values}), flush=True)
        elif memory_probe or audit_probe or gate_probe:
            # One fixed bounded probe can be requested while the protected
            # session-like app is alive. No arbitrary commands or unit names
            # cross this boundary; private workloads cannot reach the manager.
            requested = False
            gate_requested = False
            with process:
                while process.poll() is None:
                    request = base / ("audit-probe.request" if audit_probe else "memory-probe.request")
                    if not requested and request.exists():
                        requested = True
                        try:
                            assert request.read_text() == ("live-sibling\n" if audit_probe else "64MiB\n")
                            result = _audit_probe(base, output, label, env, values) if audit_probe else _memory_probe(base, output, label, env)
                        except Exception as error:
                            result = {"passed": False, "error": repr(error)}
                        pending = output / ("audit-probe.pending" if audit_probe else "memory-probe.pending")
                        pending.write_text(json.dumps(result, indent=2))
                        pending.replace(output / ("audit-probe.json" if audit_probe else "memory-probe.json"))
                    gate_request = base / "gate-probe.request"
                    if gate_probe and not gate_requested and gate_request.exists():
                        gate_requested = True
                        try:
                            assert gate_request.read_text() == "independent-shell-gate\n"
                            from filechooser_gate import run_gate
                            result = run_gate(base, output, label, env, values)
                        except Exception as error:
                            result = {"passed": False, "error": repr(error)}
                        pending = output / "gate-probe.pending"
                        pending.write_text(json.dumps(result, indent=2))
                        pending.replace(output / "gate-probe.json")
                    time.sleep(.05)
                code = process.returncode
        else:
            code = process.wait(timeout=runtime_seconds + 50)
    raise SystemExit(code)


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
    """Send the existing driver's vocabulary to its one private keyboard."""
    checked()
    assert argv[0] == "ydotool"
    assert argv[1] in ("type", "key")
    return [sys.executable, "-B", str(Path(__file__).with_name("filechooser_input.py")), *argv[1:]]


def session(base, output, argv):
    guest()
    parent_namespace = os.environ["FILECHOOSER_PARENT_PID_NAMESPACE"]
    pid_namespace = os.readlink("/proc/self/ns/pid")
    assert pid_namespace != parent_namespace, "refusing session in the login PID namespace"
    # Keep serialization in the service as well as the invoking client. An
    # interrupted SSH/systemd-run client must not release the workload lock.
    guard = None
    if "FILECHOOSER_ISOLATION" not in os.environ:
        guard = (ROOT / "runtime/.filechooser-service.lock").open("a")
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        (output / "supervisor-ready").touch()
        deadline = time.monotonic() + 25
        while not (output / "supervisor-admitted").exists():
            assert time.monotonic() < deadline, "resource attestation timeout"
            time.sleep(.05)
    for name in ("home", "run", "tmp", "config", "cache", "state", "data"):
        (base / name).mkdir(mode=0o700)
    env = {"PATH": "/usr/local/bin:/usr/bin", "USER": "tester", "LOGNAME": "tester", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "HOME": str(base / "home"), "TMPDIR": str(base / "tmp"), "XDG_RUNTIME_DIR": str(base / "run"),
           "XDG_CONFIG_HOME": str(base / "config"), "XDG_CACHE_HOME": str(base / "cache"),
           "XDG_STATE_HOME": str(base / "state"), "XDG_DATA_HOME": str(base / "data"),
           "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(base / "run/bus"),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(base / "run/no-system-bus"),
           "FILECHOOSER_ISOLATION": str(base), "XDG_CURRENT_DESKTOP": "sway", "QT_QPA_PLATFORM": "wayland",
           "FILECHOOSER_PID_NAMESPACE": pid_namespace, "FILECHOOSER_PARENT_PID_NAMESPACE": parent_namespace,
            "FILECHOOSER_INPUT_SOCKET": str(base / "run/input.sock"),
            "FILECHOOSER_SESSION_SECONDS": os.environ.get("FILECHOOSER_SESSION_SECONDS", "800"),
           "QT_FORCE_STDERR_LOGGING": "1", "ATMOSPHERA_DEBUG": "0", "ATMOSPHERA_UPGRADELOG_URL": "http://127.0.0.1:9",
           "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_HEADLESS_OUTPUTS": "1",
           # Mesa's CPU OpenGL still supports the product's shader masks. The
           # Qt Quick software scenegraph silently omits MultiEffect content.
           "LIBGL_ALWAYS_SOFTWARE": "1", "QSG_RHI_BACKEND": "opengl"}
    config = base / "sway.conf"
    config.write_text("output HEADLESS-1 mode 1280x800\nseat seat0 fallback true\nxwayland disable\n")
    bus_config = base / "bus.conf"
    bus_config.write_text('<busconfig><type>session</type><listen>' + env["DBUS_SESSION_BUS_ADDRESS"] +
                          '</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*" eavesdrop="true"/>'
                          '<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>')
    children = []
    keyboard_process = None
    audit_stop = threading.Event()
    observed, exited, discarded, violations, audit_errors = {}, {}, [], [], []
    def audit():
        expected = str(cgroup())
        while not audit_stop.is_set():
            for proc in Path("/proc").iterdir():
                if not proc.name.isdigit():
                    continue
                try:
                    row = sample_process(proc)
                    if row["disposition"] in ("vanished", "identity_changed"):
                        discarded.append(row)
                        continue
                    key = (row["pid"], row["start_time"], row["command"], row["cgroup"], row["oom_score_adj"])
                    if row["disposition"] == "exited":
                        exited[key] = row
                        continue
                    observed[key] = row
                    if sample_violation(row, expected):
                        if not violations:
                            (output / "first-violation.json").write_text(json.dumps(row, indent=2))
                        violations.append(row)
                except Exception as error:
                    # A failed sampler must fail the gate, not silently kill
                    # the observer thread and leave a reassuring empty report.
                    audit_errors.append({"proc": str(proc), "error": repr(error)})
            audit_stop.wait(.02)
    auditor = threading.Thread(target=audit, daemon=True)
    auditor.start()
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
        # Build and run one keyboard owner. Command clients never connect a
        # second Wayland keyboard or remove the seat's active keymap.
        build = base / "input-build"
        build.mkdir()
        scripts = Path(__file__).resolve().parent
        protocol = scripts / "virtual-keyboard-unstable-v1.xml"
        with (output / "input-build.log").open("w") as build_log:
            for mode, filename in (("client-header", "virtual-keyboard-client.h"), ("private-code", "virtual-keyboard-protocol.c")):
                subprocess.run(["timeout", "15", "wayland-scanner", mode, str(protocol), str(build / filename)],
                               env=env, stdout=build_log, stderr=subprocess.STDOUT, check=True, timeout=20)
            flags = subprocess.run(["timeout", "5", "pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"],
                                   env=env, capture_output=True, text=True, check=True, timeout=8).stdout.split()
            subprocess.run(["timeout", "30", "cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-I", str(build),
                            str(scripts / "filechooser-input.c"), str(build / "virtual-keyboard-protocol.c"), *flags,
                            "-o", str(build / "keyboard")], env=env, stdout=build_log, stderr=subprocess.STDOUT, check=True, timeout=35)
        with (output / "keyboard.log").open("w") as log:
            keyboard_process = subprocess.Popen([str(build / "keyboard"), env["FILECHOOSER_INPUT_SOCKET"]], env=env, stdout=log, stderr=subprocess.STDOUT)
            children.append(keyboard_process)
        end = time.monotonic() + 5
        while time.monotonic() < end:
            inputs = subprocess.run(["timeout", "3", "swaymsg", "-t", "get_inputs", "-r"], env=env, capture_output=True, text=True, check=True, timeout=5)
            if Path(env["FILECHOOSER_INPUT_SOCKET"]).exists() and any(i["type"] == "keyboard" and i.get("xkb_layout_names") for i in json.loads(inputs.stdout)):
                break
            time.sleep(.1)
        else:
            raise AssertionError("private keyboard did not publish its command socket/keymap")
        (output / "inputs.json").write_text(inputs.stdout)
        (output / "environment.json").write_text(json.dumps(env, indent=2))
        group = cgroup()
        (output / "cgroup.json").write_text(json.dumps({"path": str(group), **{n: (group / n).read_text() for n in ("memory.max", "memory.high", "cpu.max", "pids.max")}}, indent=2))
        return subprocess.run([sys.executable, "-B", *argv], env=env, timeout=int(env["FILECHOOSER_SESSION_SECONDS"])).returncode
    finally:
        if keyboard_process is not None and keyboard_process.poll() is None and Path(env["FILECHOOSER_INPUT_SOCKET"]).exists():
            subprocess.run(["timeout", "5", sys.executable, "-B", str(Path(__file__).with_name("filechooser_input.py")), "stop"],
                           env=env, capture_output=True, check=True, timeout=8)
            keyboard_process.wait(timeout=8)
        if "SWAYSOCK" in env:
            subprocess.run(["timeout", "5", "swaymsg", "exit"], env=env, capture_output=True, timeout=8)
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=8)
        (output / "resources.json").write_text(json.dumps({**{n: (cgroup() / n).read_text() for n in ("memory.peak", "memory.events", "memory.pressure", "cpu.stat")},
            "keyboard_exit": keyboard_process.returncode if keyboard_process else None}, indent=2))
        audit_stop.set(); auditor.join(timeout=5)
        assert not auditor.is_alive(), "process auditor failed to stop"
        (output / "process-cgroups.json").write_text(json.dumps({"expected": str(cgroup()),
            "processes": list(observed.values()), "exited_processes": list(exited.values()),
            "discarded_samples": discarded, "errors": audit_errors, "violations": violations}, indent=2))
        assert not audit_errors, "process audit could not read a stable sample"
        assert not violations, "live process escaped dev unit/OOM score contract"
        if guard is not None:
            guard.close()


if __name__ == "__main__":
    assert sys.argv[1] == "--session"
    if "FILECHOOSER_GATE_RESERVATION" in os.environ:
        from filechooser_gate import reserved_session
        raise SystemExit(reserved_session(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:]))
    raise SystemExit(session(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:]))
