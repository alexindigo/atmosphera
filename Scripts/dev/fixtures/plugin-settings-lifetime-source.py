#!/usr/bin/env python3
"""Equal bytes, new inode: isolated foreign-source preflight witness."""
import os
import json
from pathlib import Path
import sys

target = Path(sys.argv[1]).resolve(strict=True)
root = Path(os.environ['PHA_WORK_BASE']).resolve(strict=True)
if not target.is_relative_to(root) or target.name != 'lifetime-fixture.json':
    raise SystemExit('source replacement outside isolated fixture refused')
before = target.stat()
candidate = target.with_suffix('.replacement')
with candidate.open('xb') as stream:
    data = target.read_bytes()
    if sys.argv[2] == 'change':
        value = json.loads(data)
        value['label'] = 'foreign-source'
        data = (json.dumps(value) + '\n').encode()
    elif sys.argv[2] != 'equal':
        raise SystemExit('unknown source mutation')
    stream.write(data)
    stream.flush()
    os.fsync(stream.fileno())
os.replace(candidate, target)
assert target.stat().st_ino != before.st_ino
print('LIFETIME_SOURCE_REPLACED')
