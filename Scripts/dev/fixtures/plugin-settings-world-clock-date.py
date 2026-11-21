#!/usr/bin/env python3
"""Finite controlled date endpoint. No network or clock changes."""
import json
import os
from pathlib import Path
import sys

hours = {'America/New_York': '01:11', 'Europe/London': '02:22', 'Asia/Tokyo': '03:33', 'Australia/Sydney': '04:44'}
formats = ('+%H:%M', '+%H:%M:%S', '+%I:%M %p', '+%I:%M:%S %p')
timezone = os.environ.get('TZ')
if len(sys.argv) != 2 or sys.argv[1] not in formats or timezone not in hours:
    raise SystemExit('unexpected World Clock date endpoint: ' + repr((timezone, sys.argv[1:])))
format_string = sys.argv[1]
value = hours[timezone] + (':33' if '%S' in format_string else '') + (' AM' if '%p' in format_string else '')
with (Path(os.environ['PHA_WORLD_OUTPUT']) / 'date.jsonl').open('a') as stream:
    stream.write(json.dumps(dict(timezone=timezone, format=format_string, value=value)) + '\n')
print(value, flush=True)
