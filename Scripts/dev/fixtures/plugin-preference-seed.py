"""Publish only a fresh private fixture's original raw seed, before owner open."""
import json
import os
from pathlib import Path
import sys

config=Path(sys.argv[1]);name=sys.argv[2];seed=json.loads(sys.argv[3])
assert config.resolve().is_relative_to('/home/tester/Projects/atcq') and not config.is_symlink()
assert name not in ('','.','..') and '/' not in name and '\0' not in name
assert (config/'plugins'/name/'manifest.json').is_file() and isinstance(seed,dict)
directory=config/'settings/plugins'
assert directory.is_dir() and not directory.is_symlink()
assert directory.resolve().is_relative_to(config.resolve())
target=directory/(name+'.json')
assert not os.path.lexists(target), 'fixture seed may not overwrite existing preferences'
with target.open('x') as stream:stream.write(json.dumps(seed)+'\n')
