#!/usr/bin/env python3
"""Independent complete native-document oracle for selected text sources."""
import json
from pathlib import Path
import sys

from json_evidence import require_json_match
import time

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if boundary in ('deny', 'allow'):
    target = case / 'config/settings/plugins' if sys.argv[4] == 'shared' else case / 'config/settings'
    target.chmod(0o500 if boundary == 'deny' else 0o700)
    raise SystemExit(0)
if boundary == 'hold':
    (case / 'hold-next').touch(exist_ok=False)
    raise SystemExit(0)
if boundary == 'quiescent':
    identity = json.loads((case / 'held').read_text())
    process = Path('/proc') / str(identity['pid']) / 'stat'
    deadline = time.monotonic() + 5
    while process.exists():
        try:
            start = process.read_text().rsplit(')', 1)[1].split()[19]
        except FileNotFoundError:
            break
        if start != identity['start']:
            break
        if time.monotonic() >= deadline:
            raise SystemExit('held endpoint remains alive after worker cancellation')
        time.sleep(0.02)
    with (case / 'quiescence.jsonl').open('a') as stream:
        stream.write(json.dumps(dict(status='PASS', identity=identity)) + '\n')
    raise SystemExit(0)
expected = json.loads((case / 'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case / 'config/settings/plugins/not-just-text.json').read_text()),
              bar=json.loads((case / 'config/settings/bar.json').read_text()))
require_json_match(actual, expected, 'TEXT_DISK ' + boundary + ': complete document mismatch')
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('TEXT_DISK ' + boundary + ': PASS', flush=True)
