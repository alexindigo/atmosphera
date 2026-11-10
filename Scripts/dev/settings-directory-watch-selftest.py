#!/usr/bin/env python3
"""Exercise the directory-identity CLI without accessing user configuration."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--work-root", type=Path, required=True)
args = parser.parse_args()
helper = Path(__file__).resolve().parents[1] / "python/src/settings/section-io.py"


def identity(path):
    result = subprocess.run([sys.executable, str(helper), "directory", str(path)],
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout)["identity"]


with tempfile.TemporaryDirectory(dir=args.work_root) as directory:
    root = Path(directory)
    target = root / "settings"
    missing = identity(target)
    target.mkdir()
    initial = identity(target)
    assert initial != missing
    (target / "prepared").write_text("test")
    assert identity(target) == initial
    (target / "prepared").rename(target / "published")
    assert identity(target) == initial
    (target / "published").unlink()
    assert identity(target) == initial
    target.rename(root / "old")
    target.mkdir()
    assert identity(target) != initial
    link = root / "linked"
    link.symlink_to(target)
    first = identity(link)
    link.unlink()
    link.symlink_to(root / "old")
    assert identity(link) != first
    link.unlink()
    link.symlink_to(root / "absent")
    assert identity(link) != missing
    file = root / "file"
    file.write_text("not a directory")
    result = subprocess.run([sys.executable, str(helper), "directory", str(file)],
                            capture_output=True, text=True)
    assert result.returncode == 1 and json.loads(result.stdout)["ok"] is False
print("SETTINGS_DIRECTORY_IDENTITY: PASS")
