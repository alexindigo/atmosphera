#!/usr/bin/env python3
"""The historical Settings witness must reach Settings, not a missing type."""
import argparse
from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument
from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'baseline', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    source, baseline, work, output = (p.resolve() for p in (args.source, args.baseline, args.work_root, args.output))
    for path in (work, output):
        if not path.is_relative_to(profile.workspace) or path == profile.workspace:
            raise SystemExit('outputs must stay in the assigned workspace')
        path.mkdir(parents=True, exist_ok=False)
    if (baseline/'Commons/SettingsBootstrap.qml').exists():
        raise SystemExit('baseline must predate SettingsBootstrap')
    (work/'config/settings').mkdir(parents=True)
    (work/'config/settings/general.json').write_text('{"lockScreenMode":"old","avatarImage":"/baseline-avatar.png"}')
    (work/'shell').symlink_to(baseline, target_is_directory=True)
    spec = importlib.util.spec_from_file_location('settings_regression', source/'Scripts/dev/settings-regression.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runtime = profile.child_environment('br-')
    env = dict(runner.case_env(runtime, work), PROBE_CASE='observe', PROBE_VALUES='general.avatarImage')
    try:
        with closing(ProbeFiles(baseline, source/'Scripts/dev/fixtures/settings-regression.qml')) as probes:
            child = subprocess.run(['timeout', '--kill-after=5', '8', 'dbus-run-session', '--', 'qs', '-p', str(probes.probe), '--no-color'],
                                   env=env, capture_output=True, text=True, timeout=20)
            text = child.stdout+child.stderr
            (output/'baseline.log').write_text(text)
        failures = []
        if 'SettingsBootstrap is not a type' in text:
            failures.append('fixture stopped on missing SettingsBootstrap type')
        if 'Cannot assign to non-existent property' not in text:
            failures.append('historical Settings unknown-property error not reached')
        result = dict(status='FAIL' if failures else 'PASS', failures=failures, exit=child.returncode,
                      baseline=str(baseline), bootstrapPresent=False)
        (output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps(result), flush=True)
        return int(bool(failures))
    finally:
        shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))


if __name__ == '__main__':
    raise SystemExit(main())
