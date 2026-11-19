#!/usr/bin/python3
"""Bounded test-only scheduling around the guest's real FFmpeg executable."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

state = Path(os.environ['I5_THUMB_CONTROL'])
count = json.loads(state.read_text())['calls'] + 1


def publish(finished, code=None):
    part = state.with_suffix('.part')
    part.write_text(json.dumps(dict(calls=count, finished=finished, code=code)))
    part.replace(state)


publish(False)
release = state.parent / ('release-' + str(count))
deadline = time.monotonic() + 12
while not release.exists():
    if time.monotonic() >= deadline:
        publish(True, 124)
        raise SystemExit(124)
    time.sleep(.01)
result = subprocess.run(['/usr/bin/ffmpeg', *sys.argv[1:]], stdin=subprocess.DEVNULL, timeout=15)
publish(True, result.returncode)
raise SystemExit(result.returncode)
