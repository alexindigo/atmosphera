#!/usr/bin/env python3
"""Independent complete native documents and synthetic physical threshold oracle."""
import hashlib
import json
import os
from pathlib import Path
import sys

case, out = Path(os.environ['PHA_BATTERY_CASE']), Path(os.environ['PHA_BATTERY_OUTPUT'])
phase = sys.argv[1]
paths = dict(shared=case / 'config/settings/plugins/battery-threshold.json', bar=case / 'config/settings/bar.json')
actual = {key: json.loads(path.read_text()) for key, path in paths.items()}
actual['batteries'] = {name: int((case / 'devices' / name / 'charge_control_end_threshold').read_text()) for name in ('BAT0', 'BAT1')}
expected = json.loads((case / 'expectations.json').read_text())[phase]
assert actual == expected, 'BATTERY_DISK ' + phase + '\n' + json.dumps(actual) + '\n' + json.dumps(expected)
with (out / 'persisted' / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', values=actual, hashes={key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in paths.items()}), stream, indent=2)
print('BATTERY_DISK: PASS ' + phase, flush=True)
