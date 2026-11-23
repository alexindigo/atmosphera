#!/usr/bin/env python3
"""Activate Check again through the actual parent fixture's AT-SPI bridge."""
import json
import os
from pathlib import Path
import time

import pyatspi


def walk(node):
    yield node
    for child in node:
        if child is not None:
            yield from walk(child)


def main():
    parent = os.getppid()
    deadline = time.monotonic() + 8
    while True:
        apps = [app for app in pyatspi.Registry.getDesktop(0)
                if app.get_process_id() == parent]
        nodes = [node for app in apps for node in walk(app)
                 if node.name == 'Check again']
        if len(apps) == 1 and len(nodes) == 1:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError('parent fixture Check again AT-SPI node missing or ambiguous')
        time.sleep(0.05)
    node = nodes[0]
    if node.getRole() != pyatspi.ROLE_PUSH_BUTTON:
        raise RuntimeError('Check again is not an AT-SPI push button')
    state = node.getState()
    if not state.contains(pyatspi.STATE_ENABLED) or not state.contains(pyatspi.STATE_FOCUSABLE):
        raise RuntimeError('Check again is not enabled and focusable in AT-SPI')
    action = node.queryAction()
    names = [action.getName(i) for i in range(action.nActions)]
    press = [i for i, name in enumerate(names) if name.lower() in ('press', 'click')]
    # Qt can expose Press through both the button role and the attached action.
    # Select the standard action; duplicate names are not an admission failure.
    if not press:
        raise RuntimeError('Check again AT-SPI press missing: ' + repr(names))
    if not action.doAction(press[0]):
        raise RuntimeError('Check again AT-SPI press was refused: ' + repr(names))
    result = dict(status='PASS', pid=parent, name=node.name, role=node.getRoleName(),
                  actions=names, activated=names[press[0]], realAtSpi=True)
    Path(os.environ['PHA_OBSERVATION_OUTPUT'], 'a11y.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
