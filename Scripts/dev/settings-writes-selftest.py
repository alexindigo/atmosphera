#!/usr/bin/env python3
"""Hit/non-hit/control-flow fixtures for the settings provenance checker."""
import importlib.util
from dataclasses import FrozenInstanceError
import json
from pathlib import Path
import sys
import time
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('settings_writes',Path(__file__).with_name('check-settings-writes.py'))
module=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=module
spec.loader.exec_module(module)
metadata=json.loads((ROOT/'Configs/settings-schema.json').read_text())
cases=json.loads((ROOT/'Scripts/dev/fixtures/settings-writes/cases.json').read_text())
# Three post-fix VM runs including 20,000 deep-scope signature/hash probes:
# 0.099/0.104/0.099s. Eight times the maximum is 0.832s, rounded up to 1s
# for slower CI CPUs and scheduling noise. This is a fixed regression budget,
# independent of the full scanner's unchanged 300-second deadline.
FIXTURE_BUDGET_SECONDS=1.0
started=time.perf_counter()
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
state.scopes.append((module.SavedBindings((('rows',(True,None,False,None)),)),set()))
before=checker.signature(state)
state.scopes[0][1].add('later')
if checker.signature(state) == before:
    raise RuntimeError('state signature retained a mutable scope frame')
checker.check('next.qml', 'Item { property var rows: Settings.data.bar.widgets.left; function change() { rows.push({id:"red"}); } }')
if not any(i['file']=='next.qml' and i['code']=='detached-write-without-assignment-back'
           and i['level']=='error' for i in checker.issues):
    raise RuntimeError('per-file syntax facts suppressed a later detached write')

reference=module.Ref(('bar','widgets','left'),'detached',303)
bindings={'rows':(True,reference,True,(False,True)), 'outer':(False,None,False,None)}
entries=list(bindings.items())
frame=module.SavedBindings(entries)
original_key=frame.key
entries.clear(); bindings['rows']=(True,None,False,None)
if dict(frame.entries)['rows'][1] != reference or frame.key is not original_key:
    raise RuntimeError('saved bindings retained a mutable constructor input')
if module.SavedBindings(tuple(reversed(frame.entries))).key != original_key:
    raise RuntimeError('saved binding keys depend on restore order')
try:
    frame.entries=()
except FrozenInstanceError:
    pass
else:
    raise RuntimeError('saved bindings can be mutated after construction')
for invalid in ((True,reference,True,[False,True]),
                (True,module.Ref(['bar'],'detached',303),False,None)):
    try:
        module.SavedBindings((('rows',invalid),))
    except TypeError:
        pass
    else:
        raise RuntimeError('saved bindings admitted a nested mutable value')
state=module.State(env={'rows':reference},scalars={'rows':(False,True)},
                   locals={'outer'},scopes=[(frame,{'outer'})],contained={303:{('child',):{404}}})
forked=state.fork()
if forked.scopes[0][0] is not frame:
    raise RuntimeError('fork did not reuse its immutable binding snapshot')
before=checker.signature(state)
forked.scopes[0][1].add('branch-only'); forked.locals.add('local-only')
forked.env['rows']=None; forked.scalars['rows']=(True,False)
forked.contained[303][('child',)].clear()
if checker.signature(state) != before or 'branch-only' in state.scopes[0][1]:
    raise RuntimeError('fork leaked mutable proof state into its peer')
if checker.signature(forked) == before:
    raise RuntimeError('fork mutation reused a stale signature')
if checker.signature(state)[-1][0][0] is not original_key:
    raise RuntimeError('signature rebuilt the immutable saved binding key')
mutations={
    'environment':lambda row:row.env.update(rows=reference),
    'dirty':lambda row:row.dirty.update({303:definition.node}),
    'control':lambda row:setattr(row,'control','return'),
    'escaped':lambda row:row.escaped.add(303),
    'locals':lambda row:row.locals.add('later'),
    'scalars':lambda row:row.scalars.update(rows=(True,False)),
    'owner':lambda row:setattr(row,'owner',1),
    'receiver':lambda row:setattr(row,'this_owner',1),
    'contained':lambda row:row.contained[303][('child',)].add(505),
    'saved locals':lambda row:row.scopes[0][1].add('later'),
}
for label,mutate in mutations.items():
    row=module.State(scopes=[(frame,set())],contained={303:{('child',):{404}}})
    before=checker.signature(row); mutate(row)
    if checker.signature(row) == before:
        raise RuntimeError('signature retained mutable '+label)
# Proof equality is map equality, not iteration order. Build every mutable
# signature afresh without repeatedly sorting those same unordered entries.
ordered=module.State(env={'z':reference,'a':None}, dirty={303:definition.node},
                     scalars={'z':(False,True),'a':(None,None)},
                     contained={303:{('z',):{404},('a',):{505}}},scopes=[(frame,{'outer'})])
reordered=ordered.fork()
reordered.env=dict(reversed(list(ordered.env.items())))
reordered.scalars=dict(reversed(list(ordered.scalars.items())))
reordered.contained[303]=dict(reversed(list(ordered.contained[303].items())))
with patch('builtins.sorted',side_effect=RuntimeError('signature rebuilt an unnecessary ordering')):
    if checker.signature(ordered) != checker.signature(reordered):
        raise RuntimeError('signature depends on map insertion order')
changed=module.SavedBindings((('rows',(True,module.Ref(reference.path,'detached',404),True,(True,False))),))
other=module.State(scopes=[(changed,{'other'})])
joined,_=checker.join_sequence((state,[]),(other,[]))
joined_frame,joined_locals=joined.scopes[0]
value=dict(joined_frame.entries)['rows']
if (joined_frame is frame or joined_frame is changed or value[1].mode != 'unknown'
        or value[3] != (None,None) or joined_locals != {'outer','other'}):
    raise RuntimeError('join did not construct the conservative immutable frame')
joined_locals.add('joined-only')
if frame.key is not original_key or 'joined-only' in state.scopes[0][1] or 'joined-only' in other.scopes[0][1]:
    raise RuntimeError('join mutated an incoming saved frame')
same_join,_=checker.join_sequence((state,[]),(state,[]))
if same_join.scopes[0][0] is frame or same_join.scopes[0][0].key != original_key:
    raise RuntimeError('equal-input join must still construct a new immutable frame')
checker.check('restore.qml','Item { function restore() { let rows=1; { let rows=2; if (flag) { let rows=3; } } } }')
definition=next(d for d in checker.definitions.values()
                if checker.text(module.child(d.node,'name')) == 'restore')
state=module.State(env={'rows':reference},scalars={'rows':(False,True)},locals={'outer'})
restored=checker.block(module.child(definition.node,'body'),[state])
if not restored or any(row.env.get('rows') != reference or row.scalars.get('rows') != (False,True)
                       or row.scopes or row.locals != {'outer'} for row in restored):
    raise RuntimeError('nested branch scope exit failed to restore captured bindings')
# A fixed nested-scope workload exercises repeated signature construction, not
# just parser startup. Keep this alongside the hit/non-hit fixture timing.
stress='Item { function stress(a,b,c,d) { '+''.join('{ let scope'+str(i)+'=0; ' for i in range(8))
stress+='sink(a?1:0,b?1:0,c?1:0,d?1:0); '*12 + '}'*8+'} }'
checker.check('scope-stress.qml',stress)
if any(issue['file']=='scope-stress.qml' and issue['level']=='error' for issue in checker.issues):
    raise RuntimeError('nested-scope stress fixture produced an unexpected error')
# Mirror the residual profile's repeated deep saved-scope keys at a small,
# deterministic scale. Hash real fresh signatures, not just stored key objects.
saved_entries=tuple(('local'+str(i),(True,reference,True,(False,True))) for i in range(64))
stress_state=module.State(scopes=[(module.SavedBindings(saved_entries),{'outer'}) for _ in range(24)])
for i in range(20000):
    stress_state.control='return' if i%2 else ''
    signature=checker.signature(stress_state)
    if signature[2] != stress_state.control:
        raise RuntimeError('scope timing fixture reused mutable control state')
    hash(signature)
if failed:
    print(json.dumps(failed,indent=2)); raise SystemExit(1)
elapsed=time.perf_counter()-started
print(f'SETTINGS_WRITES_FIXTURE_TIME: {elapsed:.3f}s / {FIXTURE_BUDGET_SECONDS:.3f}s '
      f'({len(cases)} cases, scope isolation and nested-scope stress)',flush=True)
if elapsed > FIXTURE_BUDGET_SECONDS:
    raise SystemExit('SETTINGS_WRITES_SELFTEST: FAIL (fixture timing budget exceeded)')
print(f'SETTINGS_WRITES_SELFTEST: PASS ({len(cases)} hit/non-hit/flow fixtures)')
