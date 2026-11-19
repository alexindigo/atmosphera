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
if failed:
    print(json.dumps(failed,indent=2)); raise SystemExit(1)
print(f'SETTINGS_WRITES_SELFTEST: PASS ({len(cases)} hit/non-hit/flow fixtures)')
