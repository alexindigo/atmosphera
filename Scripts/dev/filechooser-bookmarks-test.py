#!/usr/bin/env python3
"""Real GTK-bookmark edits in the caller's disposable guest directory."""
import json
import os
from pathlib import Path
import subprocess
import sys

base = Path(sys.argv[1])
base.mkdir()
config = base / "config"
target = config / "gtk-3.0/bookmarks"
target.parent.mkdir(parents=True)
folders = [base / name for name in ("hash#literal", "second", "third")]
for folder in folders: folder.mkdir()
rows = ["smb://server/share Keep network label\n", folders[0].as_uri() + " First label\n", "file:///missing Keep missing\n", folders[1].as_uri() + " Second label\n"]
target.write_text("".join(rows))
worker = Path(__file__).resolve().parents[1] / "python/file-bookmarks.py"
cases = []


def check(name, value):
    cases.append({"case": "bookmarks." + name, "pass": bool(value)})
    assert value, name


def edit(kind, path, **extra):
    process = subprocess.run([sys.executable, "-B", str(worker)], input=json.dumps(dict(kind=kind, path=str(path), **extra)),
                             env=dict(os.environ, XDG_CONFIG_HOME=str(config)), capture_output=True, text=True, timeout=10, check=True)
    return json.loads(process.stdout)


check("add", edit("add", folders[2])["ok"] and target.read_text().splitlines()[-1] == folders[2].as_uri())
before = target.read_bytes()
check("dedup", edit("add", folders[2])["ok"] and target.read_bytes() == before)
check("reorder", edit("move", folders[1], direction=-1)["ok"] and target.read_text().splitlines()[1] == rows[3].rstrip())
check("preserve-foreign-labels", rows[0] in target.read_text() and rows[2] in target.read_text() and rows[1] in target.read_text())
check("remove", edit("remove", folders[0])["ok"] and rows[1] not in target.read_text())
# Read the file again for every action, retaining an external editor's updates.
with target.open("a") as stream: stream.write("sftp://server/new External editor\n")
edit("move", folders[2], direction=-1)
check("external-edits", "sftp://server/new External editor\n" in target.read_text())
before = target.read_bytes()
check("invalid-no-write", not edit("add", base / "missing")["ok"] and target.read_bytes() == before)
target.parent.chmod(0o555)
check("permission-no-write", not edit("remove", folders[1])["ok"] and target.read_bytes() == before)
target.parent.chmod(0o755)
stored = target.with_name("stored-bookmarks")
target.rename(stored)
target.symlink_to(stored)
check("symlink-preserved", edit("add", folders[0])["ok"] and target.is_symlink() and folders[0].as_uri() in stored.read_text())
print(json.dumps(cases))
