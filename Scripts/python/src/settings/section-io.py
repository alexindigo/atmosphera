#!/usr/bin/env python3
"""Fixed stdin-based preparation/publication helper for Settings-owned I/O.

Checks observed preimages, not a universal CAS with uncoordinated editors.
Neither fsync/power-loss durability nor immunity to future writes is claimed.
Only controlled diagnostics go to stderr; raw content stays on the owned pipe
or in a private conflict artifact, never argv/environment/error messages.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import uuid

_result_context = {}


def observed(state):
    _result_context["state"] = state
    _result_context.setdefault("inspected", []).append(state)
    return state


def checksum(value):
    return hashlib.sha256(value).hexdigest()


def inspect(path):
    try:
        link = path.lstat()
    except FileNotFoundError:
        return observed({"exists": False, "identity": "missing", "sha256": "", "raw": "", "valid": True, "data": {}})
    symlink = os.readlink(path) if stat.S_ISLNK(link.st_mode) else None
    try:
        with path.open("rb") as stream:
            before = os.fstat(stream.fileno())
            value = stream.read()
            after = os.fstat(stream.fileno())
    except FileNotFoundError:
        # A dangling link is present, not the same accepted base as missing.
        if symlink is None:
            raise
        value = b""
        before = after = link
    if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise RuntimeError("Content changed during read")
    identity = [link.st_dev, link.st_ino, link.st_mode, link.st_uid, link.st_gid, symlink,
                before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, checksum(value)]
    raw = value.decode("utf-8", errors="replace")
    valid, data = True, {}
    try:
        data = json.loads(raw)
        valid = isinstance(data, dict)
    except (ValueError, UnicodeError):
        valid = False
    return observed({"exists": True, "identity": checksum(json.dumps(identity).encode()),
            "sha256": checksum(value), "raw": raw, "valid": valid,
            "data": data if valid else {}, "raw_base64": base64.b64encode(value).decode("ascii"),
            "mode": stat.S_IMODE(before.st_mode), "symlink": symlink})


def retain(path, directory, state):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination = directory / (uuid.uuid4().hex + ".json")
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump({"path": str(path), "observed": state}, stream)
        stream.flush()
    return str(destination)


def main():
    mode, name = sys.argv[1:3]
    path = Path(name)
    _result_context.update(path=str(path), phase="inspect" if mode == "inspect" else "input",
                           publication={"attempted": False, "completed": False, "uncertain": False})
    if mode == "inspect":
        print(json.dumps({"ok": True, "state": inspect(path)}))
        return 0
    payload = json.load(sys.stdin)
    if mode == "retain":
        _result_context.update(phase="retention", state=payload, conflict=True)
        retained = retain(path, Path(sys.argv[3]), payload)
        print(json.dumps({"ok": True, "retained": retained}))
        return 0
    temporary = Path(sys.argv[3])
    _result_context["phase"] = "preimage"
    current = inspect(path)
    expected = payload["base"]
    same_content = (current["exists"], current["sha256"]) == (expected["exists"], expected["sha256"])
    same_identity = not expected.get("identity") or current["identity"] == expected["identity"]
    if not same_content or not same_identity:
        _result_context.update(conflict=True, phase="preimage-retention")
        retained = retain(path, Path(payload["conflicts"]), current)
        print(json.dumps({"ok": False, "conflict": True, "path": str(path),
                          "retained": retained, "state": current, "error": "Accepted preimage changed"}))
        return 18
    if mode == "prepare":
        _result_context["phase"] = "prepare"
        raw = payload["raw"]
        if payload.get("format", "json") == "json" and current["exists"] and not current["valid"]:
            _result_context.update(conflict=True, phase="invalid-retention")
            retained = retain(path, Path(payload["conflicts"]), current)
            print(json.dumps({"ok": False, "conflict": True, "path": str(path), "retained": retained,
                              "state": current, "error": "Accepted content is not a settings object"}))
            return 18
        if raw is not None and payload.get("format", "json") == "json" and not isinstance(json.loads(raw), dict):
            raise ValueError("Prepared settings must be an object")
        value = b"" if raw is None else raw.encode("utf-8")
        temporary.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            if stream.write(value) != len(value):
                raise OSError("Incomplete prepared write")
            stream.flush()
            os.fchmod(stream.fileno(), current.get("mode", 0o644))
        print(json.dumps({"ok": True, "base": current, "prepared_sha256": checksum(value),
                          "delete": raw is None, "temporary": str(temporary)}))
        return 0
    if mode != "promote":
        raise ValueError("Unknown I/O operation")
    value = temporary.read_bytes()
    if checksum(value) != payload["prepared_sha256"]:
        raise RuntimeError("Prepared content changed")
    publication = _result_context["publication"]
    publication.update(attempted=True, uncertain=True, prepared_sha256=payload["prepared_sha256"], delete=payload["delete"])
    _result_context["phase"] = "publication"
    if payload["delete"]:
        path.unlink(missing_ok=True)
        publication["completed"] = True
        temporary.unlink()
    else:
        os.replace(temporary, path)
        publication["completed"] = True
    _result_context["phase"] = "readback"
    confirmed = inspect(path)
    matches = not confirmed["exists"] if payload["delete"] else confirmed["sha256"] == payload["prepared_sha256"]
    if not matches:
        _result_context.update(conflict=True, phase="readback-retention")
        retained = retain(path, Path(payload["conflicts"]), confirmed)
        print(json.dumps({"ok": False, "conflict": True, "path": str(path), "retained": retained,
                          "state": confirmed, "publication": publication, "error": "Publication readback disagreed"}))
        return 18
    publication["uncertain"] = False
    print(json.dumps({"ok": True, "state": confirmed, "publication": publication}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        # Parser exceptions can contain snippets of private input. Report the
        # affected path/class, not the exception's raw message or payload.
        path = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(dict(_result_context, ok=False, path=path,
                              error="Settings I/O failed: " + type(error).__name__)))
        raise SystemExit(1)
