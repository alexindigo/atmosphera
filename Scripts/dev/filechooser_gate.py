"""Fixed independent gate slot owned by the outer isolated-run controller.

Private applications can request this one operation, not arbitrary systemd
commands. The outer controller retains serialization and checks fresh RAM
headroom while the primary's owned companion remains alive.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def request_gate(output):
    """Private-side fixed request; no service-manager address is exposed."""
    import filechooser_isolation as isolation
    base = isolation.checked()
    output = Path(output).resolve()
    assert output.is_relative_to(isolation.ROOT / "evidence") and output.is_dir()
    request = base / "gate-probe.request"
    assert not request.exists(), "one independent gate per reservation"
    pending = base / "gate-probe.pending"
    pending.write_text("independent-shell-gate\n")
    pending.replace(request)
    receipt = output / "gate-probe.json"
    deadline = time.monotonic() + 420
    while not receipt.exists():
        assert time.monotonic() < deadline, "independent gate controller timeout"
        time.sleep(.1)
    return json.loads(receipt.read_text())


def run_gate(primary_base, primary_output, label, admin_env, primary_properties):
    import filechooser_isolation as isolation
    root = isolation.ROOT
    args = sys.argv[1:]
    source = Path(args[args.index("--source") + 1]).resolve()
    assert source.is_relative_to(root / "sources") and source.is_dir()
    gate_label = label + "-gate"
    unit = "filechooser-" + gate_label
    base = root / "runtime" / ("i" + hashlib.sha256(gate_label.encode()).hexdigest()[:8])
    output = root / "evidence" / (gate_label + "-isolation")
    assert not base.exists() and not output.exists()
    # The diagnostic measured579317KiB qmllint PSS. This separate768MiB
    # maximum is LOWER than the old primary maximum; its high watermark and
    # CPU quota are never raised. The old shared limit throttled both jobs.
    maximum = min(int(primary_properties["MemoryMax"]), 768 * isolation.MIB)
    high = min(int(primary_properties["MemoryHigh"]), maximum)
    admission = isolation.admit(maximum)
    base.mkdir(); output.mkdir()
    (output / "admission.json").write_text(json.dumps(admission, indent=2))
    argv = [str(root / "tools/shell-gate.py"), "--source", str(source), "--label", gate_label, "--audit"]
    reservation = {"base": str(base), "output": str(output), "unit": unit, "argv": argv,
                   "primary_cgroup": primary_properties["ControlGroup"], "maximum": maximum, "high": high}
    reserved = output / "reservation.json"
    reserved.write_text(json.dumps(reservation, indent=2))
    command = ["systemd-run", "--user", "--wait", "--pipe", "--collect", "--unit=" + unit, "--service-type=exec",
               "--setenv=TMPDIR=" + str(root / "tmp"), "--setenv=FILECHOOSER_SESSION_SECONDS=320",
               "--setenv=FILECHOOSER_PARENT_PID_NAMESPACE=" + os.readlink("/proc/self/ns/pid"),
               "--setenv=FILECHOOSER_GATE_RESERVATION=" + str(reserved),
               "-p", f"MemoryMax={maximum}", "-p", f"MemoryHigh={high}", "-p", "MemorySwapMax=0",
               "-p", "CPUQuota=100%", "-p", "TasksMax=256", "-p", "OOMScoreAdjust=1000",
               "-p", "RuntimeMaxSec=360", "-p", "TimeoutStopSec=10", "-p", "OOMPolicy=stop",
               "--working-directory=" + str(root), *isolation.namespace_command([
                   sys.executable, "-B", str(Path(isolation.__file__).resolve()), "--session", str(base), str(output), *argv])]
    (output / "unit.json").write_text(json.dumps({"command": command, "primary": primary_properties}, indent=2))
    completed = False
    process = None
    try:
        with (output / "service.log").open("w") as log:
            process = subprocess.Popen(["timeout", "400", *command], env=admin_env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 25
            while not (output / "supervisor-ready").exists():
                assert process.poll() is None and time.monotonic() < deadline, "independent gate supervisor startup failed"
                time.sleep(.05)
            properties = isolation.systemd_properties(unit, admin_env)
            assert int(properties["MemoryMax"]) == maximum and int(properties["MemoryHigh"]) == high
            assert properties["TasksMax"] == "256"
            primary_group = Path(primary_properties["ControlGroup"])
            gate_group = Path(properties["ControlGroup"])
            assert gate_group != primary_group and gate_group.parent == primary_group.parent
            (output / "systemd-properties.json").write_text(json.dumps(properties, indent=2))
            (output / "supervisor-admitted").touch()
            code = process.wait(timeout=405)
            completed = True
        return {"passed": code == 0, "exit": code, "unit": unit, "output": str(output),
                "admission": admission, "properties": properties, "primary_cgroup": primary_properties["ControlGroup"]}
    finally:
        if not completed:
            stop = subprocess.run(["timeout", "15", "systemctl", "--user", "stop", unit], env=admin_env, capture_output=True, timeout=20)
            if stop.returncode:
                state = subprocess.run(["timeout", "5", "systemctl", "--user", "show", unit, "-p", "LoadState"], env=admin_env, capture_output=True, text=True, timeout=8)
                assert "LoadState=not-found" in state.stdout, stop.stderr
            if process is not None:
                process.wait(timeout=15)


def reserved_session(base, output, argv):
    import filechooser_isolation as isolation
    isolation.guest()
    path = Path(os.environ["FILECHOOSER_GATE_RESERVATION"])
    assert path == output / "reservation.json"
    value = json.loads(path.read_text())
    assert value["base"] == str(base) and value["output"] == str(output)
    assert value["argv"] == list(argv)
    assert argv[0] == str(isolation.ROOT / "tools/shell-gate.py") and argv[-1] == "--audit"
    source = Path(argv[2]).resolve()
    assert argv[1] == "--source" and source.is_relative_to(isolation.ROOT / "sources")
    group = isolation.cgroup()
    primary_group = Path("/sys/fs/cgroup" + value["primary_cgroup"])
    assert group.name == value["unit"] + ".service" and group.parent == primary_group.parent and group != primary_group
    assert (group / "memory.max").read_text().strip() == str(value["maximum"])
    assert (group / "memory.high").read_text().strip() == str(value["high"])
    assert (group / "memory.swap.max").read_text().strip() == "0"
    assert (group / "cpu.max").read_text().split() == ["100000", "100000"]
    assert (group / "pids.max").read_text().strip() == "256"
    assert Path("/proc/self/oom_score_adj").read_text().strip() == "1000"
    # Primary keeps the ordinary service lock; this additional lock protects
    # admission even if its controller/primary exits before this sibling.
    with (isolation.ROOT / "runtime/.filechooser-gate.lock").open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        (output / "supervisor-ready").touch()
        deadline = time.monotonic() + 25
        while not (output / "supervisor-admitted").exists():
            assert time.monotonic() < deadline, "independent gate resource attestation timeout"
            time.sleep(.05)
        # session() already supports controlled nested sessions under an
        # existing reservation. It sanitizes all application environment data.
        os.environ["FILECHOOSER_ISOLATION"] = str(base)
        return isolation.session(base, output, argv)
