"""Explicit guest identity/workspace boundary, matching guest_profile.py's design.

Like the settings runners, public profiles identify an already authorized guest;
they grant no access. Private compositor children inherit the captured profile,
never a baked-in VM identity or a discovered replacement.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import uuid


class ProfileBlocked(RuntimeError):
    pass


def profile_argument(parser):
    parser.add_argument("--guest-profile", type=Path,
                        required=not bool(os.environ.get("FILECHOOSER_GUEST_PROFILE")),
                        help="explicit public guest identity/workspace/source/evidence profile JSON")


class GuestProfile:
    def __init__(self, path):
        self.path = Path(path).absolute()
        if self.path != self.path.resolve() or not self.path.is_file():
            raise ProfileBlocked("profile must be an explicit regular non-symlink file")
        raw = self.path.read_bytes()
        self.sha256 = hashlib.sha256(raw).hexdigest()
        try:
            data = json.loads(raw)
            fields = {"version", "name", "uuid", "mac", "sshHostKey", "uid", "home",
                      "workspace", "source", "evidence", "runtime"}
            if set(data) != fields or data["version"] != 1:
                raise ValueError("profile fields/version")
            self.name, self.uuid = data["name"], str(uuid.UUID(data["uuid"]))
            self.mac = data["mac"].lower()
            if not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", self.mac):
                raise ValueError("MAC")
            self.host_key = tuple(data["sshHostKey"].split()[:2])
            if len(self.host_key) != 2 or self.host_key[0] != "ssh-ed25519":
                raise ValueError("public host key")
            self.uid = data["uid"]
            if type(self.uid) is not int or self.uid < 1:
                raise ValueError("UID")
            for field in ("home", "workspace", "source", "evidence", "runtime"):
                value = Path(data[field])
                if not value.is_absolute() or value != value.resolve():
                    raise ValueError("noncanonical profile path")
                setattr(self, field, value)
            if not self.workspace.is_relative_to(self.home) or self.workspace == self.home:
                raise ValueError("workspace outside guest home")
            roots = (self.source, self.evidence, self.runtime)
            if any(not p.is_relative_to(self.workspace) or p == self.workspace for p in roots):
                raise ValueError("root outside workspace")
            if any(a.is_relative_to(b) or b.is_relative_to(a) for i, a in enumerate(roots) for b in roots[i + 1:]):
                raise ValueError("overlapping source/evidence/runtime roots")
        except (ValueError, TypeError, KeyError, AttributeError) as error:
            raise ProfileBlocked("invalid guest profile: " + str(error)) from error

    def verify(self, private=False):
        if os.getuid() != self.uid or Path(pwd.getpwuid(os.getuid()).pw_dir) != self.home:
            raise ProfileBlocked("guest account/home does not match explicit profile")
        if hashlib.sha256(self.path.read_bytes()).hexdigest() != self.sha256:
            raise ProfileBlocked("profile changed after capture")
        if private and os.environ.get("FILECHOOSER_PROFILE_SHA256") != self.sha256:
            raise ProfileBlocked("private session profile differs from captured profile")
        if self.mac not in {p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")}:
            raise ProfileBlocked("guest MAC does not match explicit profile")
        if not private:
            actual = subprocess.run(["timeout", "10", "sudo", "-n", "cat", "/sys/class/dmi/id/product_uuid"],
                                    capture_output=True, text=True, check=True, timeout=15).stdout.strip().lower()
            if actual != self.uuid:
                raise ProfileBlocked("guest UUID does not match explicit profile")
            if tuple(Path("/etc/ssh/ssh_host_ed25519_key.pub").read_text().split()[:2]) != self.host_key:
                raise ProfileBlocked("guest SSH host key does not match explicit profile")
        if not self.workspace.is_dir() or self.workspace.stat().st_uid != self.uid:
            raise ProfileBlocked("owned disk workspace is unavailable")
        temporary = Path(os.environ.get("TMPDIR", "")).absolute()
        if not os.environ.get("TMPDIR") or not temporary.is_dir() or not temporary.resolve().is_relative_to(self.workspace):
            raise ProfileBlocked("TMPDIR must be an existing disk-workspace directory")
        for path in (self.workspace, temporary):
            kind = subprocess.run(["timeout", "10", "findmnt", "-n", "-o", "FSTYPE", "-T", str(path)],
                                  capture_output=True, text=True, check=True, timeout=15).stdout.strip()
            if kind in ("tmpfs", "ramfs"):
                raise ProfileBlocked("workspace/TMPDIR is RAM-backed")

    def prepare_roots(self):
        self.verify()
        if not self.source.is_dir():
            raise ProfileBlocked("explicit source is unavailable")
        for path in (self.evidence, self.runtime):
            path.mkdir(parents=True, exist_ok=True, mode=0o700)
            if path != path.resolve() or path.stat().st_uid != self.uid:
                raise ProfileBlocked("task root is not canonical and guest-owned")


_active = None


def current_profile():
    global _active
    if _active is None:
        parser = argparse.ArgumentParser(add_help=False)
        profile_argument(parser)
        args, _ = parser.parse_known_args()
        path = args.guest_profile or os.environ.get("FILECHOOSER_GUEST_PROFILE")
        _active = GuestProfile(path)
        os.environ["FILECHOOSER_GUEST_PROFILE"] = str(_active.path)
    return _active


def workspace():
    return current_profile().workspace


def exact_source(path):
    return Path(path).resolve() == current_profile().source
