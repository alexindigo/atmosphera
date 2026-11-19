#!/usr/bin/env python3
"""Exercise relative-output delivery and an absent-credential false positive."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=('relative', 'missing', 'all'), default='all')
    args = parser.parse_args()
    plugins, output = args.plugins.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    runner = ROOT / 'Scripts/dev/plugin-credential-flags-regression.py'
    if args.case in ('relative', 'all'):
        result = subprocess.run([sys.executable, '-B', str(runner), '--plugins', str(plugins), '--output', 'relative'],
                                cwd=output, capture_output=True, text=True, timeout=180)
        (output / 'relative.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0 and 'CREDENTIAL_FLAGS: PASS 10' in result.stdout, result.stderr
        assert json.loads((output / 'relative/result.json').read_text())['status'] == 'PASS'
    if args.case in ('missing', 'all'):
        code = '''import sys
from pathlib import Path
filename=sys.argv[1]
source=Path(filename).read_text()
needle='raw = {field: canary, portable: defaults[portable]}'
assert source.count(needle)==1
source=source.replace(needle,'raw = {portable: defaults[portable]}')
sys.argv=[filename,*sys.argv[2:]]
exec(compile(source,filename,'exec'),{'__file__':filename,'__name__':'__main__'})
'''
        result = subprocess.run([sys.executable, '-B', '-c', code, str(runner), '--plugins', str(plugins), '--output', str(output / 'missing')],
                                cwd=output, capture_output=True, text=True, timeout=180)
        (output / 'missing.log').write_text(result.stdout + result.stderr)
        assert result.returncode != 0 and 'CREDENTIAL_ASSERT: canary not loaded' in result.stderr, 'absent credential falsely accepted: ' + result.stdout + result.stderr
        assert not list((output / 'missing').glob('*/profile.json')), 'rejected source must not export'
    print('CREDENTIAL_ORACLES: PASS ' + args.case)


if __name__ == '__main__':
    main()
