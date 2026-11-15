#!/usr/bin/env python3
"""Real runner file ownership controls, executed only in the project VM."""
import importlib.util
import errno
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
RUNNERS = (
    ('popup-close-regression.py', 'popup-close-proof.qml', 'popup-close-contract.qml'),
    ('desktop-settings-refusal-regression.py', 'desktop-settings-refusal-proof.qml', 'desktop-settings-refusal.qml'),
    ('settings-input-commit-regression.py', 'input-commit-proof.qml', 'settings-input-commit.qml'),
    ('settings-live-input-regression.py', 'live-input-proof.qml', 'settings-live-input.qml'),
)


class ProbeFileTests(unittest.TestCase):
    def runner_environment(self, runner, directory):
        root = Path(directory)
        source = root / 'source'
        fixtures = source / 'Scripts/dev/fixtures'
        fixtures.mkdir(parents=True)
        fixture = 'settings-live-input.qml' if runner.startswith('settings-live') else 'settings-input-commit.qml'
        (fixtures / fixture).write_text('import QtQuick\nItem {}\n')
        runtime = root / 'runtime'
        runtime.mkdir()
        profile = SimpleNamespace(uuid='12f17a02-25e9-474c-9dae-fea092c2d2be', uid=1000,
            console=SimpleNamespace(records=[]), child_environment=lambda prefix: {'XDG_RUNTIME_DIR': str(runtime)})
        fake = SimpleNamespace(activate_profile=lambda path: profile, protect_owned_process=lambda process: None)
        spec = importlib.util.spec_from_file_location('runner_under_test', HERE / runner)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        argv = [runner, '--source', str(source), '--output', str(root / 'output'),
                '--work-root', str(root / 'work'), '--guest-profile', str(root / 'profile.json')]
        if runner.startswith('settings-input'):
            argv += ['--case', 'deferred']
        return root, source, module, fake, argv

    def test_live_runner_preserves_dangling_qmlls(self):
        with tempfile.TemporaryDirectory() as directory:
            root, source, module, fake, argv = self.runner_environment('settings-live-input-regression.py', directory)
            target = root / 'not-created.ini'
            qmlls = source / '.qmlls.ini'
            qmlls.symlink_to(target)
            with patch.dict(sys.modules, guest_profile=fake), patch.object(sys, 'argv', argv), \
                    patch('subprocess.run', side_effect=RuntimeError('injected command failure')):
                with self.assertRaisesRegex(AssertionError, 'injected command failure'):
                    module.main()
            self.assertTrue(qmlls.is_symlink(), 'caller symlink removed')
            self.assertFalse(target.exists(), 'caller symlink target created')

    def test_native_input_runners_pin_private_settings_file(self):
        for runner in ('settings-live-input-regression.py', 'settings-input-commit-regression.py'):
            with self.subTest(runner=runner), tempfile.TemporaryDirectory() as directory:
                root, source, module, fake, argv = self.runner_environment(runner, directory)
                caller = root / 'caller.json'
                caller.write_text('caller-owned settings sentinel')
                observed = []
                def reject(argv, **kwargs):
                    observed.append(kwargs['env']['ATMOSPHERA_SETTINGS_FILE'])
                    raise RuntimeError('injected command failure')
                with patch.dict(sys.modules, guest_profile=fake), patch.object(sys, 'argv', argv), \
                        patch.dict(os.environ, ATMOSPHERA_SETTINGS_FILE=str(caller)), patch('subprocess.run', reject):
                    with self.assertRaisesRegex(AssertionError, 'injected command failure'):
                        module.main()
                self.assertTrue(observed)
                self.assertTrue(all(path == str(root / 'work/c/settings.json') for path in observed), observed)
                self.assertEqual(caller.read_text(), 'caller-owned settings sentinel')

    def test_stream_conversion_failure_closes_descriptor_and_removes_probe(self):
        from probe_files import ProbeFiles
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            fixture = source / 'fixture.qml'
            fixture.write_text('Item {}')
            descriptors = []
            def conversion_failure(fd, mode):
                descriptors.append(fd)
                raise OSError('injected stream conversion failure')
            try:
                with patch('probe_files.os.fdopen', conversion_failure), self.assertRaisesRegex(OSError, 'stream conversion'):
                    ProbeFiles(source, fixture)
                with self.subTest(resource='probe'):
                    self.assertEqual(list(source.iterdir()), [fixture], 'conversion failure leaked acquired probe')
                with self.subTest(resource='descriptor'), self.assertRaises(OSError):
                    os.fstat(descriptors[0])
            finally:
                # Close only the descriptor acquired in this test's failing
                # constructor, if the old implementation leaked it.
                for fd in descriptors:
                    try:
                        os.close(fd)
                    except OSError as error:
                        if error.errno != errno.EBADF:
                            raise

    def test_exclusive_collision_and_simultaneous_owners(self):
        from probe_files import ProbeFiles
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            fixture = source / 'fixture.qml'
            fixture.write_text('Item {}')
            collision = source / '.atcq-probe-collision.qml'
            collision.write_text('not owned')
            with patch('tempfile._get_candidate_names', return_value=iter(['collision', 'one'])):
                first = ProbeFiles(source, fixture)
            second = ProbeFiles(source, fixture)
            self.assertNotEqual(first.probe, second.probe)
            self.assertEqual(collision.read_text(), 'not owned')
            second.close()
            self.assertTrue(first.probe.exists())
            first.close()
            self.assertEqual(sorted(path.name for path in source.iterdir()), ['.atcq-probe-collision.qml', 'fixture.qml'])

    def test_partial_acquisition_and_replaced_path(self):
        from probe_files import ProbeFiles
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            fixture = source / 'fixture.qml'
            fixture.write_text('Item {}')
            (source / '.qmlls.ini').mkdir()
            # An existing directory is caller-owned too; exclusive open must not
            # adopt it. It remains unchanged when the probe is retired.
            owner = ProbeFiles(source, fixture)
            owner.close()
            self.assertTrue((source / '.qmlls.ini').is_dir())
            (source / '.qmlls.ini').rmdir()
            real_open = Path.open
            def denied(path, *args, **kwargs):
                if path.name == '.qmlls.ini':
                    raise PermissionError('injected config acquisition failure')
                return real_open(path, *args, **kwargs)
            with patch.object(Path, 'open', denied), self.assertRaises(PermissionError):
                ProbeFiles(source, fixture)
            self.assertEqual(list(source.iterdir()), [fixture])
            owner = ProbeFiles(source, fixture)
            replacement = source / 'replacement'
            replacement.write_text('new owner')
            replacement.replace(owner.probe)
            with self.assertRaisesRegex(RuntimeError, 'replaced file'):
                owner.close()
            self.assertEqual(owner.probe.read_text(), 'new owner')
            self.assertFalse((source / '.qmlls.ini').exists())

    def test_real_runners_preserve_existing_paths_on_failure(self):
        for runner, old_name, fixture in RUNNERS:
            if not (HERE / runner).exists():
                continue  # The input runner belongs to the next stack branch.
            for symlink in (False, True):
                for qmlls_exists in (False, True):
                    with self.subTest(runner=runner, symlink=symlink, qmlls=qmlls_exists), tempfile.TemporaryDirectory() as directory:
                        root = Path(directory)
                        source = root / 'source'
                        fixtures = source / 'Scripts/dev/fixtures'
                        fixtures.mkdir(parents=True)
                        (fixtures / fixture).write_text('import QtQuick\nItem {}\n')
                        original = source / old_name
                        target = root / 'sentinel.qml'
                        target.write_bytes(b'caller-owned sentinel\x00\n')
                        if symlink:
                            original.symlink_to(target)
                        else:
                            original.write_bytes(target.read_bytes())
                        qmlls = source / '.qmlls.ini'
                        if qmlls_exists:
                            qmlls.write_text('caller-owned config\n')
                        runtime = root / 'runtime'
                        runtime.mkdir()
                        profile = SimpleNamespace(uuid='12f17a02-25e9-474c-9dae-fea092c2d2be',
                                                  uid=1000, console=SimpleNamespace(records=[]),
                                                  child_environment=lambda prefix: {'XDG_RUNTIME_DIR': str(runtime)})
                        fake = SimpleNamespace(activate_profile=lambda path: profile,
                                               protect_owned_process=lambda process: None)
                        spec = importlib.util.spec_from_file_location('runner_under_test', HERE / runner)
                        module = importlib.util.module_from_spec(spec)
                        spec.loader.exec_module(module)
                        argv = [runner, '--source', str(source), '--output', str(root / 'output'),
                                '--work-root', str(root / 'work'), '--guest-profile', str(root / 'profile.json')]
                        if runner.startswith('settings-input'):
                            argv += ['--case', 'deferred']
                        # Stop before any actual GUI/daemon command; all file acquisition and
                        # the runner's real exception/cleanup path still execute.
                        with patch.dict(sys.modules, guest_profile=fake), patch.object(sys, 'argv', argv), \
                                patch('subprocess.run', side_effect=RuntimeError('injected command failure')):
                            with self.assertRaisesRegex(AssertionError, 'injected command failure'):
                                module.main()
                        self.assertTrue(original.is_symlink() if symlink else original.is_file(), old_name)
                        self.assertEqual(original.read_bytes(), b'caller-owned sentinel\x00\n')
                        self.assertEqual(target.read_bytes(), b'caller-owned sentinel\x00\n')
                        self.assertEqual(qmlls.exists(), qmlls_exists)
                        if qmlls_exists:
                            self.assertEqual(qmlls.read_text(), 'caller-owned config\n')
                        self.assertEqual(sorted(path.name for path in source.iterdir()),
                                         sorted(['Scripts', old_name] + (['.qmlls.ini'] if qmlls_exists else [])))


if __name__ == '__main__':
    unittest.main()
