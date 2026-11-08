#!/usr/bin/env python3
"""Full-tree lint in a disposable container, without starting the shell UI.

Quickshell's scanner owns qs.* module descriptions. A self-terminating import
probe generates them in a private source copy; the ordinary checker owns native
metadata and diagnostic severities. PID 1 owns teardown of any timed-out child.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


class GateError(Exception):
    """A tooling prerequisite or lint contract failed."""


def qs_imports(paths):
    """Collect code imports using the project's string/comment-aware lexer."""
    spec = importlib.util.spec_from_file_location('qml_identifiers', Path(__file__).with_name('qml-identifiers.py'))
    identifiers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(identifiers)
    modules = set()
    for path in paths:
        text = path.read_text()
        _tokens, spans = identifiers.lex(text)
        code = list(text)
        for _kind, start, end in spans:
            code[start:end] = ['\n' if char == '\n' else ' ' for char in text[start:end]]
        modules.update(re.findall(r'(?:^|;)\s*import\s+(qs(?:\.[A-Za-z_]\w*)+)\b', ''.join(code), re.M))
    return sorted(modules)


def run_step(name, command, cwd, env, logs, expected=0, diagnostic=None):
    """Run one bounded child and preserve its output, including failed canaries."""
    path = logs / (name + '.log')
    with path.open('wb') as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            status = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            # This script is the disposable container's PID 1. Returning from
            # main tears down only its private descendants, including the child.
            raise GateError(f'{name}: exceeded 180 seconds') from None
    output = path.read_text(errors='replace')
    if status != expected or (diagnostic and diagnostic not in output):
        print(output, file=sys.stderr)
        raise GateError(f'{name}: exit {status}, expected {expected}'
                        + (f'; required diagnostic: {diagnostic}' if diagnostic else ''))
    print(f'{name}: exit {status} (expected {expected})', flush=True)
    return output


def main():
    """Generate authoritative imports, prove rejection contracts, then lint all QML."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    if os.getpid() != 1:
        parser.error('run as the command of a disposable container (PID 1)')
    source = args.source.resolve()
    work = args.workspace.resolve()
    temporary_roots = (Path('/tmp'), Path('/dev/shm'), Path('/run'), Path('/var/run'))
    if work.is_relative_to(source) or any(work == p or p in work.parents for p in temporary_roots):
        parser.error('workspace must be disk-backed and outside the source tree')
    parent = work.parent
    while not parent.exists():
        parent = parent.parent
    try:
        filesystem = subprocess.check_output(['findmnt', '-n', '-o', 'FSTYPE', '-T', str(parent)],
                                             text=True, timeout=5).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise GateError('could not determine the workspace filesystem') from error
    if filesystem in ('tmpfs', 'ramfs', 'devtmpfs', 'hugetlbfs'):
        parser.error('workspace must be disk-backed and outside the source tree')
    work.mkdir()  # Refuse to overwrite an earlier run.
    shell = work / 'source'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    for name in ('tmp', 'runtime', 'logs', 'canaries', 'home', 'config', 'cache', 'data', 'state'):
        (work / name).mkdir(mode=0o700)
    logs = work / 'logs'
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), XDG_RUNTIME_DIR=str(work / 'runtime'),
               QT_QPA_PLATFORM='offscreen', LANG='C.UTF-8', LC_ALL='C.UTF-8',
               HOME=str(work / 'home'), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_CACHE_HOME=str(work / 'cache'), XDG_DATA_HOME=str(work / 'data'),
               XDG_STATE_HOME=str(work / 'state'))
    # Match Quickshell's scanner: qs imports cause every type in that directory
    # and its relative imports to be scanned, without instantiating those types.
    qml_files = sorted(shell.rglob('*.qml'))
    if not qml_files:
        raise GateError('no QML inputs')
    modules = qs_imports(qml_files)
    imports = shell / 'LintImports.qml'
    with imports.open('x') as output:
        output.write('import QtQuick\n' + ''.join(
            f'import {module} as LintModule{i}\n' for i, module in enumerate(modules))
            + 'QtObject {}\n')
    # The scanner follows imports in all capitalized files in the root folder.
    # Keep them in an unused component: importing them in the running probe
    # would initialize shell singletons, including Wayland-only PanelWindows.
    probe = shell / 'lint-tooling.qml'
    with probe.open('x') as output:
        output.write('import QtQuick\nimport Quickshell\n'
                     'ShellRoot { Timer { interval: 0; running: true; onTriggered: Qt.quit() } }\n')
    (shell / '.qmlls.ini').touch()
    run_step('tooling', ['qs', '-p', str(probe), '--no-color'], shell, env, logs)
    vfs = (shell / '.qmlls.ini').resolve(strict=True).parent
    if not vfs.is_relative_to(work / 'runtime'):
        raise GateError('Quickshell did not generate its tooling configuration')
    for module in modules:
        if not vfs.joinpath(*module.split('.'), 'qmldir').is_file():
            raise GateError(f'Quickshell did not generate {module}')
    probe.unlink()
    imports.unlink()
    env['QS_VFS'] = str(vfs)
    print(f'Quickshell generated {len(modules)} qs modules for {len(qml_files)} QML inputs', flush=True)
    run_step('native-contracts', ['python3', '-B', 'Scripts/dev/qml-native-metadata-selftest.py'], shell, env, logs)
    canaries = work / 'canaries'
    shutil.copyfile(shell / '.qmllint.ini', canaries / '.qmllint.ini')
    checker = str(shell / 'Scripts/dev/qmllint.sh')
    for name, property_name, status in (('valid-composite', 'preferredWidth', 0),
                                        ('invalid-composite', 'preferredWidht', 1)):
        path = canaries / (name + '.qml')
        path.write_text('import qs.Modules.MainScreen\nSmartPanel { ' + property_name + ': 240 }\n')
        run_step(name, ['bash', checker, str(path)], shell, env, logs, expected=status,
                 diagnostic='qmllint: clean' if status == 0 else 'preferredWidht')
    output = run_step('full-tree', ['bash', checker], shell, env, logs, diagnostic='qmllint: clean')
    count = f'Linting {len(qml_files)} QML files...'
    if count not in output:
        raise GateError('full-tree checker did not observe every copied QML input')
    receipt = dict(passed=True, qml_files=len(qml_files), qs_modules=len(modules),
                   native_contracts=True, valid_composite=True, invalid_composite_rejected=True)
    (work / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(count, flush=True)
    print('Full-tree QML lint: clean; native and composite rejection contracts passed', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (GateError, OSError) as error:
        print(f'QML CI: {error}', file=sys.stderr, flush=True)
        sys.exit(1)
