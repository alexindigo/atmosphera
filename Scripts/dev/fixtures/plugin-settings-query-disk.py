#!/usr/bin/env python3
"""Independent complete native document readback for query representatives."""
import json
from pathlib import Path
import sys

from json_evidence import require_json_match

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
plugin = json.loads((case / 'input.json').read_text())['plugin']
expected = json.loads((case / 'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case / ('config/settings/plugins/' + plugin + '.json')).read_text()), bar=json.loads((case / 'config/settings/bar.json').read_text()))
require_json_match(actual, expected, 'QUERY_DISK ' + boundary)
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('QUERY_DISK ' + boundary + ': PASS', flush=True)
