#!/usr/bin/python3
"""Inert camera and KDE discovery/action endpoints; no real device effects."""
import json
import os
from pathlib import Path
import sys

name, argv = Path(sys.argv[0]).name, sys.argv[1:]
stat = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()
with open(os.environ['PHA_PROJECTION_REQUESTS'], 'a') as log:
    log.write(json.dumps(dict(command=name, argv=argv, pid=os.getpid(), start=stat[19])) + '\n')
if name == 'which':
    if argv == ['busctl']:
        print(str(Path(__file__).with_name('busctl')))
elif name == 'sh':
    if len(argv) == 2 and argv[0] == '-c' and argv[1].startswith('for dev in /sys/class/video4linux/'):
        print('Controlled Camera')
    else:
        # The shell's normal bootstrap works only in this case's isolated roots.
        # Intercept the physical camera command, not unrelated registry helpers.
        os.execv('/bin/sh', ['/bin/sh', *argv])
elif name == 'busctl':
    if 'status' not in argv:
        method = argv[6] if len(argv) > 6 else ''
        target = argv[4] if len(argv) > 4 else ''
        if method == 'devices':
            data = [['phone-a', 'phone-b']]
        elif method == 'name':
            data = 'Phone B' if 'phone-b' in target else 'Phone A'
        elif method in ('isReachable', 'isPaired'):
            data = True
        elif method == 'isPairRequested':
            data = False
        elif method == 'charge':
            data = 42 if 'phone-b' in target else 81
        elif method == 'isCharging':
            data = False
        elif method == 'activeNotifications':
            data = [[]]
        elif method == 'cellularNetworkType':
            data = 'LTE'
        elif method == 'cellularNetworkStrength':
            data = 3
        else:
            data = ''
        print(json.dumps(dict(data=data)))
