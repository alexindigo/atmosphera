#!/usr/bin/env python3
"""Inert notification/audio/stop collaborator, no physical effects."""
import json
import os
from pathlib import Path
import sys

stat = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()
with Path(os.environ['PHA_PRAYER_EFFECTS']).open('a') as stream:
    stream.write(json.dumps(dict(pid=os.getpid(), start=stat[19], command=Path(sys.argv[0]).name, argv=sys.argv[1:])) + '\n')
