#!/usr/bin/env python3
"""Native shared field facts and context preparation. Assigned guest only."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified guest')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        for part in ('config/settings/plugins', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        shutil.copytree(args.plugins / 'catwalk', case / 'config/plugins/catwalk')
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/catwalk.json'
        runner.write_json(shared, dict(minimumThreshold=20, hideBackground=True, opaque=dict(keep=True)))
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-shared-native.qml'
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        text = runner.run_fixture(profile, install, case, out, fixture)
        if 'PLUGIN_SETTINGS_SHARED_NATIVE: PASS' not in text or any(item in text for item in bad):
            raise RuntimeError('native field/runtime endpoint or diagnostics')
        if json.loads(shared.read_text()) != dict(hideBackground=True, opaque=dict(keep=True)):
            raise RuntimeError('native Reset touched unrelated or opaque fields')
        runtime = Path(text.split('Saving logs to "', 1)[1].split('/quickshell/', 1)[0])
        universes = list((runtime / 'quickshell/vfs').iterdir())
        if len(universes) != 1 or not runtime.is_relative_to(profile.runtime_base):
            raise RuntimeError('actual native lint universe missing or outside the task')
        targets = [install / 'Services/Plugins' / name for name in ('Service.qml', 'PluginInstanceApi.qml', 'PluginSettingsFields.qml')]
        lint = subprocess.run(['bash', str(install / 'Scripts/dev/qmllint.sh'), *map(str, targets)], cwd=install,
            env=dict(os.environ, QS_VFS=str(universes[0])), capture_output=True, text=True, timeout=180)
        (out / 'modules-lint.log').write_text(lint.stdout + lint.stderr)
        if lint.returncode != 0:
            raise RuntimeError('native-universe module lint')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(PHA_SHARED_NATIVE_COLD='1'))
        if 'PLUGIN_SETTINGS_SHARED_NATIVE: COLD_PASS' not in text or any(item in text for item in bad):
            raise RuntimeError('separate cold runtime consumer')
        runner.write_json(out / 'result.json', dict(status='PASS', nativeSharedCapture=True, stageDiscardApply=True,
            independentReadback=True, separateColdConsumer=True, stableRuntimeContext=True, pageAdoption=False))
        if install.is_symlink() or install.resolve() != install or not install.is_relative_to(case):
            raise RuntimeError('owned install cleanup identity')
        shutil.rmtree(install)
        runner.write_json(out / 'install-cleanup.json', dict(removed=[str(install)], retained='receipts and isolated configuration'))
        print('PLUGIN_SETTINGS_SHARED_NATIVE: PASS (native adapter and runtime context; no page adoption claim)')


if __name__ == '__main__':
    main()
