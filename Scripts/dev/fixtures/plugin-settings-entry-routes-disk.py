#!/usr/bin/env python3
"""Read every isolated owning document independently at the real route boundary."""
import json
import importlib.util
import os
from pathlib import Path
import sys

config, phase = Path(sys.argv[1]), sys.argv[2]
expected = json.loads(Path(os.environ['PHA_ROUTE_EXPECTATIONS']).read_text())[phase]
actual = {name: json.loads((config / 'settings' / name).read_text()) for name in expected}
if actual != expected:
    raise AssertionError('route persisted mismatch at ' + phase + '\n' + json.dumps(actual, sort_keys=True) + '\n' + json.dumps(expected, sort_keys=True))
with (Path(os.environ['PHA_ROUTE_OUTPUT']) / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', documents=actual), stream, indent=2)
print('ENTRY_ROUTE_DISK: PASS ' + phase, flush=True)
if phase in ('edited', 'whole-reset', 'retry'):
    spec = importlib.util.spec_from_file_location('route_regression', Path(__file__).resolve().parents[1] / 'plugin-settings-entry-routes-regression.py')
    routes = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(Path(spec.origin).parent))
    spec.loader.exec_module(routes)
    routes.cold_boundary_from_environment(phase)
