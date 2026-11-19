#!/usr/bin/env python3
"""Guest-only controls for action regression admission and search routing."""
import importlib.util
import ast
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

from workspace_guard import require_disk_backed_paths


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    root = Path(__file__).resolve().parents[2]
    require_disk_backed_paths(root, os.environ['TMPDIR'])
    if Path.home() != Path('/home/tester'):
        raise SystemExit('run only in the assigned VM')
    failures = []

    def check(name, okay):
        print(f"[{'PASS' if okay else 'FAIL'}] {name}", flush=True)
        if not okay:
            failures.append(name)

    search = load('search_index', root / 'Scripts/dev/build-settings-search-index.py')
    for stem, index in [('BasicsSubTab', 0), ('KeybindsSubTab', 1), ('ShortcutsSubTab', 2), ('HotCornersSubTab', 3)]:
        route = search.resolve_tab_info(root / f'Modules/Panels/Settings/Tabs/General/{stem}.qml', {'GeneralTab': 0}, {'GeneralTab': 'common.general'})
        check('search:' + stem, route[2] == index and route[3] is not None)

    runner = load('action_regression', root / 'Scripts/dev/action-catalog-regression.py')
    nested = root / 'review-selftest-nested-workspace'
    if nested.exists():
        raise RuntimeError('refuse an existing workspace')
    rejected = False
    try:
        with patch.object(sys, 'argv', ['action-catalog-regression.py', '--source', str(root), '--workspace', str(nested)]), patch.object(runner, 'private_env', side_effect=RuntimeError('fixture allocation reached')):
            runner.main()
    except SystemExit as error:
        rejected = error.code == 2
    except RuntimeError as error:
        if str(error) != 'fixture allocation reached':
            raise
    try:
        check('nested-workspace-refused-before-writes', rejected and not nested.exists())
    finally:
        if nested.exists():
            shutil.rmtree(nested)  # This control exclusively created this exact path.

    script = root / 'Scripts/dev/hot-corners-service-regression.py'
    for name, code, text, expected in [('nonzero', 3, 'HOT_CORNERS_SERVICE: PASS', 1),
                                      ('failure-marker', 0, 'HOT_CORNERS_SERVICE: PASS\nHOT_CORNERS_SERVICE: FAIL', 1),
                                      ('qml-error', 0, 'HOT_CORNERS_SERVICE: PASS\nTypeError: broken', 1),
                                      ('positive', 0, 'HOT_CORNERS_SERVICE: PASS', 0)]:
        fixture = ('import runpy,subprocess,sys; from unittest.mock import patch; '
                   f'sys.path.insert(0, {str(script.parent)!r}); '
                   f'result=subprocess.CompletedProcess([], {code}, {text!r}, ""); '
                   'p=patch("subprocess.run",return_value=result); p.start(); '
                   f'runpy.run_path({str(script)!r},run_name="__main__")')
        result = subprocess.run([sys.executable, '-O', '-B', '-c', fixture], capture_output=True, text=True)
        check('optimized-service-oracle:' + name, result.returncode == expected)
    tree = ast.parse((root / 'Scripts/dev/hot-corners-e2e.py').read_text())
    with tempfile.TemporaryDirectory(prefix='action review space ', dir=os.environ['TMPDIR']) as folder:
        work = Path(folder)
        for name, variables in [('commands', {'work': work, 'CORNERS': ['topLeft']}),
                                ('custom', {'fired_log': work / 'fired.log'})]:
            node = next(n for n in ast.walk(tree) if isinstance(n, ast.Assign)
                        and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))
            value = eval(compile(ast.Expression(node.value), '<actual-e2e-expression>', 'eval'),
                         {'str': str, 'shlex': __import__('shlex'), **variables})
            command = value['topLeft'] if name == 'commands' else value
            result = subprocess.run(['bash', '-c', command], capture_output=True, text=True)
            path = work / 'fired.log'
            check('space-path:' + name, result.returncode == 0 and path.exists()
                  and path.read_text().splitlines()[-1] == ('topLeft' if name == 'commands' else 'customBottomLeft'))
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
