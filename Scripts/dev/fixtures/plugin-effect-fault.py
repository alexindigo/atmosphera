"""Permission fault scoped to this witness's private preference directory."""
from pathlib import Path
import os
import sys
config = Path(sys.argv[1])
assert config.name == "effect-config"
directory = config / "settings/plugins"
assert directory.is_dir() and not directory.is_symlink()
assert sys.argv[2] in ("block", "repair")
os.chmod(directory, 0o500 if sys.argv[2] == "block" else 0o700)
