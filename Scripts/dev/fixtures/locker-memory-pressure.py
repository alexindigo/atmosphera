#!/usr/bin/python3
"""Bounded, supervised guest-only resident-memory pressure for locker proofs."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--mib', type=int, required=True)
args = parser.parse_args()
assert subprocess.check_output(['id', '-un'], text=True).strip() == 'tester'
assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip() == os.environ['LOCKER_TEST_VM_UUID']
assert args.work.resolve().is_relative_to(Path('/home/tester/Projects/locker'))
assert Path(os.environ['TMPDIR']).resolve().is_relative_to(Path('/home/tester/Projects/locker'))
memory = bytearray(args.mib * 1024 * 1024)
for offset in range(0, len(memory), 4096):
    memory[offset] = 17
(args.work / 'resident.json').write_text(json.dumps({'pid': os.getpid(), 'bytes': len(memory),
    'stat': Path('/proc/self/stat').read_text(), 'status': Path('/proc/self/status').read_text(),
    'memoryPressure': Path('/proc/pressure/memory').read_text(), 'readyAt': time.monotonic()}, indent=2))
while not (args.work / 'release').exists():
    for offset in range(0, len(memory), 4096):
        memory[offset] = (memory[offset] + 1) & 255
    time.sleep(.1)
