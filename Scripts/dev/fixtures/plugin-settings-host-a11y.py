#!/usr/bin/env python3
"""Observe the exact fixture's AT-SPI actions, with a live press canary."""
import json
import os
from pathlib import Path

import pyatspi


def walk(node):
    yield node
    for child in node:
        if child is not None:
            yield from walk(child)


def actions(node):
    try:
        action = node.queryAction()
        return action, [action.getName(i) for i in range(action.nActions)]
    except NotImplementedError:
        return None, []


def main():
    selected = []
    for app in pyatspi.Registry.getDesktop(0):
        nodes = list(walk(app))
        canary = [node for node in nodes if node.name == 'PHA-input-canary']
        if canary:
            selected.append((app, nodes, canary))
    if len(selected) != 1 or len(selected[0][2]) != 1:
        raise RuntimeError('fixture AT-SPI canary missing or ambiguous')
    app, nodes, canaries = selected[0]
    action, names = actions(canaries[0])
    if action is None or not names or not action.doAction(0):
        raise RuntimeError('live AT-SPI canary press failed')
    labels = ('!!settings.auto-start-breaks!!', '!!settings.auto-start-work!!',
              '!!settings.compact-mode!!', 'Play Alarm Sound')
    result = dict(pid=app.get_process_id(), canaryAction=names[0], controls=[])
    for label in labels:
        matching = [node for node in nodes if node.name == label]
        offered = [name for node in matching for name in actions(node)[1]]
        result['controls'].append(dict(label=label, matchingNodes=len(matching), actions=offered))
        if offered:
            raise RuntimeError('old toggle unexpectedly exposes an activation action')
    Path(os.environ['PHA_A11Y_RESULT']).write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
