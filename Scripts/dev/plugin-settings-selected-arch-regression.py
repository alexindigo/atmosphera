#!/usr/bin/env python3
"""P055 selected Arch Updater check client at the actual Desktop list, VM only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

UPDATE_ENDPOINT = '''#!/usr/bin/env python3
import os, sys, time
from pathlib import Path

mode, label = sys.argv[1:]
out = Path(os.environ['PHA_ARCH_EFFECT'])
pid_file = out / (label + '.started')
release = out / (label + '.release')

def identity(pid):
    stat = Path(f'/proc/{pid}/stat').read_text().rsplit(') ', 1)[1].split()
    return stat[0], stat[19]

if mode == 'release':
    pid, started = pid_file.read_text().split()
    try:
        state, current = identity(pid)
    except FileNotFoundError:
        sys.exit(7)
    if state == 'Z' or current != started:
        sys.exit(7)
    release.touch()
else:
    if mode != 'hold' or label not in ('selected', 'retired'):
        sys.exit('unexpected update command')
    pending = pid_file.with_suffix('.pending')
    with pending.open('x') as receipt:
        receipt.write(f'{os.getpid()} {identity(os.getpid())[1]}\\n')
    pending.rename(pid_file)
    deadline = time.monotonic() + 40
    while not release.exists():
        if time.monotonic() >= deadline:
            sys.exit('update endpoint was not released')
        time.sleep(.02)
    code = 0 if label == 'selected' else 23
    (out / (label + '.finished')).write_text(str(code))
    sys.exit(code)
'''


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
            parser.error('fresh roots must belong to the verified profile')
    injector = Path(os.environ['PHA_INPUT_INJECTOR']).resolve()
    if not injector.is_relative_to(profile.work_base) or not injector.is_file():
        parser.error('task-owned input injector required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'cache', 'state', 'bin'):
            (case / part).mkdir(parents=True)
        plugin = case / 'config/plugins/arch-updater'
        shutil.copytree(args.plugins / 'arch-updater', plugin, ignore=shutil.ignore_patterns('*.bak'))
        calls = out / 'calls.jsonl'
        check = case / 'bin/pha-check'
        # Inert read-only check endpoint; never a package manager.
        check.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                         'from pathlib import Path\n'
                         'label = sys.argv[1]\n'
                         'if label == "beta" and (Path(os.environ["PHA_ARCH_EFFECT"]) / "selected.finished").exists(): label = "beta-after-update"\n'
                         'with open(os.environ["PHA_CALLS"], "a") as f: f.write(json.dumps([label]) + "\\n")\n'
                         'if label != "none": print(label + "-pkg 1.0 -> 2.0")\n')
        check.chmod(0o700)
        update = case / 'bin/pha-update'
        update.write_text(UPDATE_ENDPOINT)
        update.chmod(0o700)
        effects = out / 'effects'
        effects.mkdir()
        env = dict(PATH=str(case / 'bin') + os.pathsep + os.environ['PATH'], PHA_CALLS=str(calls),
                   PHA_ARCH_CHECK=str(check), PHA_ARCH_UPDATE=str(update), PHA_ARCH_EFFECT=str(effects))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/arch-updater.json'
        runner.write_json(shared, dict(systemCmd=str(check) + ' alpha', aurCmd=str(check) + ' none', updateCmd='false',
                                       flatpak=False, toast=False, opaque=dict(keep=True)))
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-selected-arch.qml'
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env,
                extra_lint=tuple(plugin / name for name in ('Main.qml', 'ArchUpdaterSettingsClient.qml', 'ArchUpdaterQueryWorker.qml')))
        finally:
            (case / 'config/settings').chmod(0o700)
        if 'ARCH_SELECTED: PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('actual Arch Settings/check/Desktop endpoint failed')
        rows = json.loads((case / 'config/settings/desktopWidgets.json').read_text())['monitorWidgets'][0]['widgets']
        if rows != [dict(id='plugin:arch-updater', instanceSettings=dict(systemCmd=str(check) + ' beta', updateCmd=f'exec {update} hold selected')),
                    dict(id='plugin:arch-updater', instanceSettings=dict(systemCmd=str(check) + ' other', updateCmd=f'exec {update} hold retired'))] or shared.read_bytes() != before:
            raise RuntimeError('independent selected/sibling/shared persisted readback failed')
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        if ['beta'] not in recorded:
            raise RuntimeError('selected inert check endpoint was not observed')
        if {p.name: p.read_text() for p in effects.glob('*.finished')} != {'selected.finished': '0', 'retired.finished': '23'}:
            raise RuntimeError('inert update completion receipts differ')
        if (text.count('Update command exited with status 23') != 1 or text.count('Update command exited with status 0') != 1
                or recorded.count(['beta-after-update']) != 1 or recorded.count(['other']) != 1):
            raise RuntimeError('update completion report or originating refresh missing')
        cold = out / 'cold'
        cold.mkdir()
        text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_ARCH_COLD='1', PHA_ARCH_EFFECT=str(cold)))
        if 'ARCH_SELECTED: COLD_PASS' not in text or any(marker in text for marker in bad):
            raise RuntimeError('separate cold Arch Desktop result failed')
        inputs = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((args.plugins / 'arch-updater').glob('*.qml'))}
        runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, actualSettingsAndDesktop=True,
            inertCheckEndpoint=True, oneClientPerContext=True, genuineKeyboardCommand=True, discardDoesNotPublish=True,
            realIoFailureRetry=True, failedPersistenceNoRefresh=True, refreshOnlyAfterCurrentSuccess=True,
            sharedAndSiblingUnchanged=True, independentPersistedReadback=True, separateColdConsumer=True,
            ownerRetiresClients=True, updateSurvivesReplacementAndRetirement=True, completionRefreshesLiveOrigin=True,
            noPackageManagerMutation=True, completeCatalog=False))
        runner.remove_completed_installs(case, out)
        print('ARCH_SELECTED: PASS', flush=True)


if __name__ == '__main__':
    main()
