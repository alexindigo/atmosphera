#!/usr/bin/env python3
"""Observable replacement of this scenario's synthetic shared source only."""
import json
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
assert path == Path(os.environ['PHA_GIT_CASE']) / 'config/settings/plugins/git-companion.json'
value = json.loads(path.read_text())
value['repo'] = 'synthetic/gamma'
replacement = path.with_suffix('.replacement')
with replacement.open('x') as stream:
    json.dump(value, stream, indent=2)
    stream.write('\n')
os.replace(replacement, path)
