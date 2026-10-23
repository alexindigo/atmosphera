#!/usr/bin/env python3
"""Real AtmoColor/editor persistence checks in the isolated project VM runner."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from filechooser_isolation import ROOT, enter, guest, profile_env


def main():
    enter()
    guest()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*', args.label)
    runtime, evidence = ROOT / 'runtime' / args.label, ROOT / 'evidence' / args.label
    assert not runtime.exists() and not evidence.exists()
    evidence.mkdir()
    runtime.mkdir()
    try:
        shell, profile = runtime / 'shell', runtime / 'profile'
        shutil.copytree(source, shell, symlinks=True)
        probe = shell / 'standout-test.qml'
        probe.write_text((source / 'Scripts/dev/fixtures/theming-standout.qml').read_text())
        for name in ('config', 'cache', 'state', 'data', 'tmp'):
            (profile / name).mkdir(parents=True)
        defaults = json.loads((source / 'Configs/defaults.json').read_text())
        defaults['general']['showChangelogOnStartup'] = False
        (profile / 'config/settings.json').write_text(json.dumps(defaults))
        result = subprocess.run(['timeout', '--kill-after=5', '50', 'qs', '-p', str(probe)],
                                cwd=shell, env=profile_env(profile), capture_output=True, text=True, timeout=60)
        log = result.stdout + result.stderr
        (evidence / 'run.log').write_text(log)
        rows = [json.loads(line.split('STANDOUT_UNIT|', 1)[1]) for line in log.splitlines() if 'STANDOUT_UNIT|' in line]
        errors = [line for line in log.splitlines() if re.search(r'TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|is not a type|Unable to assign', line)]
        complete = 'STANDOUT_COMPLETE|' in log
        receipt = dict(exit=result.returncode, cases=rows, errors=errors, complete=complete,
                       passed=result.returncode == 0 and complete and len(rows) >= 11 and all(row['pass'] for row in rows) and not errors)
        saved = profile / 'config/atmosphera/colorschemes/Custom/Custom.json'
        if saved.exists():
            shutil.copy2(saved, evidence / 'Custom.json')
        (evidence / 'result.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt, indent=2))
        return 0 if receipt['passed'] else 1
    finally:
        shutil.rmtree(runtime)


if __name__ == '__main__':
    raise SystemExit(main())
