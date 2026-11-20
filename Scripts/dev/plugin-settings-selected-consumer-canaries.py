#!/usr/bin/env python3
"""Reject shared-Main config regressions through actual selected consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import importlib.util

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
            parser.error('fresh roots must belong to the verified profile')
    args.work_root.mkdir(exist_ok=False)
    args.output.mkdir(exist_ok=False)
    cases = [
        ('catwalk', 'Main.qml', 'plugin-settings-selected-catwalk-regression.py',
         'current ? settingsContext.settingsView', 'current ? root.pluginApi.pluginSettings',
         'CATWALK_ASSERT: sibling B distinct actual animation/background'),
        ('git-companion', 'GitSettingsClient.qml', 'plugin-settings-selected-git-regression.py',
         'current ? settingsContext.settingsView', 'current ? pluginApi.pluginSettings',
         'GIT_SELECTED_ASSERT: selected query context cannot become shared Main configuration'),
        ('air-quality', 'AirQualitySettingsClient.qml', 'plugin-settings-selected-air-regression.py',
         'current ? settingsContext.settingsView', 'current ? pluginApi.pluginSettings',
         'AIR_SELECTED_ASSERT: selected configuration cannot read shared Main'),
        ('github-contributions', 'ContributionsSettingsClient.qml', 'plugin-settings-selected-contributions-regression.py',
         'current ? settingsContext.settingsView', 'current ? pluginApi.pluginSettings',
         'CONTRIBUTIONS_ASSERT: selected account cannot read shared Main'),
    ]
    results = []
    for plugin, filename, driver, old, replacement, marker in cases:
        case = args.work_root / plugin
        inputs = case / 'plugins'
        inputs.mkdir(parents=True)
        shutil.copytree(args.plugins / plugin, inputs / plugin, ignore=shutil.ignore_patterns('*.bak'))
        target = inputs / plugin / filename
        original = target.read_bytes()
        text = original.decode()
        if text.count(old) != 1:
            raise RuntimeError('review the exact mutation boundary: ' + str(target))
        target.write_text(text.replace(old, replacement))
        out = args.output / plugin
        process = subprocess.run([sys.executable, '-B', str(args.source / 'Scripts/dev' / driver),
            '--guest-profile', str(args.guest_profile), '--source', str(args.source), '--plugins', str(inputs),
            '--work-root', str(case / 'job'), '--output', str(out)], env=os.environ,
            capture_output=True, text=True, timeout=100)
        log = args.output / (plugin + '-driver.log')
        log.write_text(process.stdout + process.stderr)
        runtime = (out / 'runtime.log').read_text() if (out / 'runtime.log').exists() else ''
        if process.returncode == 0 or marker not in runtime or (out / 'runtime.exit').read_text().strip() != '2':
            raise RuntimeError('mutation did not fail at its actual selected consumer: ' + plugin)
        results.append(dict(plugin=plugin, status='REJECTED', assertion=marker,
            originalSha256=hashlib.sha256(original).hexdigest(), mutationSha256=hashlib.sha256(target.read_bytes()).hexdigest()))
        runner.remove_completed_installs(case / 'job', out)
        print('SELECTED_CONSUMER_CANARY ' + plugin + ': REJECTED', flush=True)
    profile.verify()
    (args.output / 'result.json').write_text(json.dumps(dict(status='PASS', cases=results,
        completeCatalogBoundaryNotCertified=True), indent=2) + '\n')
    print('SELECTED_CONSUMER_CANARIES: PASS', flush=True)


if __name__ == '__main__':
    main()
