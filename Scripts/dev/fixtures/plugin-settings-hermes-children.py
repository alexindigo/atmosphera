#!/usr/bin/env python3
"""Independent exact SSH child identities at QML replacement/retirement boundaries."""
import json
from pathlib import Path
import sys
import time

case, output, boundary, expected = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], set(json.loads(sys.argv[4]))
rows = [json.loads(line) for line in (case / 'requests.jsonl').read_text().splitlines()]
children = [row for row in rows if row['event'] == 'start']
def exists(row):
    try: return (Path('/proc') / str(row['pid']) / 'stat').read_text().split(') ', 1)[1].split()[19] == row['start']
    except FileNotFoundError: return False
deadline = time.monotonic() + 4
while time.monotonic() < deadline and any(exists(row) for row in children if row['target'] not in expected): time.sleep(0.02)
observed = [{**row, 'present': exists(row)} for row in children]
assert {row['target'] for row in observed if row['present']} == expected, observed
assert all(row['present'] == (row['target'] in expected) for row in observed), observed
output.write_text(json.dumps(dict(status='PASS', boundary=boundary, liveTargets=sorted(expected), identities=observed), indent=2) + '\n')
