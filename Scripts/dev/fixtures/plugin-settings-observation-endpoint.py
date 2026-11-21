#!/usr/bin/python3
"""Inert observation/action endpoint. Never executes a target or shell fragment."""
import fcntl
import json
import os
from pathlib import Path
import sys

name, args = Path(sys.argv[0]).name, sys.argv[1:]
start = (Path('/proc') / str(os.getpid()) / 'stat').read_text().split(') ', 1)[1].split()[19]
with Path(os.environ['PHA_OBSERVATION_REQUESTS']).open('a') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX)
    stream.write(json.dumps(dict(command=name, argv=args, pid=os.getpid(), start=start)) + '\n')
    stream.flush()
if name == 'which':
    print('/controlled/' + args[-1])
elif name == 'ss':
    print('State Recv-Q Send-Q Local Address:Port Peer Address:Port Process')
    if args == ['-tlnp']:
        print('LISTEN 0 128 127.0.0.1:80 0.0.0.0:* users:(("system",pid=90001,fd=3))')
        print('LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("selected-http",pid=90002,fd=3))')
    elif args == ['-ulnp']:
        print('UNCONN 0 0 127.0.0.1:9090 0.0.0.0:* users:(("selected-udp",pid=90003,fd=3))')
    else:
        raise SystemExit('unreviewed ss arguments')
elif name == 'kill':
    if args != ['90002']:
        raise SystemExit('unreviewed inert kill target')
elif name == 'ghostty':
    expected = ['-e', 'sh', '-c', 'echo \'Killing process on port 9090/udp...\' && sudo fuser -k 9090/udp && echo \'Done.\' || echo \'Failed.\'; read -n 1 -p "Press any key to exit..."']
    if args != expected:
        raise SystemExit('unreviewed inert terminal arguments')
elif name == 'mullvad':
    if args == ['status', '--json']:
        print(json.dumps(dict(state='connected', details=dict(endpoint=dict(address='192.0.2.10'), location=dict(country='se', city='Controlled City', ipv4='192.0.2.10', hostname='controlled-host')))))
    elif args == ['relay', 'list']:
        print('Sweden (se)\n\tStockholm (sto)\n\t\tse-sto-wg-001 (192.0.2.20)')
    elif args == ['relay', 'get']:
        print('Location: country se')
    elif args == ['account', 'get']:
        print('Expires at: 2099-01-01')
    elif args in [['lockdown-mode', 'get'], ['auto-connect', 'get'], ['lan', 'get']]:
        print('State: off')
    elif args in [['relay', 'set', 'location'], ['connect'], ['disconnect'], ['lockdown-mode', 'set', 'on']]:
        pass
    else:
        raise SystemExit('unreviewed inert Mullvad action ' + repr(args))
else:
    raise SystemExit('unreviewed inert endpoint ' + name)
