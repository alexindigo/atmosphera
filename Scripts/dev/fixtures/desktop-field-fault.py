"""Scoped real directory-permission failure for private desktop-field fixtures."""
import json
import os
from pathlib import Path
import stat
import sys

config = Path(sys.argv[1])
assert config.resolve().is_relative_to('/home/tester/Projects/atcq/g') and not config.is_symlink()
plugins = len(sys.argv) == 4 and sys.argv[3] == 'plugins'
assert len(sys.argv) == 3 or plugins
directory = config/('settings/plugins' if plugins else 'settings')
assert directory.is_dir() and not directory.is_symlink() and directory.stat().st_uid == os.getuid()
receipt = config/('plugin-field-fault.json' if plugins else 'desktop-field-fault.json')
value = directory.stat()
if sys.argv[2] == 'block':
    if receipt.exists():
        old = json.loads(receipt.read_text())
        assert (value.st_dev, value.st_ino, stat.S_IMODE(value.st_mode)) == (old['dev'], old['inode'], old['mode'])
    row = dict(dev=value.st_dev, inode=value.st_ino, mode=stat.S_IMODE(value.st_mode))
    assert row['mode'] & 0o200
    receipt.write_text(json.dumps(row)+'\n')
    os.chmod(directory, 0o500)
elif sys.argv[2] == 'repair':
    row = json.loads(receipt.read_text())
    assert (value.st_dev, value.st_ino) == (row['dev'], row['inode'])
    assert stat.S_IMODE(value.st_mode) == 0o500
    os.chmod(directory, row['mode'])
else:
    raise SystemExit('block or repair required')
