#!/usr/bin/env python3
"""Full-shell keyboard focus witness for the shared NToggle change. VM only.

Runs each supported Settings presentation with the complete production entry
on the real niri session: the candidate tree, and the same tree with the previous
NToggle.qml. A disposable
observer, appended to a copy of shell.qml, opens Settings, the launcher, the
control center and the lock preview through the shell's own IPC routes and
sends real Wayland keys. Both runs must satisfy every focus assertion and
produce the same focus trace. No protocol lock, Return or PAM attempt.
"""
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
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'is not installed', 'Failed to start IPC server')


def run_variant(args, profile, name, ntoggle, mode):
    case, out = args.work_root / name, args.output / name
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    if ntoggle:
        shutil.copy2(ntoggle, install / 'Widgets/NToggle.qml')
    for part in ('config/settings', 'cache', 'state'):
        (case / part).mkdir(parents=True)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62, general=dict(showChangelogOnStartup=False),
                                                         ui=dict(settingsPanelMode=mode), location=dict(weatherEnabled=False)))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    # Seed the real weather cache so eager hidden lock-preview bindings do not
    # dereference an absent backend. No network/weather outcome is under test.
    runner.write_json(case / 'cache/location.json', dict(latitude='', longitude='', weatherLastFetch=0,
        weather=dict(current_weather=dict(temperature=0, windspeed=0, weathercode=0, is_day=True),
                     current=dict(relativehumidity_2m=0), daily=dict(time=['2026-11-20'] * 4,
                     weathercode=[0] * 4, temperature_2m_max=[0] * 4, temperature_2m_min=[0] * 4))))
    entry = install / 'shell.qml'
    original = entry.read_text()
    needle = '  Loader {\n'
    if original.count(needle) != 1 or not original.endswith('}\n'):
        raise RuntimeError('production entry changed; review observer insertion')
    shutil.copy2(args.source / 'Scripts/dev/fixtures/PhaFocusObserver.qml', install / 'PhaFocusObserver.qml')
    observed = original.replace(needle, needle + '    id: coldSession\n', 1)
    observed = observed[:-2] + '  PhaFocusObserver {\n    sessionReady: bootstrap.ready && coldSession.status === Loader.Ready && !!coldSession.item\n  }\n}\n'
    entry.write_text(observed)
    error = None
    try:
        text = runner.run_fixture(profile, install, case, out, entry, installed=True,
                                  extra_env=dict(PHA_ENTRY=str(entry), PHA_SETTINGS_MODE=mode), timeout=180)
    except RuntimeError as failure:
        error = str(failure)
        text = (out / 'runtime.log').read_text()
    lines = [line.split('FOCUS_RESULT ', 1)[1] for line in text.splitlines() if 'FOCUS_RESULT ' in line]
    trace = json.loads(lines[0]) if len(lines) == 1 else None
    diagnostics = [line.strip()[:300] for line in text.splitlines() if any(marker in line for marker in BAD) or 'FOCUS_ASSERT' in line]
    result = dict(variant=name, status='PASS' if trace is not None and error is None else 'FAIL',
                  trace=trace, fixtureError=error, diagnostics=diagnostics,
                  ntoggleSha256=hashlib.sha256((install / 'Widgets/NToggle.qml').read_bytes()).hexdigest(),
                  originalEntrySha256=hashlib.sha256(original.encode()).hexdigest())
    runner.write_json(out / 'result.json', result)
    print('FOCUS %s: %s' % (name, result['status']), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output', 'baseline-ntoggle'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='accepted for run-driver compatibility; unused')
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
        modes = {}
        for mode in ('attached', 'centered', 'window'):
            candidate = run_variant(args, profile, mode + '-candidate', None, mode)
            baseline = run_variant(args, profile, mode + '-baseline-ntoggle', args.baseline_ntoggle, mode)
            same = candidate['trace'] is not None and candidate['trace'] == baseline['trace']
            new_diagnostics = sorted(set(candidate['diagnostics']) - set(baseline['diagnostics']))
            modes[mode] = dict(status='PASS' if candidate['status'] == baseline['status'] == 'PASS' and same and not new_diagnostics else 'FAIL',
                               sameTrace=same, newDiagnostics=new_diagnostics,
                               inheritedDiagnostics=sorted(set(baseline['diagnostics'])))
        status = 'PASS' if all(row['status'] == 'PASS' for row in modes.values()) else 'FAIL'
        runner.write_json(args.output / 'result.json', dict(status=status, modes=modes,
                            witness='full production entry, all three Settings presentations, shell IPC routes, real Wayland keys; baseline diagnostics retained'))
        print('CASE focus: %s %s' % (status, json.dumps(modes)), flush=True)
        if status != 'PASS':
            raise SystemExit(1)
        runner.remove_completed_installs(args.work_root, args.output)


if __name__ == '__main__':
    main()
