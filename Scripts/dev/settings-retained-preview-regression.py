#!/usr/bin/env python3
"""Retained preview/effect assertions on native owners in an explicit guest."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--installed', type=Path, help='optional source for an owned install copy; never modified')
    parser.add_argument('--plugins', type=Path, help='accepted for the paired task wrapper; fixtures are synthetic')
    parser.add_argument('--negative-control', choices=('field-capture', 'preview-revision'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh roots must belong to the explicit guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.installed or args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        config = case / 'config'
        for name in ('config/settings/plugins', 'cache', 'state'):
            (case / name).mkdir(parents=True)
        runner.write_json(config / 'settings.json', dict(settingsVersion=62))
        runner.write_json(config / 'plugins.json', dict(version=6, states={}, sources=[]))
        failure = case / 'readonly'
        failure.mkdir()
        runner.write_json(failure / 'settings.json', dict(label='failure-base'))
        target_identity = (failure / 'settings.json').stat().st_ino
        quarantine = config / 'settings/plugins/i4-preview-fail-quarantine.json'
        quarantine.mkdir()
        (quarantine / 'sentinel').write_text('keep directory and contents\n')
        for name, label in (('i4-preview', 'base'), ('i4-preview-fail', 'failure-base'),
                            ('i4-preview-fail-quarantine', 'quarantine'), ('i4-dead-preview', 'alive')):
            directory = config / 'plugins' / name
            directory.mkdir(parents=True)
            fields = dict(label=dict(type='String', editorUsage='configuration'),
                          other=dict(type='String', editorUsage='configuration'),
                          opaque=dict(type='Record', open=True, editorUsage='operational', fields=dict(keep=dict(type='Boolean'))))
            manifest = dict(id=name, name='Preview', author='Fixture', description='Native preview test', license='MIT',
                            version='1.0.0', entryPoints=dict(settings='Preview.qml'),
                            metadata=dict(defaultSettings=dict(label=label, other='old', opaque=dict(keep=True)),
                                          settingsSchema=dict(version=1, fields=fields)))
            runner.write_json(directory / 'manifest.json', manifest)
            shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-preview-page.qml', directory / 'Preview.qml')
        runner.write_json(config / 'settings/plugins/i4-preview.json', dict(label='base', other='old', opaque=dict(keep=True)))
        link = config / 'settings/plugins/i4-preview-fail.json'
        link.symlink_to(failure / 'settings.json')
        failure.chmod(0o555)
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-preview.qml'
        fault = args.source / 'Scripts/dev/fixtures/plugin-settings-session-fault.py'
        env = dict(PHA_PREVIEW_FAULT=str(fault), PHA_WORK_BASE=str(profile.work_base))
        try:
            if args.negative_control:
                if args.negative_control == 'field-capture':
                    text = fixture.read_text()
                    needle = 'var editor = factory(fieldIntent);'
                    if text.count(needle) != 1:
                        raise RuntimeError('review the field-capture host control')
                    fixture = case / fixture.name
                    fixture.write_text(text.replace(needle, 'var editor = factory();', 1))
                    expected = 'I4_PREVIEW_ASSERT: selected page requires field capture'
                else:
                    target = install / 'Services/Plugins/PluginSettingsPreview.qml'
                    text = target.read_text()
                    needle = 'if (root._revisions[key] !== captured.revisions[key])'
                    if text.count(needle) != 1:
                        raise RuntimeError('review the preview revision control')
                    target.write_text(text.replace(needle, 'if (false)', 1))
                    expected = 'old revision cannot clear newer fields'
                output = out / 'control'
                output.mkdir()
                try:
                    runner.run_fixture(profile, install, case, output, fixture, extra_env=env, timeout=100)
                except RuntimeError:
                    log = (output / 'runtime.log').read_text()
                    code = (output / 'runtime.exit').read_text().strip()
                    if code != '2' or expected not in log or any(error in log for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:')):
                        raise RuntimeError('rejecting control missed its exact consumer assertion')
                else:
                    raise RuntimeError('rejecting control unexpectedly passed')
                runner.write_json(out / 'result.json', dict(status='PASS', kind='rejecting-control',
                    control=args.negative_control, actualRuntimeExit=2, expectedAssertion=expected, productionCoverage=False))
                runner.remove_completed_installs(case, out)
                print('SETTINGS_RETAINED_PREVIEW_CONTROL: PASS (' + args.negative_control + ')', flush=True)
                return
            for mode in ('save', 'cold'):
                output = out / mode
                output.mkdir()
                text = runner.run_fixture(profile, install, case, output, fixture,
                                          extra_env=dict(env, I4_VERIFY='1' if mode == 'cold' else '0'),
                                          extra_lint=(case / 'config/plugins/i4-preview/Preview.qml',), timeout=100)
                marker = 'I4_PREVIEW: ' + ('RESTART_PASS' if mode == 'cold' else 'SAVED_PASS')
                if marker not in text or any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', '_ASSERT:')):
                    raise RuntimeError('retained preview native consumer failure; see ' + str(output / 'runtime.log'))
                shared = json.loads((config / 'settings/plugins/i4-preview.json').read_text())
                if shared != dict(label='final', other='foreign-other', opaque=dict(keep=True)):
                    raise RuntimeError('independent retained-preview saved file mismatch')
                if not link.is_symlink() or link.resolve() != failure / 'settings.json':
                    raise RuntimeError('failed destination link identity changed')
                if (failure / 'settings.json').stat().st_ino != target_identity or json.loads((failure / 'settings.json').read_text()) != dict(label='failure-base'):
                    raise RuntimeError('failed publication altered its actual destination')
                if not quarantine.is_dir() or sorted(path.name for path in quarantine.iterdir()) != ['sentinel'] or (quarantine / 'sentinel').read_text() != 'keep directory and contents\n':
                    raise RuntimeError('quarantined directory or sentinel changed')
                runner.write_json(output / 'persisted.json', dict(shared=shared, linkedTargetUnchanged=True, quarantineUnchanged=True))
            inputs = {str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (fixture, fault, args.source / 'Scripts/dev/fixtures/plugin-preview-page.qml',
                                   args.source / 'Services/Plugins/PluginSettingsSession.qml',
                                   args.source / 'Widgets/NPluginSettingsPopup.qml')}
            runner.write_json(out / 'result.json', dict(status='PASS', fixture=fixture.name, legs=['save', 'cold'],
                inputs=inputs, fourPlacementPreviews=True, foreignEdits=True, reorderRefusal=True,
                heldCurrentStaleNoop=True, realIoFailure=True, quarantineUnchanged=True,
                ownerDestruction=True, independentPersistedReadback=True, separateColdConsumer=True))
            runner.remove_completed_installs(case, out)
            print('SETTINGS_RETAINED_PREVIEW: PASS', flush=True)
        finally:
            (config / 'settings/plugins').chmod(0o755)
            failure.chmod(0o755)
            profile.verify()


if __name__ == '__main__':
    main()
