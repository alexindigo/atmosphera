#!/usr/bin/env python3
"""Activate the fixture's four Pomodoro toggles through their AT-SPI actions."""
import json
import os
from pathlib import Path
import sys

import pyatspi

LABELS = ('!!settings.auto-start-breaks!!', '!!settings.auto-start-work!!',
          '!!settings.compact-mode!!', 'Play Alarm Sound')


def walk(node):
    yield node
    for child in node:
        if child is not None:
            yield from walk(child)


def main():
    apps = [app for app in pyatspi.Registry.getDesktop(0)
            if app is not None and app.get_process_id() == os.getppid()]
    if len(apps) != 1:
        raise RuntimeError('fixture application missing or ambiguous on the AT-SPI bus')
    nodes = list(walk(apps[0]))
    result = dict(pass_=int(sys.argv[1]), controls=[])
    for label in LABELS:
        matching = [node for node in nodes if node.name == label and node.getRole() == pyatspi.ROLE_CHECK_BOX]
        if len(matching) != 1:
            raise RuntimeError('expected one check box named %r, found %d' % (label, len(matching)))
        node = matching[0]
        action = node.queryAction()
        names = [action.getName(i) for i in range(action.nActions)]
        chosen = 'Toggle' if 'Toggle' in names else 'Press'
        before = node.getState().contains(pyatspi.STATE_CHECKED)
        if chosen not in names or not action.doAction(names.index(chosen)):
            raise RuntimeError('AT-SPI action unavailable for %r: %r' % (label, names))
        result['controls'].append(dict(label=label, actions=names, invoked=chosen, checkedBefore=before))
    path = Path(os.environ['PHA_A11Y_RESULT'])
    previous = json.loads(path.read_text()) if path.exists() else []
    path.write_text(json.dumps(previous + [result], indent=2) + '\n')


if __name__ == '__main__':
    main()
