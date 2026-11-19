#!/usr/bin/env python3
"""Guest-only pure owner-policy proof, with no session-lock/PAM simulation."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--baseline-policy', type=Path)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    entry = source / '.locker-state-proof.qml'
    if args.baseline_policy:
        baseline = args.baseline_policy.resolve(strict=True)
        assert baseline.is_relative_to(Path('/home/tester/Projects/locker')), 'guest workspace baseline required'
        (work / 'Helpers').mkdir()
        (work / 'Helpers/LockerLifecycle.js').write_text(baseline.read_text())
        entry = work / 'policy.qml'
    created = False
    try:
        with entry.open('x') as output:
            created = True
            fixture = (source / 'Scripts/dev/fixtures/locker-state.qml').read_text()
            original = '"../../../Helpers/LockerLifecycle.js"'
            assert fixture.count(original) == 1
            output.write(fixture.replace(original, '"Helpers/LockerLifecycle.js"'))
        result = subprocess.run(['qs', '-p', str(entry), '--no-color'],
                                env=dict(os.environ, QT_QPA_PLATFORM='offscreen'), timeout=30,
                                text=True, capture_output=True)
        text = result.stdout + result.stderr
        (work / 'qml.txt').write_text(text)
        assert result.returncode == 0, text
        match = re.search(r'LOCKER_STATE_RESULT (\[[^\n]+\])', text)
        assert match, text
        cases = json.loads(match[1])
        assert cases and len(cases) == len(set(cases)), cases
        assert 'ERROR' not in text and 'TypeError' not in text and 'ReferenceError' not in text, text
        (work / 'result.json').write_text(json.dumps(cases, indent=2))
        print('PASS locker-state', len(cases), work)
    finally:
        if created and entry.exists():
            entry.unlink()


if __name__ == '__main__':
    main()
