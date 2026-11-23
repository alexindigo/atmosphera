#!/usr/bin/env python3
"""Lint every shell and plugin QML file changed from the pinned baselines. Guest only.

Quickshell generates the qs module universe for a private source copy, with the
same import probe as qml-lint-ci.py. The project's qmllint.sh then checks the
changed files in bounded batches: one qmllint process over hundreds of files
exceeds the guest's memory. Every batch runs; any batch that is not clean fails.
"""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

BATCH = 24


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def changed(root, baseline):
    """QML files that are new or differ byte-wise from the baseline tree."""
    found = []
    for path in sorted(root.rglob('*.qml')):
        rel = path.relative_to(root)
        if '.git' in rel.parts or not path.is_file():
            continue
        base = baseline / rel
        if not base.is_file() or base.read_bytes() != path.read_bytes():
            found.append(rel)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'baseline-source', 'baseline-plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh work/output children must belong to the verified guest profile roots')
    profile.prepare_roots()
    ci = load('qml-lint-ci')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        shell_files = changed(args.source, args.baseline_source)
        plugin_files = changed(args.plugins, args.baseline_plugins)
        if not shell_files or not plugin_files:
            raise RuntimeError('changed QML enumeration is empty; check the baseline trees')
        copy = args.work_root / 'source'
        shutil.copytree(args.source, copy, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
        modules = ci.qs_imports(sorted(copy.rglob('*.qml')) + [args.plugins / rel for rel in plugin_files])
        (copy / 'LintImports.qml').write_text('import QtQuick\n' + ''.join(
            'import %s as LintModule%d\n' % (module, index) for index, module in enumerate(modules)) + 'QtObject {}\n')
        probe = copy / 'lint-tooling.qml'
        probe.write_text('import QtQuick\nimport Quickshell\nShellRoot { Timer { interval: 0; running: true; onTriggered: Qt.quit() } }\n')
        (copy / '.qmlls.ini').touch()
        env = dict(os.environ, **profile.child_environment(''))
        env.update(QT_QPA_PLATFORM='offscreen', QML_DISABLE_DISK_CACHE='1')
        try:
            with (args.output / 'tooling.log').open('w') as log, FixtureResources() as resources:
                process = resources.spawn(['qs', '-p', str(probe), '--no-color'], cwd=copy, env=env,
                                          stdout=log, stderr=subprocess.STDOUT)
                code = process.wait(timeout=180)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError('Quickshell tooling probe exceeded its deadline') from error
        vfs = (copy / '.qmlls.ini').resolve(strict=True).parent
        if code != 0 or not vfs.is_relative_to(Path(env['XDG_RUNTIME_DIR'])):
            raise RuntimeError('Quickshell did not generate its tooling configuration; see tooling.log')
        missing = [module for module in modules if not vfs.joinpath(*module.split('.'), 'qmldir').is_file()]
        if missing:
            raise RuntimeError('Quickshell did not generate ' + ', '.join(missing))
        probe.unlink()
        (copy / 'LintImports.qml').unlink()
        env['QS_VFS'] = str(vfs)
        targets = [('shell', copy / rel) for rel in shell_files] + [('plugins', args.plugins / rel) for rel in plugin_files]
        batches, failed = [], []
        for index in range(0, len(targets), BATCH):
            chunk = targets[index:index + BATCH]
            name = 'lint-%03d' % (index // BATCH + 1)
            lint = subprocess.run(['bash', str(copy / 'Scripts/dev/qmllint.sh')] + [str(path) for _side, path in chunk],
                                  cwd=copy, env=env, capture_output=True, text=True, timeout=600)
            (args.output / (name + '.log')).write_text(lint.stdout + lint.stderr)
            clean = lint.returncode == 0 and 'qmllint: clean' in lint.stdout
            files = [(side + '/' + str(path.relative_to(copy if side == 'shell' else args.plugins))) for side, path in chunk]
            batches.append(dict(batch=name, exit=lint.returncode, clean=clean, files=files))
            if not clean:
                failed.append(name)
            print('%s: %s (%d files)' % (name, 'clean' if clean else 'FAILED', len(chunk)), flush=True)
        shutil.rmtree(copy)
        result = dict(status='FAIL' if failed else 'PASS', shellFiles=len(shell_files), pluginFiles=len(plugin_files),
                      qsModules=len(modules), batches=batches, failedBatches=failed)
        (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print('PLUGIN_SETTINGS_CHANGED_LINT: %s (%d shell + %d plugin QML files, %d failed batches)'
              % (result['status'], len(shell_files), len(plugin_files), len(failed)), flush=True)
        if failed:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
