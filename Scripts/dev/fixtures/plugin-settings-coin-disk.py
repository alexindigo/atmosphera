#!/usr/bin/env python3
"""Independent complete documents, including finite rendered operation outcomes."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import time

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
expected = json.loads((case / 'expectations.json').read_text())
if boundary.startswith('operation-'):
    index, result = int(boundary.split('-')[1]), sys.argv[4]
    if result not in ('Heads', 'Tails') or index not in range(4):
        raise SystemExit('unreviewed Coin result/owner')
    values = deepcopy(expected['following']) if index == 0 else json.loads((output / ('operation-' + str(index - 1) + '.json')).read_text())['values']
    target = values['shared'] if index == 0 else values['bar']['widgets']['left'][index - 1].setdefault('instanceSettings', {})
    if index > 0 and result == values['shared']['lastResult']:
        target.pop('lastResult', None)
        if not target:
            values['bar']['widgets']['left'][index - 1].pop('instanceSettings')
    else:
        target['lastResult'] = result
else:
    values = expected[boundary]
deadline = time.monotonic() + 8
while True:
    actual = dict(shared=json.loads((case / 'config/settings/plugins/coin-flip.json').read_text()),
                  bar=json.loads((case / 'config/settings/bar.json').read_text()))
    if actual == values:
        break
    if not boundary.startswith('operation-') or time.monotonic() >= deadline:
        raise SystemExit('COIN_DISK ' + boundary + ': ' + repr((actual, values)))
    time.sleep(0.02)
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('COIN_DISK ' + boundary + ': PASS', flush=True)
