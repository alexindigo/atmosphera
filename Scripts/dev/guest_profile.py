"""Explicit VM identity and captured-console boundary for regression runners.

Profiles contain public identity/paths, not access credentials or permissions.
The caller must already be authorized to test that guest. No discovery fallback
or executable guest default is supplied here.
"""
import base64
import contextvars
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import uuid


class ProfileBlocked(RuntimeError):
    pass


_active = contextvars.ContextVar("regression_guest_profile", default=None)


def profile_argument(parser, required=True):
    parser.add_argument("--guest-profile", type=Path, required=required,
                        help="explicit public VM identity/workspace/session profile JSON")


def current_profile():
    profile = _active.get()
    if profile is None:
        raise ProfileBlocked("explicit --guest-profile is required before guest operations")
    return profile


def _command(args):
    result = subprocess.run(["timeout", "10", *map(str, args)], capture_output=True,
                            text=True, timeout=15)
    if result.returncode:
        raise ProfileBlocked("guest identity inspection failed: " + str(args[0]))
    return result.stdout.strip()


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    start: str
    uid: int
    pgid: int
    argv: tuple

    @classmethod
    def read(cls, pid):
        path = Path("/proc") / str(pid)
        fields = (path / "stat").read_text().rsplit(")", 1)[1].split()
        return cls(pid, fields[19], path.stat().st_uid, int(fields[2]),
                   tuple(os.fsdecode(a) for a in (path / "cmdline").read_bytes().split(b"\0") if a))

    def record(self):
        return {"pid": self.pid, "start": self.start, "uid": self.uid,
                "pgid": self.pgid, "argv": list(self.argv)}


class ConsoleGuard:
    def __init__(self, records):
        self.records = tuple(records)
        self.pids = frozenset(p.pid for p in self.records)
        self.groups = frozenset(p.pgid for p in self.records)

    @classmethod
    def capture(cls, config, uid):
        records = []
        for path in Path("/proc").glob("[0-9]*"):
            try:
                item = ProcessIdentity.read(int(path.name))
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            args = item.argv
            if not args or Path(args[0]).name not in ("qs", "quickshell") or item.uid != uid:
                continue
            if any(a in ("ipc", "msg", "log", "list", "kill") for a in args[1:]):
                continue
            if any(a in ("-c", "--config") and i + 1 < len(args) and args[i + 1] == config
                   for i, a in enumerate(args)):
                records.append(item)
        if len(records) > 1:
            raise ProfileBlocked("ambiguous original named console; preserve every instance")
        return cls(records)

    def verify(self, required=False):
        if required and not self.records:
            raise ProfileBlocked("original named console must be running at the run's start")
        for expected in self.records:
            try:
                actual = ProcessIdentity.read(expected.pid)
            except (FileNotFoundError, ProcessLookupError, PermissionError) as error:
                raise ProfileBlocked("captured original console disappeared") from error
            if actual != expected:
                raise ProfileBlocked("captured original console PID/start/UID/group/argv changed")


class GuestProfile:
    def __init__(self, path):
        self.path = Path(path).absolute()
        if self.path != self.path.resolve() or not self.path.is_file():
            raise ProfileBlocked("profile must be an explicit regular non-symlink file")
        raw = self.path.read_bytes()
        self.sha256 = hashlib.sha256(raw).hexdigest()
        try:
            data = json.loads(raw)
            required = {"version", "name", "uuid", "mac", "sshHostKey", "uid", "home", "workspace",
                        "workBase", "journalBase", "runtimeBase", "sessionRuntime", "waylandDisplay", "consoleConfig", "qmpCommand"}
            if not isinstance(data, dict) or set(data) != required or data["version"] != 1:
                raise ValueError("profile fields/version")
            self.name = data["name"]
            self.uuid = str(uuid.UUID(data["uuid"]))
            self.mac = data["mac"].lower()
            if not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", self.mac):
                raise ValueError("MAC")
            self.host_key = tuple(data["sshHostKey"].split()[:2])
            if len(self.host_key) != 2 or self.host_key[0] != "ssh-ed25519":
                raise ValueError("public host key")
            key = base64.b64decode(self.host_key[1], validate=True)
            self.host_fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(key).digest()).decode().rstrip("=")
            if type(data["uid"]) is not int or data["uid"] < 1:
                raise ValueError("UID")
            self.uid = data["uid"]
            for field, attr in (("home", "home"), ("workspace", "workspace"), ("workBase", "work_base"),
                                ("journalBase", "journal_base"), ("runtimeBase", "runtime_base"), ("sessionRuntime", "session_runtime")):
                value = Path(data[field])
                if not value.is_absolute() or value != value.resolve():
                    raise ValueError("noncanonical profile path")
                setattr(self, attr, value)
            if not self.workspace.is_relative_to(self.home) or self.workspace == self.home:
                raise ValueError("workspace outside guest home")
            for value in (self.work_base, self.journal_base, self.runtime_base):
                if not value.is_relative_to(self.workspace) or value == self.workspace:
                    raise ValueError("root outside workspace")
            roots = (self.work_base, self.journal_base, self.runtime_base)
            if any(a.is_relative_to(b) or b.is_relative_to(a) for i, a in enumerate(roots) for b in roots[i + 1:]):
                raise ValueError("overlapping work/journal/runtime roots")
            self.wayland_display = data["waylandDisplay"]
            self.console_config = data["consoleConfig"]
            if not all(isinstance(s, str) and s and "/" not in s for s in (self.name, self.wayland_display, self.console_config)):
                raise ValueError("profile name/session/console")
            command = data["qmpCommand"]
            if command is not None and (not isinstance(command, list) or not command
                                         or not all(isinstance(s, str) for s in command) or command.count("{event}") != 1):
                raise ValueError("hardware input command")
            self.qmp_prefix = tuple(command) if command else None
        except (ValueError, TypeError, KeyError, AttributeError) as error:
            raise ProfileBlocked("invalid guest profile: " + str(error)) from error
        self.console = None

    def verify(self, require_console=False):
        # Refuse a foreign account/home before any privileged identity inspection.
        if os.getuid() != self.uid or Path.home() != self.home:
            raise ProfileBlocked("guest account/home does not match explicit profile")
        if hashlib.sha256(self.path.read_bytes()).hexdigest() != self.sha256:
            raise ProfileBlocked("profile changed after capture")
        macs = {p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")}
        if self.mac not in macs:
            raise ProfileBlocked("guest MAC does not match explicit profile")
        actual_uuid = _command(["sudo", "-n", "cat", "/sys/class/dmi/id/product_uuid"]).lower()
        if actual_uuid != self.uuid:
            raise ProfileBlocked("guest UUID does not match explicit profile")
        actual_key = tuple(Path("/etc/ssh/ssh_host_ed25519_key.pub").read_text().split()[:2])
        if actual_key != self.host_key:
            raise ProfileBlocked("guest SSH host key does not match explicit profile")
        if not self.workspace.is_dir() or self.workspace.stat().st_uid != self.uid:
            raise ProfileBlocked("owned disk workspace is unavailable")
        if _command(["findmnt", "-n", "-o", "FSTYPE", "-T", self.workspace]) in ("tmpfs", "ramfs"):
            raise ProfileBlocked("workspace is RAM-backed")
        temporary = Path(os.environ.get("TMPDIR", "")).absolute()
        if not os.environ.get("TMPDIR") or not temporary.is_dir() or not temporary.resolve().is_relative_to(self.workspace):
            raise ProfileBlocked("TMPDIR must be an existing disk-workspace directory")
        if _command(["findmnt", "-n", "-o", "FSTYPE", "-T", temporary]) in ("tmpfs", "ramfs"):
            raise ProfileBlocked("TMPDIR is RAM-backed")
        self.session_environment()
        if self.console is not None:
            self.console.verify(require_console)

    def session_environment(self):
        sockets = list(self.session_runtime.glob("niri.*.sock"))
        if len(sockets) != 1 or not (self.session_runtime / self.wayland_display).exists():
            raise ProfileBlocked("profile's niri/Wayland session is unavailable or ambiguous")
        return {"XDG_RUNTIME_DIR": str(self.session_runtime), "WAYLAND_DISPLAY": self.wayland_display,
                "NIRI_SOCKET": str(sockets[0]), "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(self.session_runtime / "bus")}

    def record(self):
        return {"name": self.name, "uuid": self.uuid, "mac": self.mac,
                "hostKeySha256": self.host_fingerprint, "profile": str(self.path), "profileSha256": self.sha256,
                "console": [p.record() for p in self.console.records] if self.console else []}

    def prepare_roots(self):
        self.verify()
        for root in (self.work_base, self.journal_base, self.runtime_base):
            if root != root.resolve():
                raise ProfileBlocked("profile workspace root became symlinked")
            root.mkdir(parents=True, exist_ok=True, mode=0o700)
            if root.stat().st_uid != self.uid:
                raise ProfileBlocked("profile workspace root is not owned by the guest account")
            if _command(["findmnt", "-n", "-o", "FSTYPE", "-T", root]) in ("tmpfs", "ramfs"):
                raise ProfileBlocked("profile task root is RAM-backed")

    def child_environment(self, prefix):
        self.prepare_roots()
        runtime = Path(tempfile.mkdtemp(prefix=prefix, dir=self.runtime_base))
        os.chmod(runtime, 0o700)
        # systemctl --user uses systemd/private directly, even with an explicit
        # DBUS_SESSION_BUS_ADDRESS. Forward real session endpoints, not results.
        for name in ("bus", "systemd", "pulse"):
            target = self.session_runtime / name
            if target.exists():
                (runtime / name).symlink_to(target, target_is_directory=target.is_dir())
        # libwayland accepts an absolute display socket; keep task logs/IPC on
        # disk without losing access to the independently owned real compositor.
        return dict(self.session_environment(), XDG_RUNTIME_DIR=str(runtime),
                    WAYLAND_DISPLAY=str(self.session_runtime / self.wayland_display),
                    PIPEWIRE_RUNTIME_DIR=os.environ.get("PIPEWIRE_RUNTIME_DIR") or str(self.session_runtime))

    def qmp_command(self, event):
        if not self.qmp_prefix:
            raise ProfileBlocked("profile has no verified hardware QMP injection command")
        return shlex.join(s.format(event=json.dumps(event), uuid=self.uuid, name=self.name, mac=self.mac)
                          for s in self.qmp_prefix)


def activate_profile(path, require_console=False):
    profile = GuestProfile(path)
    profile.verify()
    profile.console = ConsoleGuard.capture(profile.console_config, profile.uid)
    profile.console.verify(require_console)
    _active.set(profile)  # Only a fully verified profile can replace the active one.
    os.environ.update(profile.session_environment())
    return profile


def protect_owned_process(proc):
    """Validate a newly spawned owned session before any scoped termination."""
    console = current_profile().console
    console.verify()
    if proc.pid in console.pids or os.getpgid(proc.pid) in console.groups or os.getpgid(proc.pid) == os.getpgrp():
        raise ProfileBlocked("refusing captured console/runner process-group ownership")
    if os.getpgid(proc.pid) != proc.pid:
        raise ProfileBlocked("owned child is not its recorded session/group leader")
