#!/usr/bin/env python3
"""Only loopback curl and a browser substitute driving the real OAuth listener."""
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import urlopen

case = Path(os.environ['PHA_SPOTIFY_CASE'])
row = dict(pid=os.getpid(), start=Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19], command=Path(sys.argv[0]).name)
with (case / 'endpoint-pids.jsonl').open('a') as log: log.write(json.dumps(row) + '\n')
if row['command'] == 'curl':
    if not any(arg.startswith(os.environ['PHA_SPOTIFY_ORIGIN'] + '/') for arg in sys.argv[1:]): raise SystemExit('non-loopback curl refused')
    os.execv('/usr/bin/curl', ['curl', '-sS', *sys.argv[1:]])
query = parse_qs(urlparse(sys.argv[1]).query)
with (case / 'browser.jsonl').open('a') as log: log.write(json.dumps(query) + '\n')
deadline = time.monotonic() + 8
while (case / 'hold-callback').exists() and time.monotonic() < deadline: time.sleep(.025)
state = 'wrong-state' if (case / 'wrong-state').exists() else query['state'][0]
target = query['redirect_uri'][0] + '?' + urlencode(dict(code='controlled', state=state))
while True:
    try:
        with urlopen(target, timeout=1) as response: response.read()
        break
    except OSError:
        if time.monotonic() >= deadline: raise
        time.sleep(.025)
