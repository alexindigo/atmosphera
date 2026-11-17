"""Guest-only NetworkManager fixture/session primitives.

An isolated bus is a separate daemon, never the guest's NetworkManager. Every
owned process is joined on teardown; output directories and bus sockets live
in the identity-verified disk workspace.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from guest_profile import activate_profile, protect_owned_process


SOURCE = Path(__file__).resolve().parents[2]


def run(argv, *, env=None, seconds=30, check=True):
    return subprocess.run(list(map(str, argv)), env=env, text=True,
                          capture_output=True, timeout=seconds, check=check)


def wait_for(predicate, description, seconds=20):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(.02)
    raise AssertionError(f"timed out: {description}: {last!r}")


class GuestRun:
    def __init__(self, profile_path, work):
        self.profile = activate_profile(profile_path)
        self.work = Path(work).absolute()
        assert self.work == self.work.resolve(), "canonical work path required"
        assert self.work.is_relative_to(self.profile.workspace), "assigned disk workspace required"
        assert not self.work.is_relative_to(SOURCE), "outputs must be outside source"
        self.work.mkdir(parents=True, exist_ok=False)
        (self.work / "tmp").mkdir()
        for name in ("config", "cache", "data", "state"):
            (self.work / name).mkdir()
        self.env = dict(os.environ, TMPDIR=str(self.work / "tmp"),
                        XDG_CONFIG_HOME=str(self.work / "config"), XDG_CACHE_HOME=str(self.work / "cache"),
                        XDG_DATA_HOME=str(self.work / "data"), XDG_STATE_HOME=str(self.work / "state"),
                        **self.profile.child_environment("nm-"))
        self.children = []
        self.logs = []
        self.results = []
        self.receipt = dict(passed=False, guest=self.profile.record(), cases=self.results)
        self.write()

    def write(self):
        path = self.work / "result.json"
        replacement = self.work / "result.pending"
        replacement.write_text(json.dumps(self.receipt, indent=2) + "\n")
        replacement.replace(path)

    def check(self, name, condition, **evidence):
        self.results.append(dict(case=name, passed=bool(condition), **evidence))
        self.write()
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name

    def launch(self, argv, name, env=None):
        log = (self.work / f"{name}.log").open("xb")
        self.logs.append(log)
        process = subprocess.Popen(list(map(str, argv)), env=env or self.env,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        guard = protect_owned_process(process)
        self.children.append((process, guard))
        return process

    def close(self):
        errors = []
        for process, guard in reversed(self.children):
            try:
                if process.poll() is None:
                    guard.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        # Recheck the recorded identity through the same guard;
                        # never select a process by name or a PID from a log.
                        guard.terminate()
                        assert guard.identity is not None
                        os.killpg(guard.identity.pgid, signal.SIGKILL)
                        process.wait(timeout=5)
            except Exception as error:
                errors.append(repr(error))
        for log in self.logs:
            log.close()
        self.receipt["cleanupErrors"] = errors
        self.receipt["cleanupComplete"] = not errors and all(p.poll() is not None for p, _ in self.children)
        self.receipt["passed"] = bool(self.results and all(c["passed"] for c in self.results)
                                      and self.receipt["cleanupComplete"] and "error" not in self.receipt)
        self.write()
        return self.receipt["passed"]


class PrivateBus:
    def __init__(self, owner):
        self.owner = owner
        socket = owner.work / "bus"
        assert len(os.fsencode(socket)) < 100, "Unix socket path too long"
        self.address = "unix:path=" + str(socket)
        self.process = owner.launch(["dbus-daemon", "--session", "--nofork",
                                     "--address=" + self.address], "private-bus")
        wait_for(socket.exists, "private bus socket")
        self.env = dict(owner.env, DBUS_SESSION_BUS_ADDRESS=self.address,
                        DBUS_SYSTEM_BUS_ADDRESS=self.address, QT_QPA_PLATFORM="wayland")
        self.daemon = owner.launch(["python3", "-B", SOURCE / "Scripts/dev/fixtures/nm-daemon.py",
                                    "--ready", owner.work / "daemon-ready"], "fixture-daemon", self.env)
        wait_for(lambda: (owner.work / "daemon-ready").exists(), "fixture ready")

    def control(self, action, **values):
        result = run(["gdbus", "call", "--address", self.address, "--dest", "dev.atmosphera.NmFixture",
                      "--object-path", "/fixture", "--method", "dev.atmosphera.NmFixture.Control",
                      action, json.dumps(values)], env=self.env)
        # This result is a single D-Bus string in gdbus's Python-like tuple syntax.
        import ast
        return json.loads(ast.literal_eval(result.stdout)[0])
