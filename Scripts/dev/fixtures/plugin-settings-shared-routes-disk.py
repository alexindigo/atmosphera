#!/usr/bin/env python3
"""Independent complete native-document readback for explicit shared routes."""
import json
import os
from pathlib import Path
import sys

from json_evidence import require_json_match

case, phase = Path(os.environ['PHA_SHARED_ROUTE_CASE']), sys.argv[1]
expected = json.loads((case / 'expectations.json').read_text())[phase]
actual = {name: json.loads((case / 'config' / name).read_text()) for name in expected}
require_json_match(actual, expected, 'shared-route native documents differ at ' + phase)
with (Path(os.environ['PHA_SHARED_ROUTE_OUTPUT']) / 'persisted' / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', documents=actual), stream, indent=2)
print('SHARED_ROUTE_DISK: PASS ' + phase, flush=True)
