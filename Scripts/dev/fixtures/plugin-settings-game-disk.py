#!/usr/bin/env python3
"""Independent complete documents, including finite original random/int outcomes."""
import json
from pathlib import Path
import sys
case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
expected = json.loads((case/'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case/'config/settings/plugins/tamagotchi.json').read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
alternatives = expected if isinstance(expected,list) else [expected]
if actual not in alternatives:
    raise SystemExit('GAME_DISK '+boundary+': '+repr((actual,alternatives)))
if boundary=='retired' and actual != json.loads((output/'timer.json').read_text())['values']:
    raise SystemExit('GAME_DISK retirement changed admitted timer document')
(output/(boundary+'.json')).write_text(json.dumps(dict(status='PASS',values=actual),indent=2)+'\n')
print('GAME_DISK '+boundary+': PASS',flush=True)
