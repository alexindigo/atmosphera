#!/usr/bin/env python3
"""Inert Git matrix endpoint; only disposable PATH uses this executable."""
import json
import os
from pathlib import Path
import sys
import time

name, args = Path(sys.argv[0]).name, sys.argv[1:]
root = Path(os.environ['PHA_GIT_OUTPUT'])
with (root / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(dict(endpoint=name, argv=args)) + '\n')
if name not in ('gh', 'glab'):
    raise SystemExit(90)
if args in (['--version'], ['auth', 'status']):
    print('inert synthetic client')
elif args == ['api', 'user']:
    print(json.dumps(dict(login='synthetic-user', username='synthetic-user')))
elif (name == 'gh' and args[:2] in (['search', 'issues'], ['search', 'prs'])) or (name == 'glab' and args[:2] in (['issue', 'list'], ['mr', 'list'])):
    scope = 'global'
    for key in ('--repo', '--owner', '--group'):
        if key in args:
            scope = args[args.index(key) + 1]
    if scope == 'synthetic/beta' and (root / 'hold').exists():
        (root / 'entered').write_text('entered\n')
        deadline = time.monotonic() + 45
        while not (root / 'release').exists():
            if time.monotonic() > deadline:
                raise RuntimeError('old response barrier timed out')
            time.sleep(0.02)
    print(json.dumps([dict(number=1, iid=1, title='result for ' + scope,
                           url='', web_url='', repository=dict(nameWithOwner=scope),
                           references=dict(full=scope + '#1'))]))
else:
    raise SystemExit(91)
