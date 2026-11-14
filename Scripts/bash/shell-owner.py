#!/usr/bin/env python3
"""Session-bus ownership and identity-pinned shell retirement (Linux only)."""
import argparse
import json
import os
from pathlib import Path
import select
import shlex
import signal
import subprocess
import sys
import time

NAME = "app.atmosphera.Shell"
PATH = "/app/atmosphera/Shell"
IFACE = "app.atmosphera.Shell1"


def log(message):
    print("atmosphera: " + message, file=sys.stderr, flush=True)


def bus(*args):
    try:
        p = subprocess.run(["busctl", "--user", "--timeout=1", *args],
                           capture_output=True, text=True, timeout=2)
        return p.stdout.strip() if p.returncode == 0 else ""
    except subprocess.TimeoutExpired:
        return ""


def call(method, *args):
    return bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
               "org.freedesktop.DBus", method, *args)


def owner(name=NAME):
    reply = call("GetNameOwner", "s", name).split()
    if len(reply) != 2 or reply[0] != "s":
        return None
    unique = json.loads(reply[1])
    reply = call("GetConnectionUnixProcessID", "s", unique).split()
    if len(reply) != 2 or reply[0] != "u":
        return None
    return unique, int(reply[1])


def ping(unique):
    return bus("call", unique, PATH, IFACE, "ping").startswith('s "')


def queued_connection(pid):
    reply = shlex.split(call("ListQueuedOwners", "s", NAME))
    for unique in reply[2:]:
        if call("GetConnectionUnixProcessID", "s", unique) == f"u {pid}":
            return unique
    return ""


def start_time(pid):
    # comm can contain spaces and parentheses; field 22 follows its LAST ')'.
    stat = Path(f"/proc/{pid}/stat")
    if stat.stat().st_uid != os.getuid():
        raise PermissionError("shell belongs to another user")
    return stat.read_text().rsplit(")", 1)[1].split()[19]


class Process:
    def __init__(self, pid, expected=None):
        self.pid = pid
        self.start = start_time(pid)
        if expected is not None and self.start != expected:
            raise ProcessLookupError("departing shell identity changed")
        self.fd = os.pidfd_open(pid)
        try:
            unchanged = start_time(pid) == self.start
        except OSError:
            self.close()
            raise
        if not unchanged:
            self.close()
            raise ProcessLookupError("shell PID was reused")

    def close(self):
        os.close(self.fd)

    def exited(self, seconds=0):
        return bool(select.select([self.fd], [], [], seconds)[0])

    def stop(self, reason):
        if self.exited():
            return
        log(f"PID {self.pid}: graceful qs kill ({reason})")
        try:
            # Instance selection also pins graceful IPC. --pid alone could
            # select a replacement if the original exits during CLI startup.
            listing = subprocess.run(["qs", "list", "--all", "--json"],
                                     capture_output=True, text=True, timeout=2)
            instances = json.loads(listing.stdout) if listing.returncode == 0 and listing.stdout.lstrip().startswith("[") else []
            instance = next((i["id"] for i in instances if i["pid"] == self.pid), None)
            if instance and not self.exited():
                subprocess.run(["qs", "kill", "--id", instance],
                               capture_output=True, timeout=5)
            elif not self.exited():
                log(f"PID {self.pid}: no Quickshell instance found for graceful IPC ({reason})")
        except subprocess.TimeoutExpired:
            log(f"PID {self.pid}: graceful IPC timed out ({reason})")
        if self.exited(5):
            return
        for sig in (signal.SIGTERM, signal.SIGKILL):
            log(f"PID {self.pid}: {sig.name} after exit deadline ({reason})")
            try:
                signal.pidfd_send_signal(self.fd, sig)
            except ProcessLookupError:
                return
            if self.exited(2):
                return
        raise RuntimeError(f"PID {self.pid}: still alive after SIGKILL ({reason})")


def pin_owner(identity):
    process = Process(identity[1])
    # Bind the pidfd/start time to the bus connection, not merely its old PID.
    if owner() != identity:
        process.close()
        raise ProcessLookupError("shell election changed")
    return process


def wait_owner(identity, process, duplicate=False):
    """A failed ping is not permission to kill until ten consecutive seconds."""
    failed = None
    responsive = None
    if duplicate:
        log(f"waiting for shell owner PID {identity[1]}")
    while owner() == identity and not process.exited():
        if ping(identity[0]):
            if owner() != identity or process.exited():
                return False
            failed = None
            if not duplicate:
                return True
            if responsive is None:
                responsive = time.monotonic()
            if time.monotonic() - responsive >= 2:
                log(f"another shell is running (pid {identity[1]})")
                return True
        else:
            responsive = None
            if failed is None and not duplicate:
                log(f"waiting for unresponsive shell owner PID {identity[1]}")
            if failed is None:
                failed = time.monotonic()
            if time.monotonic() - failed >= 10:
                # Recheck the unique owner after the last bounded ping.
                if owner() == identity and not process.exited():
                    process.stop("owner ping failed for 10 seconds")
                return False
        time.sleep(.2)
    return False


def records():
    root = Path(os.environ["XDG_RUNTIME_DIR"]) / "atmosphera-shells"
    root.mkdir(mode=0o700, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
        raise RuntimeError("unsafe shell identity directory")
    return root


def record(pid, instance, unique, phase="elected"):
    root = records()
    value = dict(pid=pid, start=start_time(pid), instance=instance, unique=unique,
                 phase=phase, bus=call("GetId"))
    # Each generation writes the same process record. Atomic replacement keeps
    # a simultaneous launcher from observing a partially written identity.
    temporary = root / f".{pid}.{os.getpid()}"
    temporary.write_text(json.dumps(value))
    temporary.replace(root / str(pid))


def retire_departed(own_pid=0):
    for path in records().iterdir():
        if not path.name.isdigit() or int(path.name) == own_pid:
            continue
        try:
            value = json.loads(path.read_text())
            process = Process(int(value["pid"]), value["start"])
        except (ProcessLookupError, FileNotFoundError):
            path.unlink(missing_ok=True)
            continue
        try:
            if value["bus"] != call("GetId"):
                continue
            current = owner()
            if current and current[1] == process.pid:
                continue
            if value["phase"] == "queued":
                # An exiting duplicate or early-startup process can hang too.
                # Do not mistake a responsive, legitimately queued shell for
                # a departed one. Observe the same ten-second failure window.
                failed = time.monotonic()
                while not process.exited():
                    current = owner()
                    unique = queued_connection(process.pid)
                    if (current and current[1] == process.pid) or (unique and ping(unique)):
                        break
                    if time.monotonic() - failed >= 10:
                        process.stop("queued Atmosphera process no longer answers")
                        break
                    time.sleep(.2)
                continue
            # A recorded Atmosphera process that released the election may
            # still retain Notifications and the Quickshell instance lock.
            if value["unique"] and ping(value["unique"]):
                log(f"PID {process.pid}: responsive departing shell left running")
                continue
            process.stop("recorded departing Atmosphera shell retained resources")
        finally:
            process.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=("stop", "prepare", "watch"))
    ap.add_argument("--pid", type=int, default=0)
    ap.add_argument("--instance", default="")
    args = ap.parse_args()
    if args.action == "stop":
        identity = owner()
        if identity:
            try:
                process = pin_owner(identity)
            except (ProcessLookupError, FileNotFoundError):
                process = None
            if process:
                try:
                    process.stop("session stop/replace")
                finally:
                    process.close()
            current = owner()
            if current and current != identity:
                raise RuntimeError("another shell acquired the election during handoff; requested shell was not launched")
        retire_departed()
        return 0
    if args.action == "watch":
        record(args.pid, args.instance, "", "queued")
    while True:
        identity = owner()
        if identity is None:
            if args.action == "prepare":
                retire_departed()
                return 0
            time.sleep(.1)
            continue
        if args.action == "watch" and identity[1] == args.pid:
            record(args.pid, args.instance, identity[0])
            retire_departed(args.pid)
            notification = owner("org.freedesktop.Notifications")
            if notification and notification[1] != args.pid:
                log(f"Notifications is held by PID {notification[1]}; notification service may be degraded")
            return 0
        try:
            process = pin_owner(identity)
        except (ProcessLookupError, FileNotFoundError):
            continue
        try:
            live = wait_owner(identity, process, duplicate=args.action == "watch")
        finally:
            process.close()
        if live:
            if args.action == "prepare":
                print(identity[1])
                return 0
            record(args.pid, args.instance, "", "departing")
            return 10  # A responsive duplicate, not an election failure.


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        log(str(error))
        sys.exit(1)
