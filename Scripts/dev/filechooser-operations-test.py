#!/usr/bin/env python3
"""Filesystem end-of-chain proofs; invoked inside the chooser unit namespace."""
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote


def main():
    root = Path(sys.argv[1])
    root.mkdir()
    folder = root / "files"
    folder.mkdir()
    data = root / "data"
    data.mkdir()
    env = dict(os.environ, XDG_DATA_HOME=str(data))
    worker = Path(__file__).resolve().parents[1] / "python/file-operations.py"
    cases = []

    def op(kind, names, **extra):
        result = subprocess.run([sys.executable, "-B", str(worker)], input=json.dumps(dict(kind=kind, folder=str(folder), names=names, **extra)),
                                capture_output=True, text=True, check=True, timeout=10, env=env)
        assert not result.stderr, result.stderr
        return json.loads(result.stdout)

    def check(name, predicate):
        cases.append(dict(case="operations.fs-" + name, **{"pass": bool(predicate)}))
        assert predicate, name

    for value in ("", ".", "..", "../escape", "bad\0name"):
        check("invalid-" + repr(value), op("create", [value]) == {"ok": False, "reason": "invalid"})
    check("create", op("create", ["directory"])["ok"] and (folder / "directory").is_dir())
    (folder / "source").write_text("original bytes")
    (folder / "target").write_text("target bytes")
    check("rename-no-clobber", not op("rename", ["source"], name="target")["ok"] and (folder / "source").read_text() == "original bytes" and (folder / "target").read_text() == "target bytes")
    (folder / "broken").symlink_to(folder / "absent")
    check("rename-no-clobber-link", not op("rename", ["source"], name="broken")["ok"] and (folder / "broken").is_symlink())
    check("rename-literal-name", op("rename", ["source"], name="résumé #%?.txt")["ok"] and (folder / "résumé #%?.txt").read_text() == "original bytes")
    check("rename-directory", op("rename", ["directory"], name="renamed directory")["ok"] and (folder / "renamed directory").is_dir())
    check("missing", not op("rename", ["missing"], name="new")["ok"])
    check("too-long", op("create", ["a" * 300])["errors"][0]["reason"] == "long")
    folder.chmod(0o555)
    try:
        check("permission", op("create", ["denied"])["errors"][0]["reason"] == "permission")
    finally:
        folder.chmod(0o755)
    pending = op("inspect", ["target"])
    (folder / "target").rename(folder / "old-target")
    (folder / "target").write_text("replacement bytes")
    check("delete-changed-identity", op("delete", ["target"], identities=pending["identities"])["reason"] == "changed" and (folder / "target").read_text() == "replacement bytes")
    outside = root / "outside"
    outside.mkdir()
    (outside / "kept").write_text("not deleted")
    (folder / "renamed directory/link").symlink_to(outside, target_is_directory=True)
    (folder / "renamed directory/child").write_text("delete child")
    pending = op("inspect", ["renamed directory"])
    check("delete-tree-no-follow", op("delete", ["renamed directory"], identities=pending["identities"])["ok"] and not (folder / "renamed directory").exists() and (outside / "kept").read_text() == "not deleted")
    (folder / "outside-link").symlink_to(outside, target_is_directory=True)
    pending = op("inspect", ["outside-link"])
    check("delete-link-not-target", op("delete", ["outside-link"], identities=pending["identities"])["ok"] and (outside / "kept").exists())
    check("trash-literal", op("trash", ["résumé #%?.txt"])["ok"] and not (folder / "résumé #%?.txt").exists())
    (folder / "résumé #%?.txt").write_text("second trash bytes")
    check("trash-collision", op("trash", ["résumé #%?.txt"])["ok"])
    trash = data / "Trash"
    infos = sorted((trash / "info").glob("*.trashinfo"))
    check("trash-recoverable-bytes", sorted(p.read_text() for p in (trash / "files").iterdir()) == ["original bytes", "second trash bytes"])
    parsed = []
    for info in infos:
        config = configparser.ConfigParser(interpolation=None)
        config.read(info)
        parsed.append(config["Trash Info"])
    check("trash-freedesktop-metadata", len(parsed) == 2 and all(unquote(p["Path"]) == str(folder / "résumé #%?.txt") and "T" in p["DeletionDate"] for p in parsed))
    (folder / "link-to-keep").symlink_to(outside / "kept")
    check("trash-link-not-target", op("trash", ["link-to-keep"])["ok"] and (outside / "kept").read_text() == "not deleted")
    (folder / "partial").write_text("partial success")
    result = op("trash", ["partial", "missing"])
    check("partial-result", not result["ok"] and result["completed"] == ["partial"] and result["errors"][0]["name"] == "missing" and not (folder / "partial").exists())
    check("no-delete-without-snapshot", not op("delete", ["target"])["ok"] and (folder / "target").exists())
    print(json.dumps(cases))


if __name__ == "__main__":
    main()
