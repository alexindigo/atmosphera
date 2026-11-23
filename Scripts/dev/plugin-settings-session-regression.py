#!/usr/bin/env python3
"""Selected-session extraction gate, only inside the explicitly named guest."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--install-source', type=Path, help='optional pinned baseline; fixtures still come from --source')
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
        shutil.copytree(args.install_source or args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'config/plugins/session-fixture', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        manifest = dict(id='session-fixture', name='Session fixture', author='Atmosphera fixture', description='Selected-session native contract fixture', version='1.0.0', entryPoints=dict(settings='Page.qml'), metadata=dict(
            defaultSettings=dict(label='default'), settingsSchema=dict(version=1, fields=dict(label=dict(type='String', editorUsage='configuration')))))
        runner.write_json(case / 'config/plugins/session-fixture/manifest.json', manifest)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        runner.write_json(case / 'config/settings/plugins/session-fixture.json', dict(label='shared', opaque=dict(keep=True)))
        shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-session-page.qml', case / 'config/plugins/session-fixture/Page.qml')
        page_source = (args.source / 'Scripts/dev/fixtures/plugin-settings-session-page.qml').read_text()
        predicate = '  readonly property bool settingsDirty: pluginApi && labelText !== pluginApi.initialSettings.label\n'
        if page_source.count(predicate) != 1:
            raise RuntimeError('review the synthetic untracked-buffer page construction')
        (case / 'config/plugins/session-fixture/Legacy.qml').write_text(page_source.replace(predicate, '', 1))
        (case / 'config/plugins/registration-fixture').mkdir()
        runner.write_json(case / 'config/plugins/registration-fixture/manifest.json', dict(manifest, id='registration-fixture'))
        quarantine_plugin = case / 'config/plugins/session-quarantine'
        quarantine_plugin.mkdir()
        runner.write_json(quarantine_plugin / 'manifest.json', dict(manifest, id='session-quarantine'))
        quarantine = case / 'config/settings/plugins/session-quarantine.json'
        quarantine.mkdir()
        (quarantine / 'sentinel').write_text('keep directory and contents\n')
        quarantine_identity = quarantine.stat().st_ino
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-session.qml'
        fault = args.source / 'Scripts/dev/fixtures/plugin-settings-session-fault.py'
        env = dict(PHA_SESSION_FAULT=str(fault), PHA_WORK_BASE=str(profile.work_base))
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
            if any('PLUGIN_SETTINGS_SESSION: ' + marker not in text for marker in ('PASS', 'QUARANTINE_PRESERVED', 'RETIRED_REGISTRATION_REFUSED')):
                raise RuntimeError('actual session marker missing')
            bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
            if any(marker in text for marker in bad):
                raise RuntimeError('actual session runtime diagnostics; see runtime.log')
            runtime = Path(text.split('Saving logs to "', 1)[1].split('/quickshell/', 1)[0])
            if not runtime.is_relative_to(profile.runtime_base):
                raise RuntimeError('runtime tooling path is outside the verified profile')
            vfs = list((runtime / 'quickshell/vfs').iterdir())
            if len(vfs) != 1:
                raise RuntimeError('actual native lint universe missing or ambiguous')
            targets = [install / 'Widgets/NPluginSettingsPopup.qml']
            if (install / 'Services/Plugins/PluginSettingsSession.qml').exists():
                targets.append(install / 'Services/Plugins/PluginSettingsSession.qml')
            targets.extend(case / 'config/plugins/session-fixture' / name for name in ('Page.qml', 'Legacy.qml'))
            lint = subprocess.run(['bash', str(install / 'Scripts/dev/qmllint.sh'), *map(str, targets)],
                                  cwd=install, env=dict(os.environ, QS_VFS=str(vfs[0])),
                                  text=True, capture_output=True, timeout=180)
            (out / 'session-lint.log').write_text(lint.stdout + lint.stderr)
            if lint.returncode != 0:
                raise RuntimeError('session/popup/page native-universe lint failed')
            shared = json.loads((case / 'config/settings/plugins/session-fixture.json').read_text())
            row = json.loads((case / 'config/settings/bar.json').read_text())['widgets']['left'][0]
            if shared != dict(label='final', opaque=dict(keep=True)) or row != dict(id='plugin:session-fixture', tag='keep'):
                raise RuntimeError('independent persisted selected-owner readback mismatch')
            cold = out / 'cold'
            cold.mkdir()
            text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_SESSION_COLD='1'))
            if 'PLUGIN_SETTINGS_SESSION: COLD_PASS' not in text or any(marker in text for marker in bad):
                raise RuntimeError('separate cold native consumer mismatch')
            if not quarantine.is_dir() or quarantine.stat().st_ino != quarantine_identity or sorted(path.name for path in quarantine.iterdir()) != ['sentinel'] or (quarantine / 'sentinel').read_text() != 'keep directory and contents\n':
                raise RuntimeError('independent startup directory quarantine preservation failed')
            inputs = {str(path.relative_to(install)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (
                install / 'Widgets/NPluginSettingsPopup.qml', install / 'Services/Plugins/PluginSettingsSession.qml',
                install / 'Services/Plugins/Service.qml') if path.exists()}
            inputs.update({str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (
                fixture, fault, args.source / 'Scripts/dev/fixtures/plugin-settings-session-page.qml')})
            runner.write_json(out / 'result.json', dict(status='PASS', inputs=inputs, nativeApply=True, realIoFailureAndRetry=True,
                savedButStaleRetention=True, dirtyCloseKeepDiscard=True, busyExclusion=True, signalBeforeCallbacks=True,
                instanceReset=True, independentPersistedReadback=True, separateColdConsumer=True, fieldOnlyRoleAdoption=True,
                nativeHideRetainsHeldPage=True, directoryQuarantinePreserved=True, untrackedBufferCloseConfirmation=True,
                appliedPreviewLeavesRuntime=True, newerPreviewRetained=True, failedAndStaleWritePreviewsRetained=True,
                retiredRegistrationRefusal=True,
                consolidatedFixture='plugin-settings-popup.qml'))
            runner.remove_completed_installs(case, out)
            print('PLUGIN_SETTINGS_SESSION: PASS (native persistence/receipt/close/cold; field-only page)', flush=True)
        finally:
            (case / 'config/settings/plugins').chmod(0o755)


if __name__ == '__main__':
    main()
