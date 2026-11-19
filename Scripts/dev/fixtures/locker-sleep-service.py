#!/usr/bin/python3
"""Disposable-guest sleep-service barrier. Never calls a kernel sleep API.

The real logind manager, signals and delay inhibitor remain in use. Only the
guest's systemd-suspend.service ExecStart is replaced for this proof. Successful
exit models completion/resume and makes logind emit PrepareForSleep(false).
"""
import argparse
import json
from pathlib import Path
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
args = parser.parse_args()
def publish(name, value):
    path = args.work / name
    temporary = path.with_suffix('.new')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)

publish('sleep-service-entered.json', {'monotonic': time.monotonic(),
    'kernelSleepInvoked': False})
deadline = time.monotonic() + 60
while not args.work.joinpath('release-sleep-service').exists() and time.monotonic() < deadline:
    time.sleep(.02)
publish('sleep-service-finished.json', {'monotonic': time.monotonic(),
    'released': args.work.joinpath('release-sleep-service').exists(), 'kernelSleepInvoked': False})
if not args.work.joinpath('release-sleep-service').exists():
    raise SystemExit(1)
