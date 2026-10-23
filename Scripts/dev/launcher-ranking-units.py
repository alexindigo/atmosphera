#!/usr/bin/env python3
"""Guest-only QML ranking + real DesktopEntries disk-refresh consumer tests.

Run via the launcher's pinned tools/guest connector, with a fresh --label.
The source is copied to a private isolated QML tree; no console shell/input
or installed entries are changed. Every temporary/profile path is on disk.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path('/home/tester/Projects/atmosphera-launcher')
# L0's task-local route adaptation, shared with tools/shell-gate. Never import
# the unrelated file chooser VM route from this source tree.
sys.path.insert(0, str(ROOT / 'tools'))
from filechooser_isolation import enter, guest, profile_env

PREFIX = 'LAUNCHER_RANKING|'
ERRORS = re.compile(r'ReferenceError|TypeError|SyntaxError|Cannot assign|Unable to assign|Binding loop|Failed to load configuration|is not a type|module .* is not installed|Failed to start IPC|Error:')


def desktop(name, executable, keywords='', extra=''):
    return ('[Desktop Entry]\nType=Application\nName=' + name + '\nExec=' + executable
            + '\nKeywords=' + keywords + '\nCategories=Utility;\n' + extra)


def main():
    enter(runtime_seconds=90)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    guest()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*', args.label)
    runtime, output = ROOT / 'runtime' / args.label, ROOT / 'evidence' / args.label
    assert not runtime.exists() and not output.exists(), 'single-use labels'
    output.mkdir()
    profile, tree = runtime / 'profile', runtime / 'tree'
    for part in ('home', 'config', 'cache', 'state', 'data/applications', 'empty', 'tmp'):
        (profile / part).mkdir(parents=True)
    settings = json.loads((source / 'Configs/defaults.json').read_text())
    settings['appLauncher']['pinnedApps'] = ['launcher-unit-alpha']
    (profile / 'config/settings.json').write_text(json.dumps(settings))
    shutil.copytree(source, tree, symlinks=True)
    # As in filechooser-units.py, load the fixture directly at the shell root
    # so Quickshell resolves its qs.* imports through the config VFS.
    (tree / 'shell.qml').write_text((source / 'Scripts/dev/fixtures/launcher-ranking.qml').read_text().replace('"../../../Modules/', '"Modules/'))
    applications = profile / 'data/applications'
    (applications / 'launcher-unit-alpha.desktop').write_text(desktop('Source Alpha', '/usr/bin/oldexec'))
    (applications / 'launcher-unit-beta.desktop').write_text(desktop('Source Beta', '/usr/bin/beta', 'browser;'))
    (applications / 'launcher-unit-other.desktop').write_text(desktop('Source Other', '/usr/bin/other'))
    mutator = runtime / 'mutate.py'
    updates = {
        'launcher-unit-alpha.desktop': desktop('Source Zeta', '/usr/bin/newexec', 'browser;', 'Comment=newdescription\nGenericName=newgeneric\nCategories=Graphics;\n'),
        'launcher-unit-beta.desktop': desktop('Source Beta', '/usr/bin/beta'),
    }
    mutator.write_text('from pathlib import Path\nbase = Path(' + repr(str(applications)) + ')\n'
                       + 'updates = ' + repr(updates) + '\n'
                       + 'for name, text in updates.items():\n    staged = base / (name + ".pending")\n    staged.write_text(text)\n    staged.replace(base / name)\n')
    env = dict(profile_env(profile), XDG_DATA_DIRS=str(profile / 'empty'),
               QT_FORCE_STDERR_LOGGING='1', ATMOSPHERA_DEBUG='0', LAUNCHER_UNIT_MUTATOR=str(mutator))
    process = subprocess.run(['timeout', '--kill-after=5', '30', 'qs', '-p', str(tree / 'shell.qml')],
                             cwd=tree, env=env, capture_output=True, text=True, timeout=40)
    log = process.stdout + process.stderr
    (output / 'run.log').write_text(log)
    cases = [json.loads(line.split(PREFIX, 1)[1]) for line in log.splitlines() if PREFIX in line]
    required = {f'matrix.{field}.{quality}' for field in range(5) for quality in range(5)}
    required.update({'source.opens-all', 'source.keyword-only', 'source.disk-visible-name', 'source.disk-keywords',
                     'source.disk-executable', 'source.disk-comment', 'source.disk-generic', 'source.disk-category',
                     'query-ties', 'empty-ties', 'beyond-twenty', 'pins-not-membership', 'merge-providers'})
    failures = [row for row in cases if not row['pass']]
    missing = sorted(required - {row['test'] for row in cases})
    errors = [line for line in log.splitlines() if ERRORS.search(line)]
    duplicate = len({row['test'] for row in cases}) != len(cases)
    passed = process.returncode == 0 and 'LAUNCHER_RANKING_DONE' in log and not failures and not missing and not errors and not duplicate
    files = ['Modules/Panels/Launcher/Helpers/ApplicationRanking.js', 'Modules/Panels/Launcher/Helpers/LauncherResults.js',
             'Modules/Panels/Launcher/Providers/ApplicationsProvider.qml', 'Scripts/dev/fixtures/launcher-ranking.qml',
             'Scripts/dev/launcher-ranking-units.py']
    receipt = dict(passed=passed, exit=process.returncode, source=str(source), runtime=str(runtime), cases=cases, failures=failures,
                   missing=missing, errors=errors, duplicate=duplicate,
                   source_sha256={name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files})
    (output / 'result.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps({key: value for key, value in receipt.items() if key not in ('cases', 'source_sha256')}, indent=2))
    print('LAUNCHER_RANKING_UNITS:', 'PASS' if passed else 'FAIL', f'({len(cases)} cases)')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
