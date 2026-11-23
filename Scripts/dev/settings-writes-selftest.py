#!/usr/bin/env python3
"""Hit/non-hit/control-flow fixtures for the settings provenance checker."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('settings_writes',Path(__file__).with_name('check-settings-writes.py'))
module=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=module
spec.loader.exec_module(module)
metadata=json.loads((ROOT/'Configs/settings-schema.json').read_text())
cases=json.loads((ROOT/'Scripts/dev/fixtures/settings-writes/cases.json').read_text())
failed=[]
for case in cases:
    checker=module.Checker(metadata)
    checker.check('case.js' if 'js' in case else 'case.qml',case.get('qml',case.get('js')))
    errors={i['line'] for i in checker.issues if i['level']=='error'}
    advisory=any(i['level']=='advisory' for i in checker.issues)
    # One broken parse can produce several recovery nodes: rejection is the
    # contract, not an implementation-specific count of parser recovery nodes.
    count=min(1,len(errors)) if case['name']=='parse failure closed' else len(errors)
    codes={issue['code'] for issue in checker.issues}
    if (count!=case['errors'] or ('advisory' in case and case['advisory'] != advisory)
            or not set(case.get('codes',[])).issubset(codes)
            or any(checker.counts[key] < minimum for key, minimum in case.get('counts',{}).items())):
        failed.append({'name':case['name'],'expected':case['errors'],'actual':count,'issues':checker.issues})
# Syntax can be reused; the lexical values it resolves must never be reused.
checker=module.Checker(metadata)
checker.check('facts.qml', 'Item { function outer() { var rows; function capture(arg) { consume(rows, arg); } } }')
definition=next(d for d in checker.definitions.values()
                if checker.text(module.child(d.node,'name')) == 'capture')
callable_=module.Ref((), 'callable', definition.node.id)
state=module.State(env={'rows':module.Ref(('bar','widgets','left'),'detached',101)},
                   owner=definition.owner)
first=checker.capture_tokens(callable_,state)
state.env['rows']=module.Ref(('bar','widgets','right'),'detached',202)
second=checker.capture_tokens(callable_,state)
if first != {101} or second != {202}:
    raise RuntimeError('syntax capture facts retained a mutable lexical value')
if not isinstance(checker.parameters(definition.node),tuple):
    raise RuntimeError('parameter syntax facts are not immutable')
before=checker.signature(state)
state.env['rows']=None
if checker.signature(state) == before:
    raise RuntimeError('state signature retained a mutable environment')
state.scopes.append(({'rows':(True,None,False,None)},set()))
before=checker.signature(state)
state.scopes[0][1].add('later')
if checker.signature(state) == before:
    raise RuntimeError('state signature retained a mutable scope frame')
checker.check('next.qml', 'Item { property var rows: Settings.data.bar.widgets.left; function change() { rows.push({id:"red"}); } }')
if not any(i['file']=='next.qml' and i['code']=='detached-write-without-assignment-back'
           and i['level']=='error' for i in checker.issues):
    raise RuntimeError('per-file syntax facts suppressed a later detached write')
if failed:
    print(json.dumps(failed,indent=2)); raise SystemExit(1)
print(f'SETTINGS_WRITES_SELFTEST: PASS ({len(cases)} hit/non-hit/flow fixtures)')
