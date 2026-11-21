#!/usr/bin/env python3
"""Join an admitted runtime action at its independent whole-document endpoint."""
import json
from pathlib import Path
import runpy
import sys
import time

case, boundary = Path(sys.argv[1]), sys.argv[3]
plugin = json.loads((case / 'input.json').read_text())['plugin']
expected = json.loads((case / 'expectations.json').read_text())[boundary]
deadline = time.monotonic() + 8
while True:
    actual = dict(shared=json.loads((case / ('config/settings/plugins/' + plugin + '.json')).read_text()), bar=json.loads((case / 'config/settings/bar.json').read_text()))
    if actual == expected or time.monotonic() >= deadline:
        break
    time.sleep(0.03)
runpy.run_path(str(Path(__file__).with_name('plugin-settings-query-disk.py')), run_name='__main__')
