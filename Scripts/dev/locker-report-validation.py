#!/usr/bin/env python3
"""Guest-only report validation tests. Synthetic records are not PAM evidence."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    spec = importlib.util.spec_from_file_location('locker_report_adapter', source / 'Scripts/python/locker-unit.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    root = work / 'reports'
    root.mkdir(mode=0o700)
    module.runtime_root = lambda: root
    data = {'session': 'proof-session', 'generation': 'proof-generation', 'authRole': None}
    identity = module.proc_identity(os.getpid())
    info = module.prepare_report('proof')
    path = Path(info['path'])
    original = {'reportInfo': info, 'clientIdentity': identity,
        'identity': {'InvocationID': 'proof-invocation'}, 'client': {'secure': True, 'ready': True}}
    record = copy.deepcopy(original)
    report = dict(schema=1, session=data['session'], generation=data['generation'], role='emergency',
        invocation='proof-invocation', identity=identity, token=info['token'],
        sequence=1, event='locked', everSecure=True)
    results = []

    def check(name, expected):
        module.refresh_report(data, 'emergency', record)
        assert record['protocolOutcome'] == expected, (name, record)
        results.append(name)

    check('empty-is-unknown', 'unknown')
    assert not record['client']['secure']
    record['client'].update(terminal=True, authenticated=True, settlement='authenticated-unlock')
    check('async-terminal-without-native-report-is-unknown', 'unknown')
    assert not record['client']['terminal'] and not record['client']['authenticated']
    for value in ([1], [1, 2], 'text', 1, True, None, []):
        record = copy.deepcopy(original)
        path.write_text(json.dumps(value))
        check('reject-non-object-' + type(value).__name__ + repr(value), 'unknown')
        assert not record['client']['secure'] and record.get('reportError')
    for field, value in (('generation', 'stale-generation'), ('session', 'other-session'),
            ('role', 'real'), ('invocation', 'old-invocation'), ('identity', {'pid': identity['pid'], 'start': 'old'}),
            ('token', 'wrong-token'), ('sequence', True), ('event', 'synthetic-auth')):
        record = copy.deepcopy(original)
        path.write_text(json.dumps(dict(report, **{field: value})))
        check('reject-' + field, 'unknown')
        assert not record['client']['secure'] and record.get('reportError')
    path.write_text(json.dumps(report))
    path.chmod(0o644)
    record = copy.deepcopy(original)
    check('reject-public-mode', 'unknown')
    path.chmod(0o600)
    target = root / 'untrusted-target'
    target.write_text(json.dumps(report))
    target.chmod(0o600)  # otherwise valid: only the symlink itself may be refused
    path.unlink()
    path.symlink_to(target)
    check('reject-symlink', 'unknown')
    path.unlink()
    path.touch(mode=0o600)
    path.write_text(json.dumps(report))
    record = copy.deepcopy(original)
    check('matching-native-lock', 'locked')
    assert record['client']['secure'] and record['everSecure']
    from unittest.mock import patch
    with patch.object(module, 'same_process', return_value=False):
        check('dead-registered-client-is-unknown', 'unknown')
        assert not record['client']['secure'] and record['everSecure']
    record['client']['secure'] = False
    check('async-publication-cannot-erase-lock', 'locked')
    assert record['client']['secure']
    path.write_text(json.dumps(dict(report, sequence=2)))
    check('native-sequence-advances', 'locked')
    path.write_text(json.dumps(dict(report, event='finished')))
    check('older-sequence-cannot-erase-lock', 'locked')
    path.write_text(json.dumps(dict(report, sequence=2, event='finished')))
    check('rewritten-sequence-cannot-erase-lock', 'locked')
    assert 'rewritten' in record['reportError']
    path.write_text(json.dumps(dict(report, sequence=3, event='authenticated-unlock')))
    check('auth-report-needs-private-fence', 'locked')
    assert record['client']['secure'] and not record['client'].get('authenticated')
    data['authRole'] = 'emergency'
    check('matching-authenticated-unlock', 'authenticated-unlock')
    assert record['client']['terminal'] and record['client']['authenticated'] and not record['client']['secure']
    assert not record['client']['ready'], 'terminal report kept handover readiness'
    data['authRole'] = None
    record = copy.deepcopy(original)
    path.write_text(json.dumps(dict(report, event='finished', everSecure=False)))
    check('refusal-is-terminal-never-secure', 'finished')
    assert record['client']['terminal'] and not record['client']['secure'] and not record['client']['authenticated']
    assert not record['client']['ready'], 'terminal refusal kept handover readiness'
    (work / 'result.json').write_text(json.dumps({'checks': results,
        'scope': 'identity/sequence/durability input validation, not synthetic auth acceptance'}, indent=2))
    (work / 'result.txt').write_text('PASS report-validation ' + str(len(results)) + '\n')
    print('PASS report-validation', len(results), work)


if __name__ == '__main__':
    main()
