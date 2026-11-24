#!/usr/bin/env python3
"""Literal argv endpoint: no network, one deterministic USD rates response."""
import json
import os
from pathlib import Path
import signal
import sys
import time

expected = ['-sf', '--connect-timeout', '5', '--max-time', '10', '-L', 'https://api.frankfurter.app/latest?from=USD']
if sys.argv[1:] != expected:
    raise SystemExit('unexpected Currency curl argv: ' + repr(sys.argv[1:]))
case, output = Path(os.environ['PHA_CURRENCY_CASE']), Path(os.environ['PHA_CURRENCY_OUTPUT'])


def event(name):
    with (output / 'curl.jsonl').open('a') as stream:
        stream.write(json.dumps(dict(event=name, pid=os.getpid(), argv=sys.argv[1:])) + '\n')


def cancelled(signum, frame):
    event('cancelled')
    raise SystemExit(0)


signal.signal(signal.SIGTERM, cancelled)
signal.signal(signal.SIGINT, cancelled)
event('requested')
try:
    (case / 'fail-next').unlink()
except FileNotFoundError:
    pass
else:
    event('failed')
    raise SystemExit(22)
if (case / 'hold').exists():
    event('held')
    (case / 'held').write_text(str(os.getpid()))
    while (case / 'hold').exists():
        time.sleep(0.03)
print(json.dumps(dict(rates=dict(EUR=2, GBP=4, JPY=100))), flush=True)
event('responded')
