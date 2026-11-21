#!/usr/bin/env python3
"""Hold the real helper's existing settings lock, never mock its publication."""
import fcntl
import os
from pathlib import Path
import time

root = Path(os.environ['PHA_MUSIC_CASE'])
with (root / 'helper/settings.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    (root / 'locked').write_text('locked\n')
    deadline = time.monotonic() + 40
    while not (root / 'release').exists():
        if time.monotonic() > deadline:
            raise RuntimeError('music settings lock barrier timed out')
        time.sleep(0.02)
