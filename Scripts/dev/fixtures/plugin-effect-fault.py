"""Permission fault scoped to this witness's private preference directory."""
from pathlib import Path
import os
import json
import sys
config = Path(sys.argv[1])
assert config.name == "effect-config"
directory = config / "settings/plugins"
assert directory.is_dir() and not directory.is_symlink()
assert sys.argv[2] in ("block", "repair", "foreign", "foreign-root")
if sys.argv[2] in ("foreign", "foreign-root"):
    name = sys.argv[3]
    assert name and "/" not in name and name not in (".", "..")
    path = directory / (name + ".json")
    assert path.is_file() and not path.is_symlink()
    raw = json.loads(path.read_text())
    if sys.argv[2] == "foreign": raw["opaque"] = {"keep": True, "foreign": True}
    else: raw["foreign"] = True
    path.write_text(json.dumps(raw) + "\n")
else:
    os.chmod(directory, 0o500 if sys.argv[2] == "block" else 0o700)
