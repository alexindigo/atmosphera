#!/usr/bin/env python3
"""Literal curl collaborator; synthetic GitHub accounts only, never network IO."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import struct
import time
import zlib
from urllib.parse import parse_qs, urlparse

args = sys.argv[1:]
stat = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()
row = dict(pid=os.getpid(), start=stat[19], argv=args)
with Path(os.environ['PHA_PROVIDER_REQUESTS']).open('a') as stream:
    stream.write(json.dumps(row) + '\n')
url = next((arg for arg in args if arg.startswith(('https://', 'http://'))), '')
life = os.environ.get('PHA_PROVIDER_LIFECYCLE') == '1'
if '/following?' in url:
    name = url.split('/users/', 1)[1].split('/')[0]
    if name.startswith('held'): time.sleep(2)
    page = parse_qs(urlparse(url).query)['page'][0]
    result = [dict(login='chain_' + str(i)) for i in (range(100) if page == '1' else [100])] if life and name == 'chain' else []
elif '/notifications' in url:
    if '-X' in args and args[args.index('-X') + 1] == 'PATCH':
        if life: time.sleep(1.2)
        result = {}
    else:
        result = [dict(id=str(i), subject=dict(type='Issue', title='controlled-' + str(i), url='https://api.github.com/repos/owner/repo/issues/1'), repository=dict(full_name='owner/repo'), unread=True) for i in range(3)] if life else []
elif '/graphql' in url:
    query = json.loads(args[args.index('-d') + 1])['query']
    matches = re.findall(r'user\(login: "([^"]+)"\)', query)
    match = re.search(r'user\(login: "([^"]+)"\)', query)
    name = match[1] if match else 'unknown'
    if name == 'held':
        time.sleep(2)
    now = datetime.now(timezone.utc).isoformat()
    count = 2 if name == 'selected' else 1
    edges = [dict(starredAt=now, node=dict(login='actor-' + name + '-' + str(i), avatarUrl='')) for i in range(count)]
    if life and 'u0:' in query:
        previous = [json.loads(line) for line in Path(os.environ['PHA_PROVIDER_REQUESTS']).read_text().splitlines()]
        attempts = sum(1 for row in previous if row.get('argv') == args)
        if name == 'chain_0' and attempts == 1:
            result = dict(errors=[dict(message='controlled-retry')])
        else:
            result = dict(data={**{'u' + str(i): dict(login=user, avatarUrl='', starredRepositories=dict(nodes=[dict(nameWithOwner=user + '/controlled')], edges=[dict(starredAt=now)])) for i, user in enumerate(matches)}, 'rateLimit': dict(cost=1)})
    else:
        result = dict(data=dict(user=dict(repositories=dict(nodes=[dict(nameWithOwner=name + '/controlled', stargazers=dict(edges=edges), forks=dict(nodes=[]))])), rateLimit=dict(cost=1)))
elif '-o' in args:
    if '/held?' in url:
        Path(os.environ['PHA_PROVIDER_CASE'], 'avatar-held').write_text('admitted')
        time.sleep(1.2)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\x00\x20\x80\xff\xff')) + chunk(b'IEND', b'')
    Path(args[args.index('-o') + 1]).write_bytes(png)
    result = {}
else:
    raise SystemExit('unreviewed inert GitHub endpoint: ' + url)
print(json.dumps(result))
