#!/usr/bin/env python3
"""Owned-VM-only inert Settings model/test-bridge verification, never live Settings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import time

CASES = (
    "instance-and-alias-isolation", "frozen-capture-and-ABA",
    "stale-duplicate-wrong-owner-completion", "publication-uncertainty-retention",
    "late-conflict-through-retention", "ordered-setup-suffix-coverage",
    "notification-reentry-and-fresh-pump", "bridge-real-QObject-immediate-nested-capture",
    "bridge-opaque-list-failed-save-invalidation", "bridge-token-detachment-and-empty-save-reentry",
    "bridge-revision-backed-default-query", "bridge-failed-assignment-baseline-restoration",
)
SOURCE_INPUTS = (
    "Scripts/dev/fixtures/settings-model-invariants.qml", "Helpers/SettingsModel.js",
    "Helpers/sha256.js", "Helpers/QtObj2JS.js", "Scripts/dev/settings-model-regression.py",
)
JOURNALS = Path("/home/tester/post-071/bindings-fifo-handoff/recovery-journals/settings-model-ownership")
ERRORS = re.compile(r"ReferenceError|TypeError|SyntaxError|Error loading configuration|Failed to load configuration|"
                    r"is not installed|Component is not ready|Cannot assign|Cannot read property|"
                    r"Expected token|Unexpected token|Binding loop detected|SETTINGS_MODEL_WATCHDOG")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def preserve_runtime(root, out):
    rows, sockets = {}, set()
    for path in [root, *sorted(root.rglob("*"))]:
        s = path.lstat()
        name = path.relative_to(root).as_posix()
        record = {"mode": stat.S_IMODE(s.st_mode), "uid": s.st_uid, "gid": s.st_gid,
                  "mtime_ns": s.st_mtime_ns, "inode": s.st_ino, "device": s.st_dev}
        if path.is_symlink():
            record.update(type="symlink", target=os.readlink(path))
        elif stat.S_ISSOCK(s.st_mode):
            record.update(type="socket", path=str(path))
            sockets.add(str(path))
        elif path.is_file():
            record.update(type="file", bytes=s.st_size, sha256=digest(path))
        elif path.is_dir():
            record.update(type="directory")
        else:
            raise RuntimeError("unexpected inert runtime artifact: " + str(path))
        rows[name] = record
    endpoints = [line for line in Path("/proc/net/unix").read_text().splitlines()
                 if len(line.split()) >= 8 and line.split()[-1] in sockets]
    (out / "runtime-manifest.json").write_text(json.dumps({"root": str(root), "entries": rows,
        "socket_endpoints": endpoints, "socket_node_bytes": "not regular-file data; original nodes retained"}, indent=2) + "\n")
    if endpoints:
        raise RuntimeError("owned inert runtime endpoint remains live")
    destination = out / "owned-runtime"
    shutil.copytree(root, destination, symlinks=True,
                    ignore=lambda directory, names: [name for name in names if str(Path(directory) / name) in sockets])
    for name, expected in rows.items():
        if expected["type"] == "socket":
            continue
        path = destination / name
        s = path.lstat()
        if (stat.S_IMODE(s.st_mode), s.st_uid, s.st_gid, s.st_mtime_ns) != (
                expected["mode"], expected["uid"], expected["gid"], expected["mtime_ns"]):
            raise RuntimeError("inert runtime copied metadata changed: " + name)
        if expected["type"] == "file" and digest(path) != expected["sha256"]:
            raise RuntimeError("inert runtime copied content changed: " + name)
        if expected["type"] == "symlink" and os.readlink(path) != expected["target"]:
            raise RuntimeError("inert runtime copied link changed: " + name)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--case", choices=("all",), required=True)
    a = ap.parse_args()
    macs = {p.read_text().strip() for p in Path("/sys/class/net").glob("*/address")}
    if os.getuid() != 1000 or Path.home() != Path("/home/tester") or "52:54:00:cd:ea:a0" not in macs:
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — exact owned tester VM required")
    source, out = a.source.absolute(), a.output.absolute()
    if source != source.resolve() or out != out.resolve() or not source.is_dir() or out.exists():
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — fresh non-symlink source/output required")
    if source == out or source in out.parents or out in source.parents or JOURNALS not in out.parents:
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — disjoint named journal root required")
    fs = os.statvfs(out.parent if out.parent.exists() else JOURNALS.parent)
    if fs.f_bavail * fs.f_frsize < (1024 + 64) * 1024 * 1024 or fs.f_favail < 55000:
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — root recovery reserve unavailable")
    runtime = os.statvfs("/run/user/1000")
    if runtime.f_bavail * runtime.f_frsize < 64 * 1024 * 1024 or runtime.f_favail < 5000:
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — original runtime reserve unavailable")
    executable = shutil.which("qs")
    if not executable:
        raise SystemExit("SETTINGS_MODEL_REGRESSION: BLOCKED — installed qs missing")
    hashes = {name: digest(source / name) for name in SOURCE_INPUTS}
    os.umask(0o077)
    out.mkdir(mode=0o700, parents=True)
    for name in ("cache", "config", "data", "inert"):
        (out / name).mkdir(mode=0o700)
    copies = {}
    for name in SOURCE_INPUTS:
        destination = out / "inert" / name
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copy2(source / name, destination)
        copies[name] = digest(destination)
    if copies != hashes:
        raise RuntimeError("inert input copy differs from candidate")
    entry = out / "inert" / "shell.qml"
    entry.write_text('import QtQuick\nQtObject { property QtObject tests: Loader { source: "Scripts/dev/fixtures/settings-model-invariants.qml" } }\n')
    # Quickshell's VFS confines relative imports to its config root. Keep the
    # original fixture/model layout inside a small inert input tree, not a full
    # desktop tree or a stripped/rewritten JavaScript module.
    runtime_dir = Path(tempfile.mkdtemp(prefix="sm-", dir="/run/user/1000"))
    (out / "source-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    env = {key: os.environ[key] for key in ("PATH", "HOME", "USER", "LOGNAME", "LANG") if key in os.environ}
    env.update(QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1", ATMOSPHERA_DEBUG="0",
               XDG_CACHE_HOME=str(out / "cache"), XDG_CONFIG_HOME=str(out / "config"),
               XDG_DATA_HOME=str(out / "data"), XDG_RUNTIME_DIR=str(runtime_dir))
    command = [executable, "-p", str(entry)]
    errors, quiet, timed_out = [], False, False
    with (out / "engine.log").open("xb") as log:
        proc = subprocess.Popen(command, cwd=source, env=env, stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True)
        (out / "ownership.json").write_text(json.dumps({"guest": "arch-atmosphera-gtkfree",
            "source": str(source), "output": str(out), "pid": proc.pid, "uid": os.getuid(),
            "live_desktop_fixture": False, "command": command, "timeout_seconds": 25,
            "runtime_root": str(runtime_dir), "copied_input_hashes": copies,
            "entry_sha256": digest(entry)}, indent=2) + "\n")
        deadline = time.monotonic() + 25
        while proc.poll() is None:
            if time.monotonic() > deadline or log.tell() > 1024 * 1024 or (out / "engine.log").stat().st_size > 1024 * 1024:
                timed_out = True
                errors.append("inert engine deadline/log bound exceeded")
                if proc.pid == 51508 or os.getpgid(proc.pid) != proc.pid:
                    raise RuntimeError("inert child ownership changed; refusing termination")
                os.killpg(proc.pid, signal.SIGTERM)
                break
            time.sleep(.02)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            errors.append("owned inert child did not quiesce after scoped TERM")
    try:
        os.killpg(proc.pid, 0)
    except ProcessLookupError:
        quiet = True
    if quiet:
        try:
            preserve_runtime(runtime_dir, out)
        except Exception as error:
            errors.append("inert runtime preservation failed: " + repr(error))
    text = (out / "engine.log").read_text(errors="replace")
    traces = []
    for line in text.splitlines():
        if "SETTINGS_MODEL_TRACE|" in line:
            try:
                traces.append(json.loads(line.split("SETTINGS_MODEL_TRACE|", 1)[1]))
            except (ValueError, TypeError) as error:
                errors.append("invalid trace marker: " + repr(error))
        if ERRORS.search(line):
            errors.append(line)
    if [row.get("id") for row in traces] != list(CASES):
        errors.append("literal trace set/order missing, duplicated or changed")
    if any(row.get("status") != "PASS" for row in traces):
        errors.append("one or more model/test-bridge traces failed")
    if text.count("SETTINGS_MODEL_REGRESSION: PASS") != 1 or "SETTINGS_MODEL_REGRESSION: FAIL" in text:
        errors.append("explicit engine PASS missing/contradicted")
    if proc.returncode != 0:
        errors.append("inert engine exit: " + str(proc.returncode))
    current = {name: digest(source / name) for name in SOURCE_INPUTS}
    if current != hashes:
        errors.append("source changed during inert run")
    if not quiet:
        errors.append("owned inert process group remains live; no continuation")
    status = "BLOCKED" if not quiet else "FAIL" if errors else "PASS"
    result = {"status": status, "cases": traces, "errors": errors, "engine_exit": proc.returncode,
              "timed_out": timed_out, "owned_child_group_gone": quiet, "source_hashes": hashes,
              "scope": "actual JS model and test bridge only; controlled effects, no production Settings/default/callback/native filesystem proof"}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2), flush=True)
    print("SETTINGS_MODEL_REGRESSION: " + status, flush=True)
    return 2 if status == "BLOCKED" else 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
