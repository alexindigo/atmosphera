#!/usr/bin/env python3
"""Independent typed JSON readback at each native field receipt boundary."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

from fixture_paths import require_owned_path

config, expectations, phase, output = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
require_owned_path(config, Path(os.environ['PHA_WORK_BASE']), 'Values config')
require_owned_path(output, Path(os.environ['PHA_OUTPUT_BASE']), 'Values output')
expected = json.loads(expectations.read_text())[phase]
shared_path = config / 'settings/plugins/values-fixture.json'
shared = json.loads(shared_path.read_text())
family = os.environ['PHA_VALUES_FAMILY']
shard = 'bar' if family in ('shared', 'global-bar', 'monitor-bar') else 'controlCenter' if family == 'control-center' else 'desktopWidgets'
document = json.loads((config / 'settings' / (shard + '.json')).read_text())
rows = (document['widgets']['left'] if family in ('shared', 'global-bar') else document['screenOverrides'][0]['widgets']['left']
        if family == 'monitor-bar' else document['shortcuts']['left'] if family == 'control-center' else document['monitorWidgets'][0]['widgets'])
def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))
actual = dict(shared=shared, rows=rows)
if canonical(actual) != canonical(expected):
    raise AssertionError('typed field persisted mismatch at ' + phase + '\n' + canonical(actual) + '\n' + canonical(expected))
with (output / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', phase=phase, values=actual, sharedSha256=hashlib.sha256(shared_path.read_bytes()).hexdigest()), stream, indent=2)
print('VALUES_DISK: PASS ' + phase, flush=True)
if phase in ('edited', 'reset'):
    spec = importlib.util.spec_from_file_location('values_regression', Path(__file__).resolve().parents[1] / 'plugin-settings-values-regression.py')
    values = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(Path(spec.origin).parent))
    spec.loader.exec_module(values)
    values.cold_boundary_from_environment(phase)
    print('VALUES_COLD_BOUNDARY: PASS ' + phase, flush=True)
