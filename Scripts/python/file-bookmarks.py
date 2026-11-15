#!/usr/bin/env python3
"""Edit GTK bookmarks without discarding labels or unsupported URI entries."""
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import unquote, urlsplit


def local(uri):
    value = urlsplit(uri)
    # Ignore directory trailing slashes, not filesystem-significant link/..
    # components. Matching must preserve the same meaning as navigation.
    return (unquote(value.path).rstrip("/") or "/") if value.scheme == "file" and value.netloc in ("", "localhost") and value.path.startswith("/") and not value.query and not value.fragment else ""


def edit(job):
    path = job["path"]
    if not isinstance(path, str) or not os.path.isabs(path) or "\0" in path:
        raise ValueError("Choose an absolute folder")
    path = path.rstrip("/") or "/"
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    target = (config / "gtk-3.0/bookmarks").resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.with_name(".bookmarks.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            original = target.read_text()
        except FileNotFoundError:
            original = ""
        rows = original.splitlines(keepends=True)
        indices = [i for i, row in enumerate(rows) if local(row.rstrip("\r\n").partition(" ")[0]) == path]
        if job["kind"] == "add":
            if not os.path.isdir(path):
                raise ValueError("Choose an existing folder")
            if not indices:
                if rows and not rows[-1].endswith("\n"):
                    rows[-1] += "\n"
                rows.append(Path(path).as_uri() + "\n")
        elif job["kind"] == "remove":
            rows = [row for i, row in enumerate(rows) if i not in indices]
        elif job["kind"] == "move":
            visible, seen = [], set()
            for i, row in enumerate(rows):
                folder = local(row.rstrip("\r\n").partition(" ")[0])
                if folder not in seen and os.path.isdir(folder):
                    visible.append(i); seen.add(folder)
            if indices and indices[0] in visible:
                at = visible.index(indices[0]); other = at + (-1 if job["direction"] < 0 else 1)
                if 0 <= other < len(visible):
                    a, b = indices[0], visible[other]
                    rows[a], rows[b] = rows[b], rows[a]
                    # A formerly final unterminated row is now an interior row.
                    if not rows[a].endswith("\n"): rows[a] += "\n"
                    if not rows[b].endswith("\n"): rows[b] += "\n"
        else:
            raise ValueError("Unknown bookmark action")
        text = "".join(rows)
        if text != original:
            name = None
            try:
                with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, prefix=".bookmarks-", delete=False) as stream:
                    name = stream.name
                    stream.write(text); stream.flush(); os.fsync(stream.fileno())
                    os.fchmod(stream.fileno(), target.stat().st_mode & 0o777 if target.exists() else 0o600)
                os.replace(name, target)
                name = None
            finally:
                if name is not None: os.unlink(name)


if __name__ == "__main__":
    try:
        edit(json.load(sys.stdin))
        print(json.dumps({"ok": True}))
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
