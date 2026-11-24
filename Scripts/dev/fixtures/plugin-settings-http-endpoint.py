#!/usr/bin/env python3
"""Inert literal-argv Habitica collaborator. Never contacts a remote account."""
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import parse_qs, urlparse

args = sys.argv[1:]
headers = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == '-H']
user = next(value.split(': ', 1)[1] for value in headers if value.startswith('x-api-user: '))
method = args[args.index('-X') + 1]
url = urlparse(args[-1])
start = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19]
row = dict(argv=args, user=user, method=method, path=url.path, pid=os.getpid(), start=start)
with open(os.environ['PHA_HTTP_REQUESTS'], 'a') as stream:
    stream.write(json.dumps(row) + '\n'); stream.flush()
if user == 'held' or method == 'POST' or (user == 'shared' and url.path == '/api/v3/user'):
    time.sleep(1.4)
if method == 'POST':
    data = dict(hp=44, lvl=8)
elif url.path == '/api/v3/user':
    data = dict(profile=dict(name='account-' + user), stats=dict(hp=44, lvl=8, gp=2))
elif url.path.endswith('/tags'):
    data = [dict(id='tag-a', name='Tag A'), dict(id='tag-b', name='Tag B')]
else:
    kind = parse_qs(url.query)['type'][0]
    data = [dict(id=user + "/task '" + str(i), text='task-' + user + '-' + str(i), type='daily' if kind == 'dailys' else 'todo' if kind == 'todos' else 'habit', tags=['tag-a' if i == 0 else 'tag-b'], checklist=[dict(id="item/'", text='check-' + user, completed=False)]) for i in range(2)]
print(json.dumps(dict(success=True, data=data)), flush=True)
