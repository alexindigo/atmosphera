#!/usr/bin/env python3
"""Independent complete native-document oracle for the Git consumer matrix."""
import hashlib
import json
import os
from pathlib import Path
import sys

from fixture_paths import require_owned_path

config, phase = Path(sys.argv[1]), sys.argv[2]
case, output = Path(os.environ['PHA_GIT_CASE']), Path(os.environ['PHA_GIT_OUTPUT'])
require_owned_path(config, case, 'Git Matrix config')
if config != case / 'config':
    raise ValueError(f'Git Matrix config: expected {case / "config"}, got {config}')
expected = json.loads((case / 'expectations.json').read_text())[phase]
paths = {'shared': config / 'settings/plugins/git-companion.json',
         'bar': config / 'settings/bar.json'}
actual = {key: json.loads(path.read_text()) for key, path in paths.items()}
if actual != expected:
    raise AssertionError('GIT_DISK: ' + phase + '\n' + json.dumps(actual, sort_keys=True) + '\n' + json.dumps(expected, sort_keys=True))
with (output / 'persisted' / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', phase=phase, values=actual,
                   hashes={key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in paths.items()}), stream, indent=2)
print('GIT_DISK: PASS ' + phase, flush=True)
