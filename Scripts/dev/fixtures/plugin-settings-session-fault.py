#!/usr/bin/env python3
"""Guarded user-owned permission fault, only under the verified guest work root."""
import os
from pathlib import Path
import stat
import sys

config = Path(sys.argv[1])
assert config == config.resolve() and config.is_relative_to(Path(os.environ['PHA_WORK_BASE']))
directory = config / 'settings/plugins'
assert directory.is_dir() and not directory.is_symlink() and directory.stat().st_uid == os.getuid()
if sys.argv[2] == 'block':
    assert stat.S_IMODE(directory.stat().st_mode) == 0o755
    directory.chmod(0o500)
elif sys.argv[2] == 'repair':
    assert stat.S_IMODE(directory.stat().st_mode) == 0o500
    directory.chmod(0o755)
else:
    raise SystemExit('block or repair required')
