#!/usr/bin/env python3
"""Image decoding end-consumer regression controller; explicit owned guest only."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from guest_profile import activate_profile, profile_argument, protect_owned_process
from image_decoding_fixtures import COLORS, create_fixtures, pixel, read_png
from image_decoding_evidence import source_manifest
from image_decoding_workspace import retire_fixture_copy
from qml_probe import bootstrap_fixture


CASES = ('red', 'icons-red', 'icons', 'artwork-red', 'artwork', 'cache-clear-red', 'cache-clear', 'remote-red', 'wizard-red', 'cache-red', 'cache', 'cache-read-red', 'cache-read', 'producer-capture', 'producer-retirement-red', 'notification-adapter', 'notification-service-red', 'notification-service', 'wallpaper-wizard', 'wallpaper-remote', 'owner', 'legacy', 'backdrops', 'rounded', 'wallpaper-admission', 'wallpaper-setup', 'wallpaper-scan', 'wallpaper-gallery', 'desktop-wallpaper', 'chooser', 'chooser-wallpaper', 'shell', 'plugins', 'packaging', 'all', 'review-results')
ERRORS = re.compile(r'ReferenceError|TypeError|SyntaxError|Cannot assign|Unable to assign|Binding loop|'
                    r'Failed to load configuration|is not installed|Component is not ready|'
                    r'completion callback threw|Wallpaper settlement callback failed|Completion callback failed for request')


class Run:
    def __init__(self, args, profile):
        self.args, self.profile = args, profile
        self.out, self.work = args.output, args.work_root
        for path, parent in ((self.out, profile.journal_base), (self.work, profile.work_base)):
            if path != path.resolve() or not path.is_relative_to(parent) or path == parent or path.exists():
                raise ValueError('Fresh canonical child required: ' + str(path))
        for source in (args.source, args.plugins, args.baseline_source, args.baseline_plugins):
            if source is not None and (source != source.resolve() or not source.is_dir() or not source.is_relative_to(profile.workspace)):
                raise ValueError('Canonical source inside the named guest workspace required')
        profile.prepare_roots()
        self.out.mkdir(mode=0o700)
        self.work.mkdir(mode=0o700)
        self.commands, self.cases = [], []
        self.started = time.monotonic()
        self.inputs = {key: source_manifest(path) for key, path in
                       (('source', args.source), ('plugins', args.plugins), ('baselineSource', args.baseline_source),
                        ('baselinePlugins', args.baseline_plugins)) if path is not None}
        (self.out / 'inputs.json').write_text(json.dumps(self.inputs, indent=2) + '\n')
        self.record('running')

    def record(self, state, failure=''):
        data = dict(state=state, case=self.args.case, qtWebp=self.args.qt_webp, elapsedSeconds=time.monotonic() - self.started,
                    guest=self.profile.record(), cases=self.cases, failure=failure,
                    inputs={key: row['sha256'] for key, row in self.inputs.items()})
        pending = self.out / 'status.pending'
        pending.write_text(json.dumps(data, indent=2) + '\n')
        pending.replace(self.out / 'status.json')
        (self.out / 'interim-report.md').write_text('# Image decoding progress\n\n' + state + '\n\n' + '\n'.join(
            f'- {r["id"]}: {r["result"]}' for r in self.cases) + '\n')
        return data

    def command(self, argv, timeout=90, **kwargs):
        result = subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=timeout, **kwargs)
        self.commands.append(dict(argv=list(map(str, argv)), exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
        (self.out / 'commands.json').write_text(json.dumps(self.commands, indent=2) + '\n')
        return result

    def check(self, name, condition, detail, red=False):
        result = 'REPRODUCED' if condition and red else 'PASS' if condition else 'FAIL'
        row = dict(id=name, result=result, detail=detail)
        self.cases.append(row)
        self.record('running')
        print(('RED_CONTROL ' if red else 'CASE ') + name + ': ' + result, flush=True)
        if not condition:
            raise AssertionError(name + ': ' + json.dumps(detail))

    def qt(self, source, fixture, inputs, name, extra_env=None, assembled=False):
        result = self._qt(source, fixture, inputs, name, extra_env, assembled)
        if not assembled:
            retire_fixture_copy(source, self.work / name, self.out / (name + '-source.json'),
                                self.out / (name + '-source-retired.json'), self.work)
        return result

    def _qt(self, source, fixture, inputs, name, extra_env=None, assembled=False):
        # Actual production imports are copied, never mocked or rewritten. Only
        # the separate test entry and private XDG preferences are synthesized.
        shell = source if assembled else self.work / name
        before = source_manifest(source)
        if not assembled:
            shutil.copytree(source, shell, symlinks=True, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        after = source_manifest(shell)
        if before != after:
            raise AssertionError('Copied consumer tree differs')
        (self.out / (name + '-source.json')).write_text(json.dumps(before, indent=2) + '\n')
        profile = self.work / (name + '-profile')
        for directory in ('config', 'cache', 'state', 'data', 'tmp'):
            (profile / directory).mkdir(parents=True)
        defaults = json.loads((source / 'Configs/defaults.json').read_text())
        defaults['general']['showChangelogOnStartup'] = False
        defaults['wallpaper']['directory'] = str(inputs)
        if self.args.case == 'backdrops':
            defaults['wallpaper'].update(enabled=True, useSolidColor=False)
            defaults['general'].update(lockScreenBlur=0, lockScreenTint=0, showScreenCorners=False)
        if self.args.case == 'rounded':
            defaults['general']['animationDisabled'] = (extra_env or {}).get('IMAGE_ROUNDED_REDUCED') == '1'
        if self.args.case == 'desktop-wallpaper':
            defaults['wallpaper'].update(enabled=True, useSolidColor=False, automationEnabled=False, overviewEnabled=True,
                                         overviewBlur=0, overviewTint=0, transitionDuration=200, skipStartupTransition=True)
        if self.args.case == 'notification-service':
            (profile / 'config/notification-rules.json').write_text(json.dumps(dict(rules=[
                dict(pattern='blocked', action='block'), dict(pattern='hidden', action='hide')])))
        if self.args.case == 'wallpaper-remote':
            defaults['wallpaper'].update(enabled=True, useSolidColor=False, automationEnabled=False,
                                         linkLightAndDarkWallpapers=False, setWallpaperOnAllMonitors=False)
            defaults['colorSchemes']['darkMode'] = False
        if self.args.case == 'wallpaper-admission':
            defaults['wallpaper'].update(enabled=True, useSolidColor=False, linkLightAndDarkWallpapers=False,
                                         setWallpaperOnAllMonitors=False, automationEnabled=False)
            defaults['wallpaper']['useOriginalImages'] = (extra_env or {}).get('IMAGE_USE_ORIGINAL') == '1'
        (profile / 'config/settings.json').write_text(json.dumps(defaults))
        if self.args.case in ('cache-clear-red', 'cache-clear'):
            # Pre-owner shell output and a plugin-owned thumbnail folder.
            legacy = profile / 'cache/images/wallpapers'
            (legacy / 'large').mkdir(parents=True)
            (legacy / 'thumbnails/mpvpaper').mkdir(parents=True)
            (legacy / 'large/legacy-key.png').write_bytes((inputs / 'frame-0.png').read_bytes())
            (legacy / 'thumbnails/mpvpaper/plugin.bmp').write_bytes(b'plugin-owned')
        if self.args.case in ('icons-red', 'icons', 'artwork-red', 'artwork'):
            # Real XdgIcon loose-icon lookup in the private XDG data root.
            themes = profile / 'data/icons'
            themes.mkdir(parents=True)
            for icon, source in (('fixture-webp-app.png', 'Still.webp'), ('fixture-png-app.png', 'frame-1.png'),
                                 ('fixture-svg-app.svg', 'Still.svg'), ('fixture-corrupt-app.png', 'Corrupt.webp')):
                shutil.copyfile(inputs / source, themes / icon)
        if self.args.case in ('cache-red', 'cache', 'cache-read-red', 'cache-read'):
            from image_decoding_cache_fixtures import target, thumbnail
            redirected = self.args.case in ('cache-read-red', 'cache-read')
            if redirected:
                outside = profile / 'user-originals'
                outside.mkdir(mode=0o755)
                bucket = profile / 'cache/thumbnails/normal'
                bucket.parent.mkdir(parents=True)
                bucket.symlink_to(outside, target_is_directory=True)
            for filename, depth, interlace, text in (('Still.webp', 8, 0, 'tEXt'), ('Foreign16.webp', 16, 0, 'zTXt'),
                                                  ('ForeignInterlaced.webp', 8, 1, 'iTXt')):
                cached = target(profile / 'cache/thumbnails', inputs / filename)
                if not redirected:
                    cached.parent.mkdir(parents=True, exist_ok=True)
                cached.write_bytes(thumbnail(inputs / filename, depth=depth, interlace=interlace, text=text))
        entry = shell / 'image-decoding-fixture.qml'
        entry.write_text(bootstrap_fixture(fixture.read_text()))
        # Opt into Quickshell's authoritative qs.* tooling descriptions, using
        # the same mechanism as qml-lint-ci.py. Lint must resolve composites,
        # rather than turn missing imports into an apparently clean result.
        (shell / '.qmlls.ini').touch()
        output = self.out / name
        output.mkdir()
        env = dict(os.environ, **self.profile.child_environment('image-'),
                    QML_DISABLE_DISK_CACHE='1', QT_QPA_PLATFORM='wayland', IMAGE_FIXTURES=str(inputs), IMAGE_OUTPUT=str(output),
                    IMAGE_DATA='data:image/jpeg;base64,' + base64.b64encode((inputs / 'Still.webp').read_bytes()).decode(),
                    ATMOSPHERA_CONFIG_DIR=str(profile / 'config') + '/', ATMOSPHERA_CACHE_DIR=str(profile / 'cache') + '/',
                    IMAGE_ICON_DIR=str(self.args.source / 'builtin/plugins/atmosphera-icons'),
                   ATMOSPHERA_STATE_DIR=str(profile / 'state') + '/', ATMOSPHERA_SETTINGS_FILE=str(profile / 'config/settings.json'),
                   XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'),
                    XDG_STATE_HOME=str(profile / 'state'), XDG_DATA_HOME=str(profile / 'data'), TMPDIR=str(profile / 'tmp'))
        env.update(extra_env or {})
        argv = ['qs', '-p', str(entry)]
        with (output / 'qt.log').open('w') as log:
            proc = subprocess.Popen(argv, env=env, cwd=shell, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
            guard = protect_owned_process(proc)
            try:
                # Inspect the actual fresh reader process, not an environment
                # flag that merely claims a plugin condition.
                maps = set()
                deadline = time.monotonic() + (90 if self.args.case == 'notification-service' else 25)
                while proc.poll() is None:
                    try:
                        maps.update(line.split()[-1] for line in Path(f'/proc/{proc.pid}/maps').read_text().splitlines()
                                    if 'imageformats/' in line)
                    except FileNotFoundError:
                        pass
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Qt consumer watchdog')
                    time.sleep(.05)
                code = proc.wait(timeout=25)
            finally:
                if proc.poll() is None:
                    guard.terminate()
                    proc.wait(timeout=10)
        text = (output / 'qt.log').read_text()
        (output / 'process.json').write_text(json.dumps(dict(argv=argv, identity=guard.identity.record() if guard.identity else None, exit=code, imagePlugins=sorted(maps)), indent=2) + '\n')
        errors = [line for line in text.splitlines() if ERRORS.search(line)]
        if code or errors:
            raise AssertionError(dict(exit=code, runtimeErrors=errors, log=str(output / 'qt.log')))
        vfs = (shell / '.qmlls.ini').resolve(strict=True).parent
        if not vfs.is_relative_to(self.profile.runtime_base) or not (vfs / 'qs/Commons/qmldir').is_file():
            raise AssertionError('Consumer did not generate authoritative QML tooling')
        lint_paths = [str(entry)]
        if self.args.case in ('owner', 'legacy'):
            lint_paths += [str(shell / p) for p in ('Services/UI/ImageWorker.qml', 'Services/UI/ImageSource.qml',
                                                    'Services/UI/ImageCacheService.qml', 'Widgets/NImage.qml')]
        if self.args.case in ('cache', 'cache-read'):
            lint_paths += [str(shell / p) for p in ('Services/UI/ImageSource.qml', 'Widgets/NImage.qml',
                'Services/UI/ImageCacheService.qml', 'Modules/FileChooser/FileEntryArtwork.qml')]
        if self.args.case in ('cache-clear-red', 'cache-clear'):
            lint_paths += [str(shell / p) for p in ('Services/UI/ImageWorker.qml', 'Services/UI/ImageCacheService.qml',
                'Modules/Panels/Settings/Tabs/Wallpaper/GeneralSubTab.qml')]
        if self.args.case == 'icons':
            lint_paths += [str(shell / p) for p in ('Commons/AtmoAppIcon.qml', 'Widgets/AtmoIcon.qml',
                'Modules/Bar/Widgets/ActiveWindow.qml')]
        if self.args.case == 'artwork':
            lint_paths += [str(shell / p) for p in ('Widgets/NImageIcon.qml', 'Commons/AtmoAppIcon.qml',
                'Modules/Bar/Extras/TrayMenu.qml', 'Modules/Bar/Widgets/ControlCenter.qml', 'Modules/Bar/Widgets/Launcher.qml',
                'Modules/Bar/Widgets/Tray.qml', 'Modules/Panels/Tray/TrayDrawerPanel.qml', 'Modules/Dock/DockContent.qml',
                'Modules/FileChooser/FileAppOptions.qml', 'Modules/Cards/MediaCard.qml', 'Modules/Panels/Media/MediaPlayerPanel.qml',
                'Modules/Panels/Settings/DesktopWidgets/WidgetSettings/AppShortcutSettings.qml',
                'Modules/Panels/Settings/Tabs/Dock/AppearanceSubTab.qml', 'builtin/plugins/demo-custom-lockscreen/LockScreenView.qml')]
        if self.args.case == 'chooser':
            lint_paths += [str(shell / p) for p in ('Services/Files/FileTypes.qml', 'Services/Files/FileThumbnails.qml',
                'Services/Files/FileThumbnail.qml', 'Services/UI/ImageWorker.qml', 'Modules/FileChooser/FileEntryArtwork.qml',
                 'Modules/FileChooser/FileEntry.qml', 'Modules/FileChooser/FileQuickLook.qml')]
        if self.args.case == 'backdrops':
            lint_paths += [str(shell / p) for p in ('Widgets/NImageBackdrop.qml', 'Widgets/AtmoWallpaperBackground.qml',
                'Modules/LockScreen/LockScreenBackground.qml') if (shell / p).is_file()]
        if self.args.case == 'rounded':
            lint_paths += [str(shell / p) for p in ('Widgets/NImageRounded.qml', 'Widgets/NImage.qml')]
        if self.args.case == 'wallpaper-admission':
            lint_paths += [str(shell / p) for p in ('Services/UI/WallpaperService.qml',
                'Modules/Panels/Wallpaper/WallpaperPanel.qml')]
        if self.args.case == 'wallpaper-setup':
            lint_paths += [str(shell / p) for p in ('Modules/Panels/SetupWizard/SetupWallpaperStep.qml',)]
        if self.args.case in ('wallpaper-wizard', 'wizard-red'):
            lint_paths += [str(shell / p) for p in ('Modules/Panels/SetupWizard/SetupWizard.qml',
                'Services/UI/WallpaperService.qml', 'Services/UI/SetupService.qml') if (shell / p).is_file()]
        if self.args.case == 'wallpaper-scan':
            lint_paths += [str(shell / 'Services/UI/WallpaperService.qml')]
        if self.args.case == 'wallpaper-gallery':
            lint_paths += [str(shell / 'Modules/Panels/Wallpaper/WallpaperPanel.qml')]
        if self.args.case == 'wallpaper-remote':
            lint_paths += [str(shell / p) for p in ('Services/UI/WallhavenService.qml', 'Services/UI/WallpaperService.qml',
                'Services/UI/ImageCacheService.qml', 'Services/UI/ImageWorker.qml', 'Modules/Panels/Wallpaper/WallpaperPanel.qml')]
        if self.args.case == 'desktop-wallpaper':
            lint_paths += [str(shell / p) for p in ('Modules/Background/Background.qml', 'Modules/Background/Overview.qml')]
        if self.args.case in ('producer-capture', 'producer-retirement-red', 'notification-adapter'):
            lint_paths += [str(shell / p) for p in ('Services/UI/ImageAdmission.qml', 'Services/UI/ImageCacheService.qml')]
        if self.args.case == 'notification-service':
            lint_paths += [str(shell / p) for p in ('Services/System/NotificationService.qml', 'Services/UI/ImageCacheService.qml',
                'Widgets/NImageRounded.qml', 'Widgets/NNotificationImage.qml', 'Modules/Notification/Notification.qml',
                'Modules/Panels/NotificationHistory/NotificationHistoryPanel.qml')]
        lint = self.command(['bash', str(self.args.source / 'Scripts/dev/qmllint.sh'), *lint_paths], timeout=900,
                            cwd=shell, env=dict(env, QS_VFS=str(vfs)))
        (output / 'qmllint.log').write_text(lint.stdout + lint.stderr)
        if lint.returncode or 'Failed to import qs.' in lint.stderr:
            raise AssertionError('Composite-aware consumer fixture lint failed')
        rows = [json.loads(line.split('IMAGE_BASELINE|', 1)[1]) for line in text.splitlines() if 'IMAGE_BASELINE|' in line]
        grabs = [json.loads(line.split('IMAGE_GRAB|', 1)[1]) for line in text.splitlines() if 'IMAGE_GRAB|' in line]
        assert len(rows) == 1 and grabs and all(row['saved'] for row in grabs)
        (output / 'consumer.json').write_text(json.dumps(rows[0], indent=2) + '\n')
        return rows[0], output

    def producer_capture(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        expected = [inputs / 'Still.webp', inputs / 'Still.webp', inputs / 'frame-0.png']
        names = ('ephemeral.webp', "literal '[x]: é.dat", 'ephemeral.png')
        for source, name in zip(expected, names):
            shutil.copyfile(source, inputs / name)
        # The service and producer share a genuinely private bus, never the
        # guest's real notification endpoint. Keep its socket disk-backed too.
        address = 'unix:path=' + str(self.work / 'notification-bus')
        bus_log = (self.out / 'bus.log').open('w')
        bus = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1', '--address=' + address],
                               stdout=subprocess.PIPE, stderr=bus_log, text=True, start_new_session=True)
        guard = protect_owned_process(bus)
        bus_record = dict(identity=guard.identity.record())
        try:
            actual = bus.stdout.readline().strip()
            assert actual.startswith(address)
            red = self.args.case == 'producer-retirement-red'
            adapter = self.args.case == 'notification-adapter'
            if red and self.args.baseline_source is None:
                raise ValueError('Producer retirement red requires an explicit immutable baseline source')
            source = self.args.baseline_source if red else self.args.source
            name = 'producer-retirement-red' if red else 'notification-adapter' if adapter else 'producer-capture'
            result, output = self.qt(source, self.args.source / ('Scripts/dev/fixtures/image-decoding/' + name + '.qml'),
                                     inputs, name, extra_env=dict(DBUS_SESSION_BUS_ADDRESS=actual,
                                     IMAGE_PRODUCER=str(self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-producer.py')))
        finally:
            guard.terminate()
            bus_record['exit'] = bus.wait(timeout=10)
            bus_log.close()
            (self.out / 'bus-process.json').write_text(json.dumps(bus_record, indent=2) + '\n')
        if red:
            self.check('producer-file-retirement-old-adapter', len(result['legacyFiles']) == 4
                       and all(row['path'] and not row['success'] and row['statusAfterLoss'] == 3 for row in result['legacyFiles']),
                       result['legacyFiles'], red=True)
            self.check('retirement-red-real-producer', result['producerExit'] == 0 and not result['producerErrors']
                       and all(not (inputs / name).exists() for name in names), result)
            return result
        if adapter:
            return self.notification_adapter_results(result, output, inputs, expected, installed)
        self.check('capture-native-reader-control', result['raw'] == (1 if installed else 3), result['raw'])
        self.check('capture-binary-padding-exact', all(base64.b64decode(row['url'].split(',', 1)[1], validate=True)
                   == bytes(i % 256 for i in range(row['length'])) for row in result['bytes']) and len(result['bytes']) == 7, result['bytes'])
        captures = result['captured']
        self.check('capture-provider-revisions-observed', len(captures) == 9 and len({r['original'] for r in captures[1:5]}) == 4
                   and captures[1]['id'] == captures[2]['id'] == captures[3]['id'] != captures[4]['id'],
                   [{k: v for k, v in row.items() if k not in ('source', 'snapshot')} for row in captures])
        self.check('capture-provider-gone-before-retention', len(result['late']) == 4
                   and all(row['status'] == 3 for row in result['late']) and result['producerExit'] == 0
                   and not result['producerErrors'], result['late'])
        self.check('capture-files-gone-before-retention', all(not (inputs / name).exists() for name in names), names)
        self.check('capture-exact-original-bytes', all(base64.b64decode(captures[index]['source'].split(',', 1)[1], validate=True)
                   == source.read_bytes() for index, source in zip((5, 7, 8), expected)), [5, 7, 8])
        self.check('capture-same-url-replacement-bytes', captures[5]['original'] == captures[6]['original']
                   and captures[5]['id'] != captures[6]['id'] and base64.b64decode(captures[6]['source'].split(',', 1)[1], validate=True)
                   == (inputs / 'frame-1.png').read_bytes(), captures[6]['original'])
        rows = sorted(result['results'], key=lambda row: row['index'])
        expected_colors = [list(COLORS[0]), [230, 30, 50, 255], [20, 210, 70, 255], [30, 60, 230, 255],
                           [230, 30, 50, 255], list(COLORS[0]), list(COLORS[1]), list(COLORS[0]), list(COLORS[0])]
        observed = [pixel(output / ('retained-' + str(i) + '.png')) for i in range(9)]
        self.check('capture-retained-consumer-pixels', len(rows) == 9 and all(row['success'] for row in rows)
                   and observed == expected_colors, observed)
        self.check('capture-content-not-label-identity', rows[1]['path'] == rows[4]['path']
                   and len({row['path'] for row in rows[1:4]}) == 3
                   and all(Path(row['path']).is_file() for row in rows), [row['path'] for row in rows])
        self.check('capture-retained-format-not-fake-png', Path(rows[5]['path']).suffix == '.webp'
                   and Path(rows[5]['path']).read_bytes() == expected[0].read_bytes()
                   and Path(rows[8]['path']).suffix == '.png', [rows[5]['path'], rows[8]['path']])
        self.check('capture-provider-alpha', all(pixel(Path(row['path']), 0, 0)[3] == 0 for row in rows[1:5]),
                   [pixel(Path(row['path']), 0, 0) for row in rows[1:5]])
        self.check('capture-refusal-reasons', all(not result[name]['ok'] and result[name]['code'] and result[name]['reason']
                   for name in ('missing', 'empty', 'badProvider')), {name: result[name] for name in ('missing', 'empty', 'badProvider')})
        self.check('capture-cancel-and-quiescence', not result['cancelled'] and not result['worker'] and result['interests'] == 0
                   and not (output / 'cancelled').exists(), result['cancelled'])
        return result

    def notification_adapter_results(self, result, output, inputs, expected, installed):
        self.check('adapter-native-reader-control', result['raw'] == (1 if installed else 3), result['raw'])
        admitted = result['admitted']
        rows = sorted(result['results'], key=lambda row: row['index'])
        self.check('adapter-producer-loss', result['producerExit'] == 0 and not result['producerErrors']
                   and len(admitted) == 9 and all(not (inputs / name).exists() for name in
                   ('ephemeral.webp', "literal '[x]: é.dat", 'ephemeral.png')), admitted)
        colors = [list(COLORS[0]), [230, 30, 50, 255], [20, 210, 70, 255], [30, 60, 230, 255],
                  [230, 30, 50, 255], list(COLORS[0]), list(COLORS[1]), list(COLORS[0]), list(COLORS[0])]
        observed = [pixel(output / f'adapter-{i}.png') for i in range(9)]
        self.check('adapter-retained-consumer-pixels', len(rows) == 9 and all(row['success'] for row in rows)
                   and observed == colors, observed)
        self.check('adapter-content-not-label-identity', rows[1]['path'] == rows[4]['path']
                   and len({row['path'] for row in rows[1:4]}) == 3
                   and admitted[5]['original'] == admitted[6]['original'] and rows[5]['path'] != rows[6]['path'], rows)
        self.check('adapter-exact-original-format', all(Path(rows[i]['path']).read_bytes() == source.read_bytes()
                   for i, source in zip((5, 7, 8), expected)) and Path(rows[5]['path']).suffix == '.webp'
                   and Path(rows[6]['path']).read_bytes() == (inputs / 'frame-1.png').read_bytes(), rows)
        self.check('adapter-provider-alpha', all(pixel(Path(row['path']), 0, 0)[3] == 0 for row in rows[1:5]), rows[1:5])
        self.check('adapter-qt-acknowledged-representation', all(row['success'] and row['detail']['status'] in ('generated', 'hit')
                   and row['detail']['url'] and Path(row['path']).is_file() for row in rows), rows)
        self.check('adapter-explicit-failures', len(result['failures']) == 4 and all(not row['path'] and not row['success']
                   and row['detail']['code'] and row['detail']['reason'] for row in result['failures']), result['failures'])
        self.check('adapter-cancel-suppressed', not result['cancelled'], result['cancelled'])
        self.check('adapter-quiescence', result['interests'] == 0 and not result['worker'], result['interests'])
        return result

    def notification_service(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        shutil.copyfile(inputs / 'Still.webp', inputs / 'service-ephemeral.webp')
        red = self.args.case == 'notification-service-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Actual notification service red requires immutable baseline source')
        source = self.args.baseline_source if red else self.args.source
        address = 'unix:path=' + str(self.work / 'service-bus')
        http_events = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                history = self.path == '/history.jpg'
                payload = (inputs / 'Still.webp').read_bytes()
                self.send_response(200)
                self.send_header('Content-Length', str(len(payload)) if history else '1000')
                self.end_headers()
                self.wfile.flush()
                (inputs / ('http-history-started' if history else 'http-started')).write_text('held\n')
                if history:
                    deadline = time.monotonic() + 15
                    while not (inputs / 'http-history-release').exists() and time.monotonic() < deadline:
                        time.sleep(.02)
                    self.wfile.write(payload)
                    self.wfile.flush()
                    http_events.append(dict(path=self.path, delivered=True))
                    return
                self.connection.settimeout(20)
                try:
                    eof = self.connection.recv(1) == b''
                except TimeoutError:
                    eof = False
                http_events.append(dict(path=self.path, eof=eof))
            def log_message(self, *_args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        with (self.out / 'bus.log').open('w') as log:
            bus = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1', '--address=' + address],
                                   stdout=subprocess.PIPE, stderr=log, text=True, start_new_session=True)
            guard = protect_owned_process(bus)
            try:
                actual = bus.stdout.readline().strip()
                assert actual.startswith(address)
                name = 'notification-service-red' if red else 'notification-service'
                result, output = self.qt(source, self.args.source / ('Scripts/dev/fixtures/image-decoding/' + name + '.qml'),
                    inputs, name, extra_env=dict(DBUS_SESSION_BUS_ADDRESS=actual,
                    ATMOSPHERA_NOTIF_HISTORY_FILE=str(inputs / 'history.json'),
                    IMAGE_SERVICE_URL='http://127.0.0.1:' + str(server.server_port) + '/held.jpg',
                    IMAGE_PRODUCER=str(self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-service-producer.py')))
                if not red:
                    self.check('notification-service-ready-has-retained-url', all(isinstance(row['cachedImage'], str)
                        and row['cachedImage'].startswith('file://') for step in result['snapshots'] for row in step['history']
                        if row['imageState'] == 'ready'), dict(stages=len(result['snapshots'])))
                    cold, cold_output = self.qt(source, self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-history.qml',
                        inputs, 'notification-history-cold', extra_env=dict(DBUS_SESSION_BUS_ADDRESS=actual,
                        ATMOSPHERA_NOTIF_HISTORY_FILE=str(inputs / 'history.json')))
            finally:
                guard.terminate()
                code = bus.wait(timeout=10)
                (self.out / 'bus-process.json').write_text(json.dumps(dict(identity=guard.identity.record(), exit=code), indent=2) + '\n')
                server.shutdown()
                thread.join(timeout=5)
                server.server_close()
                (self.out / 'http.json').write_text(json.dumps(http_events, indent=2) + '\n')
        self.check('actual-service-producer-retired-file', result['producerExit'] == 0 and not result['producerErrors']
                   and not (inputs / 'service-ephemeral.webp').exists(), result)
        if not red:
            self.check('notification-service-superseded-http-retired', len(http_events) == 2
                       and next(row for row in http_events if row['path'] == '/held.jpg')['eof']
                       and next(row for row in http_events if row['path'] == '/history.jpg')['delivered'], http_events)
            return self.notification_service_results(result, output, cold, cold_output, inputs, installed)
        self.check('actual-service-original-file-loss', result['popup']['status'] == result['history']['status'] == 3
                   and result['popup']['source'] == result['history']['source'] == result['entry']['originalImage']
                   and result['entry']['cachedImage'] == result['entry']['originalImage'], result, red=True)
        return result

    def notification_service_results(self, result, output, cold, cold_output, inputs, installed):
        snapshots = {row['stage']: row for row in result['snapshots']}
        required = ['file', 'metadata-only', 'replace-green', 'replace-blue', 'collision', 'compact', 'data', 'no-art', 'missing', 'corrupt', 'hidden',
                    'dnd', 'transient', 'blocked', 'no-owner', 'pending-clear', 'pending-dismiss', 'pending-remove',
                    'slow-superseded', 'transient-replacement', 'blocked-replacement', 'shared-one', 'shared-two', 'shared-remove',
                    'overflow-trigger', 'clear-with-popup', 'cold-provider', 'cold-file', 'closed']
        self.check('notification-service-complete-schedules', list(snapshots) == required, list(snapshots))
        self.check('notification-service-actual-native-control', result['raw'] == (1 if installed else 3), result['raw'])
        first = snapshots['file']['history'][0]
        green = snapshots['replace-green']['history'][0]
        blue = snapshots['replace-blue']['history'][0]
        self.check('notification-service-entry-revision-fence', first['id'] == green['id'] == blue['id']
                   and len({row['imageRevision'] for row in (first, green, blue)}) == 3
                   and len({row['cachedImage'] for row in (first, green, blue)}) == 3,
                   [first, green, blue])
        metadata = snapshots['metadata-only']['history'][0]
        self.check('notification-service-metadata-not-recapture', metadata['id'] == first['id']
                   and metadata['imageRevision'] == first['imageRevision'] and metadata['cachedImage'] == first['cachedImage']
                   and metadata['summary'] == 'Updated metadata', metadata)
        self.check('notification-service-original-and-representation', first['imageFormat'] == 'webp'
                   and first['cachedImage'].endswith('.webp') and first['imageRepresentation'].endswith('.png')
                   and first['cachedImage'] != first['imageRepresentation'], first)
        self.check('notification-service-equal-labels-no-alias', len(snapshots['collision']['history']) == 2
                   and len({row['id'] for row in snapshots['collision']['history']}) == 2
                   and len({row['cachedImage'] for row in snapshots['collision']['history']}) == 2
                   and len(snapshots['collision']['popup']) == 1, snapshots['collision'])
        # All rendered actual roots are checked, not just the owner callbacks.
        for stage, color in [('file', COLORS[0]), ('replace-green', (20, 210, 70, 255)), ('replace-blue', (30, 60, 230, 255)),
                             ('compact', COLORS[1]), ('data', COLORS[0])]:
            target = first['id'] if stage.startswith('replace') or stage == 'file' else next(
                row['id'] for row in snapshots[stage]['history'] if row['summary'] == stage)
            rows = [row for row in result['widgets'] if row['stage'] == stage and row['id'] == target]
            self.check('notification-service-' + stage + '-actual-pixels', {row['cohort'] for row in rows} == {'popup', 'history'}
                       and all(row['status'] == 1 and pixel(output / row['file']) == list(color) for row in rows), rows)
        for name in ('missing', 'corrupt'):
            data = next(row for row in snapshots[name]['history'] if row['summary'] == name)
            rows = [row for row in result['widgets'] if row['stage'] == name and row['id'] == data['id']]
            self.check('notification-service-' + name + '-labelled-failure', data['imageState'] == 'unavailable'
                       and not data['cachedImage'] and data['imageErrorCode'] and data['imageErrorReason']
                       and {row['cohort'] for row in rows} == {'popup', 'history'}
                       and all(row['status'] == 3 and row['error'] and row['reason'] for row in rows), rows)
            warning_pixels = []
            for row in rows:
                width, height, rgba = read_png(output / row['file'])
                warning_pixels.append(sum(rgba[i + 3] > 80 and all(abs(rgba[i + j] - result['warningColor'][j]) <= 3
                    for j in range(3)) for i in range(0, len(rgba), 4)))
            self.check('notification-service-' + name + '-visible-warning', all(warning_pixels), warning_pixels)
        for name in ('hidden', 'dnd'):
            row = snapshots[name]
            self.check('notification-service-' + name + '-history-only', any(r['summary'] == name for r in row['history'])
                       and not any(r['summary'] == name for r in row['popup'])
                       and next(r for r in row['history'] if r['summary'] == name)['imageState'] == 'ready', row)
        no_art = next(r for r in snapshots['no-art']['history'] if r['summary'] == 'no-art')
        self.check('notification-service-no-art-not-failure', no_art['imageState'] == 'idle'
                   and not no_art['originalImage'] and not no_art['cachedImage'] and not no_art['imageErrorCode'], no_art)
        self.check('notification-service-transient-popup-only', any(r['summary'] == 'transient' for r in snapshots['transient']['popup'])
                   and not any(r['summary'] == 'transient' for r in snapshots['transient']['history']), snapshots['transient'])
        for name in ('blocked', 'no-owner', 'pending-clear', 'pending-dismiss', 'pending-remove'):
            row = snapshots[name]
            self.check('notification-service-' + name + '-no-resurrection', not any(r['summary'] == name for r in row['popup'] + row['history'])
                       and not any(r['summary'] == name for r in row['owners']), row)
        admissions = {row['summary']: row for row in result['admissions']}
        self.check('notification-service-synchronous-failure-before-insert', admissions['missing']['state'] == 'unavailable'
                   and admissions['missing']['revision'], admissions['missing'])
        self.check('notification-service-no-unowned-admission', all(not admissions[name]['id'] and not admissions[name]['interestDelta']
                   for name in ('blocked', 'no-owner')), admissions)
        self.check('notification-service-pending-release', all(not admissions[name]['afterEntry']
                   and not admissions[name]['afterInterests'] for name in ('pending-clear', 'pending-dismiss', 'pending-remove')), admissions)
        slow = snapshots['slow-superseded']
        data = next(row for row in slow['history'] if row['summary'] == 'slow-superseded')
        rows = [row for row in result['widgets'] if row['stage'] == 'slow-superseded' and row['id'] == data['id']]
        changes = result['changes']
        previous_source = admissions['slow-start']['source']
        expected_revision = int(admissions['slow-start']['revision'].rsplit(':', 1)[1])
        consistent = bool(changes)
        for change in changes:
            if change['entrySource'] != previous_source:
                expected_revision += 1
            consistent &= change['entrySource'] == (change['image'] or change['appIcon'])
            consistent &= change['revision'] == data['id'] + ':' + str(expected_revision)
            previous_source = change['entrySource']
        self.check('notification-service-running-supersession', data['id'] == admissions['slow-start']['id']
                   and consistent and expected_revision > 1 and any(row['signal'] == 'imageChanged' for row in changes)
                   and data['imageRevision'] == changes[-1]['revision']
                   and data['originalImage'] == changes[-1]['entrySource'] == changes[-1]['image']
                   and len(rows) == 2 and all(row['status'] == 1 and pixel(output / row['file']) == [30, 60, 230, 255]
                   for row in rows), dict(changes=changes, widgets=rows))
        policy = snapshots['transient-replacement']
        history_id = admissions['history-held']['id']
        history = next(row for row in policy['history'] if row['id'] == history_id)
        popup = next(row for row in policy['popup'] if row['id'] == history_id)
        rows = [row for row in result['widgets'] if row['stage'] == 'transient-replacement' and row['id'] == history_id]
        self.check('notification-service-pending-history-revision-survives', history['imageRevision'] != popup['imageRevision']
                   and history['originalImage'].endswith('/history.jpg') and popup['originalImage'].startswith('image://')
                   and len(rows) == 2 and all(row['status'] == 1 and pixel(output / row['file']) ==
                   (list(COLORS[0]) if row['cohort'] == 'history' else [20, 210, 70, 255]) for row in rows), rows)
        blocked = snapshots['blocked-replacement']
        preserved = next(row for row in blocked['history'] if row['id'] == history_id)
        rows = [row for row in result['widgets'] if row['stage'] == 'blocked-replacement' and row['id'] == history_id]
        self.check('notification-service-blocked-replacement-keeps-history', preserved == history
                   and not any(row['id'] == history_id for row in blocked['popup']) and len(rows) == 1
                   and rows[0]['status'] == 1 and pixel(output / rows[0]['file']) == list(COLORS[0]), rows)
        for stage in ('shared-remove', 'overflow-trigger', 'clear-with-popup'):
            rows = [row for row in result['widgets'] if row['stage'] == stage and row['summary'] == 'shared-two' and row['cohort'] == 'popup']
            self.check('notification-service-' + stage + '-shared-bytes-survive', len(rows) == 1 and rows[0]['status'] == 1
                       and pixel(output / rows[0]['file']) == [230, 30, 50, 255], rows)
        persisted = json.loads((inputs / 'history.json').read_text())['notifications']
        self.check('notification-service-cold-records', {r['summary'] for r in persisted} == {'cold-provider', 'cold-file'}
                   and all(r['imageState'] == 'ready' and r['cachedImage'] != r['originalImage'] for r in persisted), persisted)
        self.check('notification-service-cold-actual-pixels', len(cold['widgets']) == 2 and all(row['status'] == 1
                   and pixel(cold_output / row['file']) == ([30, 60, 230, 255] if row['summary'] == 'cold-provider' else list(COLORS[0]))
                   for row in cold['widgets']), cold)
        self.check('notification-service-quiescence', result['interests'] == cold['interests'] == 0
                   and not result['worker'] and not cold['worker'] and not snapshots['closed']['popup'], snapshots['closed'])
        return result

    def red(self):
        args = self.args
        if args.baseline_source is None or args.baseline_plugins is None:
            raise ValueError('Red characterization requires exact baseline shell and plugins')
        packages = self.command(['pacman', '-Q', 'qt6-base', 'qt6-imageformats', 'imagemagick', 'ffmpeg', 'libwebp', 'libheif'])
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (args.qt_webp == 'present'), dict(installed=installed, packageReceipt=packages.stdout + packages.stderr))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (self.out / 'commands.json').write_text(json.dumps(self.commands, indent=2) + '\n')
        result, output = self.qt(args.baseline_source, args.source / 'Scripts/dev/fixtures/image-decoding/baseline.qml', inputs, 'baseline')
        maps = json.loads((output / 'process.json').read_text())['imagePlugins']
        self.check('fresh-qt-webp-reader-condition', any('libqwebp.so' in path for path in maps) == installed, maps)
        self.check('independent-png-consumer-control', result['png'] == 1 and result['pngTile']['imageReady']
                   and pixel(output / 'chooser-png.png') == list(COLORS[0]), dict(consumer=result['pngTile'], center=pixel(output / 'chooser-png.png')))
        if args.qt_webp == 'absent':
            self.check('raw-webp-unavailable', result['webp'] == result['motion'] == 3, result, red=True)
            self.check('chooser-webp-icon-not-preview', not result['webpTile']['imageReady']
                       and pixel(output / 'chooser-webp.png') != list(COLORS[0]), dict(consumer=result['webpTile'], center=pixel(output / 'chooser-webp.png')), red=True)
            self.check('quicklook-animated-webp-unavailable', result['quicklook'] == 'error'
                       and len({s['quickFrame'] for s in result['samples']}) == 1, result['samples'], red=True)
        else:
            self.check('native-webp-control', result['webp'] == result['motion'] == 1
                       and result['frames'] == 3 and len({s['nativeFrame'] for s in result['samples']}) == 3, result)
            observed = [pixel(path) for path in sorted(output.glob('quicklook-*.png'))]
            self.check('native-quicklook-rendered-motion-control', result['quicklook'] == 'ready'
                       and {tuple(p) for p in observed} == set(COLORS), observed)
            events = result['nativeEvents']
            self.check('native-frame-order-control', len(events) >= 6 and
                       all(b['frame'] == (a['frame'] + 1) % 3 for a, b in zip(events, events[1:])), events)
        conversion = result['conversion']
        promised = Path(conversion.get('path', ''))
        numbered = sorted(promised.parent.glob(promised.stem + '-*.png')) if conversion.get('path') else []
        self.check('wallpaper-numbered-output-false-success', conversion.get('called') and conversion.get('success')
                   and not promised.exists() and len(numbered) == 3,
                   dict(callback=conversion, exactExists=promised.exists(), numbered=[str(p) for p in numbered], setup=result['setup'], completions=result['completions']), red=True)
        setup_path = Path(result['setup']['cached'])
        self.check('setup-published-nonexistent-preview', bool(result['setup']['cached']) and not setup_path.exists()
                   and len(list(setup_path.parent.glob(setup_path.stem + '-*.png'))) == 3
                   and pixel(output / 'setup-wallpaper.png') != list(COLORS[0]),
                   dict(source=result['setup'], center=pixel(output / 'setup-wallpaper.png')), red=True)
        # Retain the actual old worker's image-seek failure as a separate red,
        # never confuse process exit 0 with production consumer success.
        data = self.out / 'old-worker-output.png'
        with data.open('wb') as stream:
            argv = ['ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-ss', '0', '-i', str(inputs / 'Motion.webp'),
                    '-frames:v', '1', '-vf', 'scale=128:128:force_original_aspect_ratio=decrease', '-threads', '1',
                    '-pix_fmt', 'rgba', '-f', 'image2pipe', '-c:v', 'png', 'pipe:1']
            proc = subprocess.run(argv, stdout=stream, stderr=subprocess.PIPE, timeout=30)
        detail = dict(argv=argv, exit=proc.returncode, bytes=data.stat().st_size, stderr=proc.stderr.decode(errors='replace'))
        self.check('ffmpeg-image-seek-zero-output', proc.returncode == 0 and data.stat().st_size == 0, detail, red=True)
        for extension in ('avif', 'heic', 'tiff'):
            normalized = self.out / ('delegate-control-' + extension + '.png')
            decoded = self.command(['magick', str(inputs / ('Still.' + extension)) + '[0]', 'PNG32:' + str(normalized)])
            center = pixel(normalized) if decoded.returncode == 0 and normalized.exists() else None
            self.check('fixture-delegate-' + extension, center is not None and
                       max(abs(a - b) for a, b in zip(center, COLORS[0])) <= 8, dict(center=center, expected=COLORS[0]))
        return result

    def desktop_wallpaper(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        result, output = self.qt(self.args.baseline_source or self.args.source, self.args.source/'Scripts/dev/fixtures/image-decoding/desktop-wallpaper.qml',
                                 inputs, 'desktop-wallpaper', dict(IMAGE_DESKTOP_RED='1' if self.args.baseline_source else '0'))
        if self.args.baseline_source:
            self.check('desktop-acknowledged-before-qt-presentation', any(not row['visible'] or row['transitioning']
                       for row in result['completions']), result, red=True)
            return result
        self.check('desktop-wallpaper-actual-fixture-configuration', result['effective'] == dict(overviewBlur=0, overviewTint=0,
                   transitionDuration=200), result['effective'])
        for endpoint in ('desktop', 'overview'):
            for name in ('valid', 'invalid', 'newest'):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check('desktop-wallpaper-'+endpoint+'-'+name, center == list(COLORS[0]), center)
            width, height, rgba = read_png(output/('valid-'+endpoint+'.png'))
            edge = list(rgba[(height//2*width+width//16)*4:(height//2*width+width//16)*4+4])
            self.check('desktop-wallpaper-'+endpoint+'-transparent-edge', edge[3] <= 10, edge)
            for index, name in enumerate(('none','fade','wipe','disc','stripes','pixelate','honeycomb')):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check('desktop-wallpaper-'+endpoint+'-'+name, center == list(COLORS[index % 2 + 1]), center)
            for name in ('solid', 'solid-invalid'):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check('desktop-wallpaper-'+endpoint+'-'+name, center == [18,52,86,255], center)
            self.check('desktop-wallpaper-'+endpoint+'-retained-complete-texture',
                       read_png(output/('valid-'+endpoint+'.png')) == read_png(output/('invalid-'+endpoint+'.png'))
                       and read_png(output/('solid-'+endpoint+'.png')) == read_png(output/('solid-invalid-'+endpoint+'.png')),
                       dict(imageBefore='valid', imageAfter='invalid', solidBefore='solid', solidAfter='solid-invalid'))
        self.check('desktop-wallpaper-explicit-static-representation', all(row['result'].get('frames') == 1
                   and row['result'].get('format') == 'png' for row in result['snapshots'] if row['name'] in ('valid','newest')),
                   [row for row in result['snapshots'] if row['name'] in ('valid','newest')])
        checks = []
        for index, row in enumerate(result['completions']):
            name = Path(row['path']).name
            expected = ([18,52,86,255] if row['path'].startswith('solid:') else list(COLORS[0]) if name == 'Motion.webp'
                        else list(COLORS[int(name[6])]) if name.startswith('frame-') else None)
            capture = output/('ack-'+str(index)+'.png')
            observed = pixel(capture) if capture.is_file() else None
            checks.append(dict(event=row, observed=observed, expected=expected))
        self.check('desktop-wallpaper-acknowledgment-after-presented-ready', len(checks) >= 9
                   and all(row['observed'] == row['expected'] and not row['event']['transitioning'] for row in checks), checks)
        self.check('desktop-wallpaper-failure-reason', all(row['reason'] for row in result['snapshots']
                   if row['name'] in ('invalid','solid-invalid')), result['snapshots'])
        self.check('desktop-wallpaper-destruction-retires-all-interests', result['interests'] == result['requests'] == 0
                   and not result['workerRunning'], result)
        return result

    def wallpaper_gallery(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                mapping = {'/motion.jpg':'Motion.webp', '/bad.jpg':'Corrupt.webp', '/heic.jpg':'Still.heic'}
                name = mapping.get(self.path)
                if not name:
                    self.send_error(404)
                    return
                data = (inputs/name).read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.baseline_source or self.args.source,
                self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-gallery.qml', inputs, 'wallpaper-gallery',
                dict(IMAGE_GALLERY_URL='http://127.0.0.1:'+str(server.server_port)))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        (self.out/'http-requests.json').write_text(json.dumps(requests,indent=2)+'\n')
        for cohort in ('local','remote'):
            motion = [row for row in result['snapshots'] if row['cohort'] == cohort and row['index'] == 0]
            centers = [pixel(path) for path in output.glob(cohort+'-image-0-*.png')]
            self.check('wallpaper-gallery-'+cohort+'-static-frame-zero',len(motion) == 11
                       and all(row['status'] == 1 and row['result']['frames'] == 1 for row in motion)
                       and centers == [list(COLORS[0])]*11, dict(rows=motion,centers=centers))
            heic = [row for row in result['snapshots'] if row['cohort'] == cohort and row['index'] == 2]
            heic_pixels = [pixel(path) for path in output.glob(cohort+'-image-2-*.png')]
            self.check('wallpaper-gallery-'+cohort+'-heic-pixels',len(heic) == 1 and heic[0]['status'] == 1
                       and len(heic_pixels) == 1 and max(abs(a-b) for a,b in zip(heic_pixels[0],COLORS[0])) <= 8,heic)
            failed = [row for row in result['snapshots'] if row['cohort'] == cohort and row['index'] == 1]
            self.check('wallpaper-gallery-'+cohort+'-honest-failure',len(failed) == 1 and failed[0]['status'] == 3
                       and failed[0]['reason'],failed)
            width,height,pixels = read_png(output/(cohort+'-failure-tile.png'))
            warning_pixels = sum(max(abs(a-b) for a,b in zip(pixels[i:i+4],result['warningColor'])) < 8
                                 for i in range(0,len(pixels),4))
            self.check('wallpaper-gallery-'+cohort+'-unobscured-warning',warning_pixels > 10,
                       dict(pixels=warning_pixels,color=result['warningColor'],width=width,height=height))
        self.check('wallpaper-gallery-real-http-misleading-types',set(requests) == {'/motion.jpg','/bad.jpg','/heic.jpg'},requests)
        self.check('wallpaper-gallery-close-retires-all-interests',result['interests'] == result['requests'] == 0
                   and not result['workerRunning'],result)
        return result

    def wallpaper_scan(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        names = ['Still.webp', 'Still.avif', 'Still.heic', 'Still.tiff', 'frame-0.png']
        pool_name = 'pool "quoted" [literal] ü:dir'
        special_names = [' space .png', 'pipe|name.png', 'line\nbreak.png', '-leading.png']
        for directory in ('scan-main', 'pool-simple', pool_name, 'scan-next', 'browse-only', 'empty'):
            (inputs/directory).mkdir()
        for name in names:
            shutil.copyfile(inputs/name, inputs/'pool-simple'/name)
        for name in special_names:
            shutil.copyfile(inputs/'frame-0.png', inputs/pool_name/name)
        shutil.copyfile(inputs/'frame-0.png', inputs/'scan-main/main.png')
        shutil.copyfile(inputs/'frame-1.png', inputs/'scan-next/next.png')
        shutil.copyfile(inputs/'frame-2.png', inputs/'browse-only/browse.png')
        (inputs/'pool-simple/trap.png').mkdir()
        shim = self.work/'scan-scheduling'
        shim.mkdir()
        executable = shim/'find'
        executable.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
with open(os.environ['IMAGE_SCAN_ARGV'], 'a') as stream:
    stream.write(json.dumps(dict(pid=os.getpid(), argv=args))+'\\n')
if any(pathlib.Path(arg).name == 'scan-main' for arg in args):
    time.sleep(.7)
os.execv('/usr/bin/find', ['find', *args])
''')
        executable.chmod(0o755)
        argv_log = self.out/'scan-argv.jsonl'
        source = self.args.baseline_source or self.args.source
        result, output = self.qt(source, self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-scan.qml',
                                 inputs, 'wallpaper-scan', dict(PATH=str(shim)+':'+os.environ['PATH'],
                                 IMAGE_SCAN_ARGV=str(argv_log), IMAGE_SCAN_POOL=pool_name,
                                 IMAGE_SCAN_BASELINE='1' if self.args.baseline_source else '0'))
        stages = {row['name']:row for row in result['snapshots']}
        expected = {str(inputs/'scan-main/main.png'), *(str(inputs/'pool-simple'/name) for name in names)}
        self.check('wallpaper-scan-publishes-complete-main-pool-union', set(stages['union']['paths']) == expected,
                   stages['union'])
        self.check('wallpaper-scan-browse-never-cancels-publication', set(stages['browse']['paths']) == expected
                   and result['browse'] == [str(inputs/'browse-only/browse.png')], result)
        special = {str(inputs/pool_name/name) for name in special_names}
        self.check('wallpaper-scan-literal-argv-preserves-all-path-bytes', set(stages['literal']['paths']) == expected | special,
                   stages['literal'])
        self.check('wallpaper-scan-new-refresh-retires-old-union', stages['latest']['paths'] == [str(inputs/'scan-next/next.png')],
                   stages['latest'])
        self.check('wallpaper-scan-empty-refresh-settles', not stages['empty']['paths'], stages['empty'])
        self.check('wallpaper-scan-counts-settle-without-negative-values', all(row['count'] >= 0 for row in result['counts'])
                   and all(row['count'] == 0 for row in result['snapshots']), result['counts'])
        self.check('wallpaper-scan-union-publishes-once', all(sum(event['stage'] == stage for event in result['events']) == 1
                   for stage in (1,2,3,4,5)), result['events'])
        rows = [json.loads(line) for line in argv_log.read_text().splitlines()]
        self.check('wallpaper-scan-real-find-literal-arguments', any(str(inputs/pool_name) in row['argv'] for row in rows)
                   and all('sh' not in row['argv'] and '-c' not in row['argv'] for row in rows), rows)
        self.check('wallpaper-scan-owned-processes-retired', all(not Path('/proc/'+str(row['pid'])).exists() for row in rows), rows)
        return result

    def wallpaper_wizard(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        # The real none deployment must be inapplicable, not able to modify a
        # guest-global keyd layer or stop an existing xremap service.
        self.check('wizard-neutral-deployment-prerequisites', not Path('/etc/keyd/atmosphera').exists()
                   and not Path('/etc/keyd/atmosphera').is_symlink()
                   and self.command(['systemctl', '--user', 'show', 'xremap-atmosphera.service',
                                     '-p', 'LoadState', '--value']).stdout.strip() == 'not-found', {})
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        data = (inputs/'Still.webp').read_bytes()
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                time.sleep(1)
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Content-Type', 'image/jpeg')
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.source, self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-wizard.qml',
                inputs, 'wallpaper-wizard', dict(IMAGE_WIZARD_RED='1' if self.args.case == 'wizard-red' else '0',
                IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}', NIRI_SOCKET=''))
            if self.args.case != 'wizard-red':
                extra, extra_output = self.qt(self.args.source, self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-wizard.qml',
                    inputs, 'wallpaper-wizard-extra', dict(IMAGE_WIZARD_EXTRA='1',
                    IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}', NIRI_SOCKET=''))
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        (self.out/'http-requests.json').write_text(json.dumps(requests, indent=2)+'\n')
        stages = {row['name']: row for row in result['snapshots']}
        if self.args.case == 'wizard-red':
            self.check('old-wizard-saves-corrupt-unaccepted-wallpaper', stages['red']['request']['status'] == 'Succeeded'
                       and stages['red']['path'] == str(inputs/'frame-1.png') and stages['red']['scale'] == 1.15,
                       result, red=True)
            return result
        self.check('wizard-submission-is-captured-before-admission', result['immediate']['status']['status'] == 'Running'
                   and result['immediate']['path'] == str(inputs/'frame-1.png')
                   and result['captured']['scaleRatio'] == 1.15 and result['captured']['wallpaper'] == str(inputs/'Motion.webp'), result['immediate'])
        valid = stages['valid']
        self.check('wizard-save-follows-accepted-source-and-keeps-captured-values', valid['request']['status'] == 'Succeeded'
                   and valid['path'] == str(inputs/'Motion.webp') and valid['scale'] == 1.15
                   and valid['bar'] == 'bottom' and pixel(output/'valid.png') == list(COLORS[0]), valid)
        self.check('wizard-failed-image-retains-head-with-no-setup-save', stages['failed']['request']['status'] == 'Stopped'
                   and stages['failed']['request']['error'] == 'setup-wallpaper-unavailable'
                   and stages['failed']['scale'] == 1.15
                   and not any(row['stage'] == 3 and row['result']['status'] in ('saved', 'nothing_to_save') for row in result['saves']), stages['failed'])
        retry = stages['retry']
        self.check('wizard-retry-reuses-captured-work-after-source-repair', retry['request']['attemptId'] == 2
                   and retry['request']['status'] == 'Succeeded' and retry['scale'] == 1.25
                   and retry['path'] == str(inputs/'Retry.webp') and pixel(output/'retry.png') == list(COLORS[0]), retry)
        failed_id = stages['failed']['request']['id']
        ordered = [row for row in result['terminals'] if row['id'] != 'bindings-1']
        self.check('wizard-failed-head-blocks-later-fifo-request', len(ordered) >= 4
                   and [row['success'] for row in ordered[:4]] == [True, False, True, True]
                   and ordered[1]['id'] == ordered[2]['id'] == failed_id, ordered)
        superseded = stages['superseded']
        self.check('wizard-superseded-admission-settles-without-saving', superseded['request']['error'] == 'setup-wallpaper-superseded'
                   and superseded['scale'] == 1.25, superseded)
        self.check('wizard-reopen-restores-retained-capture-and-service-owned-retry', result['restored']['id'] == superseded['request']['id']
                   and result['restored']['scale'] == 1.35 and result['restored']['wallpaper'].endswith('/slow.jpg')
                   and stages['reopened']['request']['status'] == 'Succeeded' and stages['reopened']['scale'] == 1.35
                   and pixel(output/'reopened.png') == list(COLORS[0]), result['restored'])
        self.check('wizard-destruction-does-not-abandon-captured-preparation', stages['detached']['request']['id'] == result['detached']
                   and stages['detached']['request']['status'] == 'Succeeded' and stages['detached']['scale'] == 1.45
                   and pixel(output/'detached.png') == list(COLORS[0]), stages['detached'])
        extra_stages = {row['name']: row for row in extra['snapshots']}
        self.check('wizard-partial-target-admission-is-not-captured-success', extra_stages['partial']['request']['status'] == 'Stopped'
                   and extra_stages['partial']['request']['error'] == 'setup-wallpaper-superseded'
                   and extra_stages['partial']['scale'] == 1 and extra_stages['partial']['other'].endswith('/partial.jpg')
                   and extra_stages['all-targets']['request']['attemptId'] == 2 and extra_stages['all-targets']['scale'] == 1.55
                   and pixel(extra_output/'all-targets.png') == list(COLORS[0]), extra_stages['partial'])
        self.check('wizard-no-wallpaper-selection-still-saves-captured-setup', extra_stages['no-selection']['request']['status'] == 'Succeeded'
                   and extra_stages['no-selection']['request']['work']['wallpaper'] == '' and extra_stages['no-selection']['scale'] == 1.65
                   and extra_stages['no-selection']['path'] == extra_stages['all-targets']['path']
                   and read_png(extra_output/'no-selection.png') == read_png(extra_output/'all-targets.png'), extra_stages['no-selection'])
        self.check('wallpaper-retirement-settles-once-with-legacy-callback-suppressed', not result['legacy']
                   and len(result['settlements']) == 2 and result['settlements'][0]['state'] == 'cancelled'
                   and result['settlements'][1]['detail']['code'] == 'empty-source', result['settlements'])
        for label, observed in (('main', result), ('partial', extra)):
            rows = observed['reentrantSettlements']
            self.check('wallpaper-reentrant-retirement-'+label, len(rows) == 4
                       and {row['name'] for row in rows} == {'first', 'other', 'superseding', 'latest'}
                       and all(row['outcome']['state'] == 'cancelled' for row in rows), rows)
        tuples = [(row['id'], row['attempt']) for row in result['terminals']]
        self.check('wizard-attempts-settle-exactly-once', len(tuples) == len(set(tuples)), tuples)
        config = self.work/'wallpaper-wizard-extra-profile/config/settings'
        native = {name: json.loads((config/(name+'.json')).read_text()) for name in ('general', 'bar', 'wallpaper', 'bindings')}
        (self.out/'native-settings.json').write_text(json.dumps(native, indent=2)+'\n')
        self.check('wizard-native-settings-readback-matches-final-captured-work', native['general']['scaleRatio'] == 1.65
                   and native['bar']['position'] == 'bottom' and native['wallpaper']['directory'] == str(inputs)
                   and native['bindings']['environment'] == 'none', native)
        self.check('wizard-source-native-package-control', result['raw'] == (1 if installed else 3), result['raw'])
        self.check('wizard-final-quiescence', result['interests'] == result['requests'] == result['queue'] == 0
                   and result['state'] == 'Idle' and not result['workerRunning']
                   and extra['interests'] == extra['requests'] == extra['queue'] == 0
                   and extra['state'] == 'Idle' and not extra['workerRunning'], dict(main=result, extra=extra))
        return result

    def wallpaper_setup(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        result, output = self.qt(self.args.source, self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-setup.qml',
                                 inputs, 'wallpaper-setup')
        stages = {row['name']:row for row in result['snapshots']}
        self.check('setup-failed-source-never-retries-original', stages['failed']['cached'] == stages['before']['cached']
                   and read_png(output/'before.png') == read_png(output/'failed.png'), stages['failed'])
        self.check('setup-static-preview-is-exact-single-output', Path(stages['before']['cached']).is_file()
                   and not list(Path(stages['before']['cached']).parent.glob(Path(stages['before']['cached']).stem+'-*.png'))
                   and pixel(output/'before.png') == list(COLORS[0]), stages['before'])
        self.check('setup-failure-is-explicit', stages['failed']['state'] == 'unavailable' and stages['failed']['reason'], stages['failed'])
        warning = stages['failed']['warning']
        width,height,pixels = read_png(output/'failed-screen.png')
        count = sum(max(abs(a-b) for a,b in zip(pixels[(y*width+x)*4:(y*width+x+1)*4],result['warningColor'])) < 8
                    for y in range(max(0,int(warning['y'])),min(height,int(warning['y']+warning['height'])+1))
                    for x in range(max(0,int(warning['x'])),min(width,int(warning['x']+warning['width'])+1))) if warning else 0
        self.check('setup-warning-is-presented-next-to-retained-preview', warning and warning['visible'] and count > 10,
                   dict(warning=warning,pixels=count))
        self.check('setup-replacement-fences-stale-completion', stages['latest']['state'] == 'ready'
                   and pixel(output/'latest.png') == list(COLORS[1]), stages['latest'])
        self.check('setup-invalid-user-intent-retains-selection-and-preview', stages['invalid-intent']['selected'] == stages['latest']['selected']
                   and stages['invalid-intent']['state'] == 'unavailable' and stages['invalid-intent']['reason']
                   and read_png(output/'invalid-intent.png') == read_png(output/'latest.png'), stages['invalid-intent'])
        self.check('setup-emits-only-validated-user-selection', result['selections'] == [str(inputs/'Still.webp')]
                   and stages['valid-intent']['selected'] == str(inputs/'Still.webp')
                   and pixel(output/'valid-intent.png') == list(COLORS[0]), result['selections'])
        self.check('setup-gallery-is-static-frame-zero', len(result['galleryFrames']) == 11
                   and all(row['status'] == 1 and row['result']['frames'] == 1 for row in result['galleryFrames'])
                   and all(pixel(path) == list(COLORS[0]) for path in output.glob('gallery-*.png')), result['galleryFrames'])
        self.check('setup-destruction-retires-all-interests', result['interests'] == result['requests'] == 0 and not result['workerRunning'], result)
        return result

    def wallpaper_admission(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding/wallpaper-admission.qml'
        result, output = self.qt(self.args.source, fixture, inputs, 'wallpaper-admission')
        stages = {row['name']: row for row in result['snapshots']}
        valid = stages['valid']
        self.check('wallpaper-failed-selection-never-publishes', stages['invalid']['path'] == valid['path']
                   and not any(row['path'].endswith(('Corrupt.webp', 'Missing.webp')) for row in result['events']), result)
        self.check('wallpaper-validation-precedes-publication', result['immediatePath'] == ''
                   and valid['path'] == str(inputs/'Motion.webp') and valid['state'] == 'ready', valid)
        self.check('wallpaper-static-multiframe-exact-pixels', pixel(output/'valid.png') == list(COLORS[0]), valid)
        for name in ('invalid', 'invalid-favorite'):
            row = stages[name]
            self.check('wallpaper-'+name+'-retains-state-and-pixels', row['path'] == valid['path']
                       and row['favorites'] == result['beforeFavorites'] and row['theme'] == result['beforeTheme']
                       and read_png(output/(name+'.png')) == read_png(output/'valid.png'), row)
        self.check('wallpaper-latest-generation-only', stages['latest']['path'] == str(inputs/'frame-1.png')
                   and pixel(output/'latest.png') == list(COLORS[1])
                   and not any(row['tick'] < 80 and row['path'].endswith('frame-2.png') for row in result['events']), result['events'])
        self.check('wallpaper-cancellation-retires-publication-and-callback', stages['cancelled']['path'] == stages['latest']['path']
                   and not result['callbacks'] and read_png(output/'cancelled.png') == read_png(output/'latest.png'), result)
        independent = stages['independent']
        self.check('wallpaper-independent-screen-and-appearance', independent['other'] == str(inputs/'frame-0.png')
                   and independent['dark'] == str(inputs/'frame-2.png') and independent['path'] == stages['latest']['path'], independent)
        favorite = stages['valid-favorite']
        self.check('wallpaper-favorite-admits-after-validation', favorite['path'] == str(inputs/'Still.webp')
                   and any(row['path'] == str(inputs/'Still.webp') for row in json.loads(favorite['favorites']))
                   and pixel(output/'valid-favorite.png') == list(COLORS[0]), favorite)
        self.check('wallpaper-solid-retires-pending-image', stages['solid']['solid']
                   and not any(row['tick'] >= 140 and row['path'].endswith('frame-2.png') for row in result['events']), stages['solid'])
        self.check('wallpaper-admission-quiescence', result['interests'] == result['requests'] == 0
                   and not result['workerRunning'], result)
        failure_notices = [row for row in result['notices'] if 20 <= row['tick'] < 60]
        self.check('wallpaper-failure-is-user-visible-not-success', len(failure_notices) == 2
                   and all(row['type'] == 'error' and row['title'] and row['reason'] for row in failure_notices), result['notices'])
        shim = self.work/'empty-decoders'
        shim.mkdir()
        for name in ('magick', 'ffmpeg'):
            executable = shim/name
            executable.write_text('#!/bin/sh\nexit 0\n')
            executable.chmod(0o755)
        rejected, rejected_output = self.qt(self.args.source,
            self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-rejection.qml', inputs,
            'wallpaper-no-output', dict(PATH=str(shim)+':'+os.environ['PATH'], IMAGE_USE_ORIGINAL='1'))
        self.check('wallpaper-zero-exit-no-output-never-publishes-success', not rejected['completions'] and not rejected['events']
                   and rejected['path'] == str(inputs/'frame-0.png') and not rejected['favorites']
                   and len(rejected['callbacks']) == 1 and not rejected['callbacks'][0]['success']
                   and rejected['callbacks'][0]['detail']['reason'], rejected)
        self.check('wallpaper-zero-exit-keeps-prior-rendered-pixels', pixel(rejected_output/'after.png') == list(COLORS[0])
                   and read_png(rejected_output/'before.png') == read_png(rejected_output/'after.png'), rejected)
        self.check('wallpaper-zero-exit-failure-visible-and-quiescent', len(rejected['notices']) == 2
                   and all(row['type'] == 'error' and row['reason'] for row in rejected['notices'])
                   and rejected['interests'] == rejected['requests'] == 0 and not rejected['workerRunning'], rejected)
        return result

    def rounded(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding/rounded.qml'
        result, output = self.qt(self.args.source, fixture, inputs, 'rounded')
        for name in ('still','data'):
            self.check('rounded-'+name+'-shader-pixels', result[name]['status'] == 1 and pixel(output/(name+'.png')) == list(COLORS[0]), result[name])
            self.check('rounded-'+name+'-alpha-geometry', pixel(output/(name+'.png'),0,0)[3] == 0, pixel(output/(name+'.png'),0,0))
        centers = [pixel(path) for path in output.glob('motion-*.png')]
        self.check('rounded-animated-webp-presents-all-frames', result['motion']['status'] == 1
                   and {tuple(p) for p in centers} == set(COLORS), dict(consumer=result['motion'],centers=centers))
        self.check('rounded-failure-is-labelled-not-ordinary-icon', result['failure']['status'] == 3 and result['failure']['reason'], result['failure'])
        width,height,pixels = read_png(output/'failure.png')
        warning_pixels = sum(max(abs(a-b) for a,b in zip(pixels[(y*width+x)*4:(y*width+x+1)*4],result['warningColor'])) < 8
                             for y in range(height//2,height) for x in range(width//2,width))
        self.check('rounded-error-warning-is-actually-presented',warning_pixels > 10,dict(pixels=warning_pixels,color=result['warningColor']))
        for name in ('fit','crop','stretch'):
            path = output/(name+'.png')
            centers = [pixel(path,x,64) for x in (16,64,112)]
            self.check('rounded-'+name+'-single-transform-geometry', centers == ([list(COLORS[1])]*3 if name == 'crop' else [list(c) for c in COLORS])
                       and pixel(path,0,0)[3] == 0 and pixel(path,64,16)[3] == (0 if name == 'fit' else 255),
                       dict(centers=centers,corner=pixel(path,0,0),top=pixel(path,64,16)))
        reduced, reduced_output = self.qt(self.args.source, fixture, inputs, 'rounded-reduced',dict(IMAGE_ROUNDED_REDUCED='1'))
        centers = [pixel(path) for path in reduced_output.glob('motion-*.png')]
        self.check('rounded-reduced-motion-retains-animation-data', reduced['motion']['status'] == 1
                   and reduced['motion']['result']['frames'] == 3 and len({tuple(p) for p in centers}) == 1, reduced['motion'])
        stage = self.work/'locker-stage'
        packaged = self.command(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', self.args.source],
            env=dict(os.environ,srcdir=str(self.args.source.parent),_gitname=self.args.source.name,
                     pkgdir=str(stage),pkgver=(self.args.source/'VERSION').read_text().strip()))
        self.check('rounded-locker-package-assembly',packaged.returncode == 0,dict(exit=packaged.returncode,stderr=packaged.stderr))
        lock = stage/'etc/xdg/quickshell/atmosphera-lockscreen'
        locked, locked_output = self.qt(lock,fixture,inputs,'rounded-locker',assembled=True)
        centers = [pixel(path) for path in locked_output.glob('motion-*.png')]
        self.check('rounded-installed-locker-shader-motion', locked['motion']['status'] == 1
                   and {tuple(p) for p in centers} == set(COLORS)
                   and pixel(locked_output/'data.png') == list(COLORS[0])
                   and locked['failure']['status'] == 3 and locked['failure']['reason'], locked)
        return result

    def backdrops(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding/backdrops.qml'
        result, output = self.qt(self.args.source, fixture, inputs, 'backdrops')
        def review(observed, captures, prefix):
            for name in ('backdrop', 'lock'):
                before, failed, replacement = [stage[name] for stage in observed['stages']]
                center = pixel(captures / ('before-' + name + '.png'))
                self.check(prefix + name + '-initial-pixels', before['resolved'] and center[0] > 100
                           and center[0] > 3*center[1] and center[0] > 2*center[2], dict(consumer=before, center=center))
                self.check(prefix + name + '-failure-retains-presented-image', failed['resolved'] == before['resolved']
                           and read_png(captures/('before-'+name+'.png')) == read_png(captures/('failed-'+name+'.png')), failed)
                self.check(prefix + name + '-explicit-error', failed['state'] == 'unavailable' and failed['reason'], failed)
                next_center = pixel(captures/('replacement-'+name+'.png'))
                self.check(prefix + name + '-latest-generation-pixels', replacement['state'] == 'ready'
                           and next_center[1] > 80 and next_center[1] > 3*next_center[0] and next_center[1] > 2*next_center[2],
                           dict(consumer=replacement, center=next_center))
            self.check(prefix + 'hide-retires-interests', observed['interests'] == observed['requests'] == 0 and not observed['workerRunning'], observed)
        review(result, output, 'backdrops-')
        initial, initial_output = self.qt(self.args.source, fixture, inputs, 'backdrops-initial-error', dict(IMAGE_INITIAL_BAD='1'))
        for name in ('backdrop', 'lock'):
            before = initial['stages'][0][name]
            self.check('backdrops-' + name + '-startup-error-is-explicit', not before['resolved'] and before['state'] == 'unavailable'
                       and before['reason'], before)
        self.check('backdrops-lock-startup-error-safe-solid', pixel(initial_output/'before-lock.png')[:3] == [0,0,0],
                   pixel(initial_output/'before-lock.png'))
        self.check('backdrops-error-does-not-take-input-focus', initial['inputFocused'] and initial['inputText'] == 'unlock-input-control', initial)
        stage = self.work / 'locker-stage'
        packaged = self.command(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', self.args.source],
            env=dict(os.environ, srcdir=str(self.args.source.parent), _gitname=self.args.source.name,
                     pkgdir=str(stage), pkgver=(self.args.source / 'VERSION').read_text().strip()))
        self.check('backdrops-locker-package-assembly', packaged.returncode == 0, dict(exit=packaged.returncode,stderr=packaged.stderr))
        lock = stage / 'etc/xdg/quickshell/atmosphera-lockscreen'
        self.check('backdrops-locker-minimal-graph', not (lock/'Services/Plugins').exists() and not (lock/'Portals').exists(),str(lock))
        locked, locked_output = self.qt(lock, fixture, inputs, 'backdrops-locker', assembled=True)
        review(locked, locked_output, 'backdrops-installed-')
        return result

    def legacy(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/legacy.qml', inputs, 'legacy')
        for reader in result['readers']:
            name = reader['name']
            row = result['results'][name]
            path = Path(row['path'])
            self.check('legacy-' + name + '-exact-output', row['success'] and path.is_file()
                       and path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
                       and not list(path.parent.glob(path.stem + '-*.png')), row)
            self.check('legacy-' + name + '-presented-pixels', reader['status'] == 1
                       and max(abs(a-b) for a,b in zip(pixel(output / (name + '.png')), COLORS[0])) <= 8, reader)
        avatar = Path(result['results']['avatar']['path'])
        self.check('legacy-circular-avatar-alpha', pixel(avatar, 0, 0)[3] == 0 and pixel(avatar)[3] == 255,
                   dict(corner=pixel(avatar, 0, 0), center=pixel(avatar)))
        for name in ('corrupt', 'missing'):
            row = result['results'][name]
            self.check('legacy-' + name + '-honest-failure', not row['success'] and not row['path']
                       and bool(row['detail'].get('reason')), row)
        self.check('legacy-signals-are-validated-only', len(result['completions']) == 5 and len(result['failures']) == 2, result)
        self.check('legacy-completion-retires-interests', result['interests'] == result['requests'] == 0 and not result['workerRunning'], result)
        self.check('legacy-cancelled-callback-is-retired', not result['cancelledCallback'], result['cancelledCallback'])
        # Actual adapter requests with fixture-private executables that return
        # zero without their promised output. No production failure switches.
        for mode in ('magick-empty', 'all-empty'):
            shim = self.work / mode
            shim.mkdir()
            for name in (('magick',) if mode == 'magick-empty' else ('magick', 'ffmpeg')):
                executable = shim / name
                executable.write_text('#!/bin/sh\nexit 0\n')
                executable.chmod(0o755)
            failed, failed_output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/legacy.qml',
                inputs, 'legacy-' + mode, dict(PATH=str(shim) + ':' + os.environ['PATH']))
            if mode == 'magick-empty':
                for reader in failed['readers']:
                    name = reader['name']
                    row = failed['results'][name]
                    self.check('legacy-independent-decoder-' + name, row['success'] and row['detail']['decoder'] == 'ffmpeg'
                               and reader['status'] == 1 and max(abs(a-b) for a,b in zip(pixel(failed_output/(name+'.png')),COLORS[0])) <= 8, row)
                self.check('legacy-independent-circle-alpha', pixel(Path(failed['results']['avatar']['path']),0,0)[3] == 0, failed['results']['avatar'])
            else:
                self.check('legacy-no-output-is-never-success', all(not row['path'] and not row['success']
                           and row['detail'].get('reason') for row in failed['results'].values())
                           and not failed['completions'] and len(failed['failures']) == 7, failed)
            self.check('legacy-' + mode + '-quiescence', failed['interests'] == failed['requests'] == 0
                       and not failed['workerRunning'] and not failed['cancelledCallback'], failed)
        original, original_output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/legacy.qml',
            inputs, 'legacy-original', dict(IMAGE_USE_ORIGINAL='1'))
        large = original['results']['large']
        self.check('legacy-original-option-still-proves-presentation', large['success'] and Path(large['path']).is_file()
                   and large['detail']['origin'] == ('native' if installed else 'fallback')
                   and pixel(original_output/'large.png') == list(COLORS[0])
                   and original['interests'] == original['requests'] == 0 and not original['workerRunning'], large)
        return result

    def chooser(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/chooser.qml', inputs, 'chooser')
        self.check('chooser-off-is-idle', result['initialInterests'] == 0, result['initialInterests'])
        for row in result['tiles']:
            width, height, pixels = read_png(output / (row['id'] + '.png'))
            count = sum(max(abs(a - b) for a, b in zip(pixels[i:i + 4], COLORS[0])) <= 8 for i in range(0, len(pixels), 4))
            self.check(row['id'], row['state']['imageReady'] and count > 50,
                       dict(consumer=row, observedPixels=count, captureSize=[width, height]))
        for row in result['failures']:
            self.check(row['id'], row['state'].get('unavailable') and bool(row['state'].get('errorReason'))
                       and not row['state']['imageReady'], row)
        self.check('chooser-recognized-images-reach-preview', all(kind in ('image', 'animatedImage') for kind in result['kinds']), result['kinds'])
        colors = [pixel(path) for path in output.glob('quicklook-*.png')]
        self.check('chooser-quicklook-preserves-animation', result['quicklook']['previewState'] == 'ready'
                   and result['quicklook']['frames'] == 3 and len({r['frame'] for r in result['frames']}) == 3
                   and {tuple(p) for p in colors} == set(COLORS), dict(consumer=result['quicklook'], colors=colors, frames=result['frames']))
        self.check('chooser-close-retires-interests', result['finalInterests'] == 0 and not result['workerRunning'], result)
        video = inputs / 'Shared.mp4'
        encoded = self.command(['ffmpeg', '-nostdin', '-v', 'error', '-loop', '1', '-i', str(inputs / 'frame-0.png'),
            '-t', '1', '-c:v', 'libx264', '-threads', '1', '-pix_fmt', 'yuv420p', str(video)])
        if encoded.returncode:
            raise AssertionError('Independent video fixture encoding failed')
        shim = self.work / 'picker-bin'
        shim.mkdir()
        probe = shim / 'ffprobe'
        probe.write_text('#!/usr/bin/python3\nimport os,sys,time\ntime.sleep(1)\nos.execv("/usr/bin/ffprobe",["ffprobe",*sys.argv[1:]])\n')
        probe.chmod(0o755)
        shared, shared_output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/picker-sharing.qml',
            inputs, 'picker-sharing', dict(PATH=str(shim) + ':' + os.environ['PATH']))
        self.check('two-pickers-use-one-worker-request', shared['shared'] == dict(interests=2, requests=1), shared['shared'])
        self.check('closing-one-picker-retains-other-image', shared['survivor']['ready'] and not shared['survivor']['firstUrl']
                   and shared['survivor']['ffmpeg'] == 1 and max(abs(a-b) for a,b in zip(pixel(shared_output/'survivor.png'),COLORS[0])) <= 8, shared)
        self.check('last-picker-close-shuts-shared-worker', shared['finalInterests'] == shared['finalRequests'] == 0
                   and not shared['workerRunning'], shared)
        return result

    def wallpaper_remote(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                if self.path == '/missing.jpg':
                    self.send_error(404)
                    return
                if self.path == '/slow.jpg':
                    time.sleep(1.5)
                data = (inputs / ('Corrupt.webp' if self.path == '/bad.jpg' else 'Motion.webp')).read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.source,
                self.args.source / 'Scripts/dev/fixtures/image-decoding/wallpaper-remote.qml', inputs, 'remote',
                dict(IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}'))
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        self.check('remote-raw-native-package-control', result['raw'] == (1 if installed else 3), result['raw'])
        rows = {row['name']: row for row in result['snapshots']}
        accepted = rows['remote']
        original = Path(accepted['path'])
        self.check('remote-exact-original-not-renamed-jpeg', original.is_file() and original.suffix == '.webp'
                   and original.read_bytes() == (inputs/'Motion.webp').read_bytes(), accepted)
        self.check('remote-captured-directory-and-no-immediate-success', original.parent == Path(result['capturedDirectory'])
                   and not result['immediatePublication'], result)
        self.check('remote-captured-target-and-appearance', accepted['dark'] == str(inputs/'frame-2.png')
                   and accepted['other'] == str(inputs/'frame-2.png'), accepted)
        self.check('remote-actual-backdrop-static-pixels', accepted['state'] == 'ready'
                   and pixel(output/'remote.png') == list(COLORS[0]), accepted)
        self.check('remote-invalid-retains-exact-prior-pixels', rows['invalid']['path'] == str(original)
                   and read_png(output/'invalid.png') == read_png(output/'remote.png'), rows['invalid'])
        self.check('remote-local-intent-retires-slow-download', rows['superseded']['path'] == str(inputs/'frame-1.png')
                   and pixel(output/'superseded.png') == list(COLORS[1])
                   and all(row['id'] != 'slow' for row in result['downloads']) and '/slow.jpg' in requests, result)
        independent = rows['independent']
        self.check('remote-explicit-independent-target-keeps-captured-dark-slot', independent['otherDark']
                   and Path(independent['otherDark']).read_bytes() == (inputs/'Motion.webp').read_bytes()
                   and independent['path'] == str(inputs/'frame-1.png')
                   and independent['other'] == str(inputs/'frame-2.png'), independent)
        self.check('remote-http-failure-retains-selected-image', rows['http-failed']['path'] == str(inputs/'frame-1.png')
                   and read_png(output/'http-failed.png') == read_png(output/'superseded.png'), rows['http-failed'])
        calls = {row['id']: row for row in result['callbacks']}
        self.check('remote-standalone-download-validates-and-keeps-original', calls['standalone']['success']
                   and Path(calls['standalone']['path']).read_bytes() == (inputs/'Motion.webp').read_bytes()
                   and calls['standalone']['detail']['format'] == 'png'
                   and calls['standalone']['detail']['sourceInfo']['frames'] == 3, calls['standalone'])
        self.check('remote-invalid-download-honest-reason-and-cancelled-callback-retired', not calls['invalid']['success']
                   and not calls['invalid']['path'] and calls['invalid']['detail']['reason']
                   and 'cancelled' not in calls, calls)
        self.check('remote-failed-input-never-emits-downloaded', sorted(row['id'] for row in result['downloads'])
                   == ['motion', 'motion', 'standalone'], result['downloads'])
        errors = [row for row in result['notices'] if row['type'] == 'error']
        self.check('remote-selection-failures-have-visible-useful-errors', len(errors) == 2 and all(row['reason'] for row in errors), errors)
        self.check('remote-final-lifetime-quiescence', result['interests'] == result['requests'] == 0
                   and not result['workerRunning'], result)
        (self.out/'http-requests.json').write_text(json.dumps(requests, indent=2)+'\n')

    def remote_red(self):
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                data = (inputs / 'Corrupt.webp').read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.end_headers()
                self.wfile.write(data)
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.baseline_source or self.args.source,
                self.args.source / 'Scripts/dev/fixtures/image-decoding/remote-red.qml', inputs, 'remote-red',
                dict(IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}'))
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        self.check('wallhaven-invalid-bytes-published-as-download-success', result['done'] and result['result']['success']
                   and Path(result['result']['path']).read_bytes() == (inputs / 'Corrupt.webp').read_bytes()
                   and result['imageStatus'] == 3, result, red=True)

    def cache_contract(self):
        from image_decoding_cache_fixtures import target, thumbnail
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        for name in ('Foreign16.webp', 'ForeignInterlaced.webp'):
            (inputs / name).write_bytes((inputs / 'Still.webp').read_bytes())
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        redirected = self.args.case in ('cache-read-red', 'cache-read')
        red = self.args.case in ('cache-red', 'cache-read-red')
        if red and self.args.baseline_source is None:
            raise ValueError('Cache red requires an explicit immutable baseline source')
        name = self.args.case
        result, output = self.qt(self.args.baseline_source if red else self.args.source,
            self.args.source / 'Scripts/dev/fixtures/image-decoding/cache.qml', inputs, name)
        colors = [pixel(output / f'thumbnail-{i}.png') for i in range(3)]
        if redirected:
            self.check('actual-chooser-symlinked-cache-' + ('borrowed' if red else 'refused'),
                (all(row['state']['imageReady'] for row in result['rows']) and colors == [list(COLORS[1])] * 3) if red else
                (all(not row['state']['imageReady'] and row['state']['unavailable'] and row['state']['errorReason']
                     for row in result['rows']) and all(color != list(COLORS[1]) for color in colors)),
                dict(rows=result['rows'], colors=colors), red=red)
        else:
            self.check('actual-chooser-foreign-still-cache-' + ('ignored' if red else 'adopted'),
                       all(row['state']['imageReady'] for row in result['rows'])
                       and colors == [list(COLORS[0] if red else COLORS[1])] * 3, dict(rows=result['rows'], colors=colors), red=red)
        self.check('thumbnail-purpose-does-not-alias-ordinary-render', pixel(output / 'ordinary.png') == list(COLORS[0]), result['ordinary'])
        cache = self.work / (name + '-profile/cache/thumbnails')
        unchanged = []
        for filename, depth, interlace, text in (('Still.webp', 8, 0, 'tEXt'), ('Foreign16.webp', 16, 0, 'zTXt'),
                                                ('ForeignInterlaced.webp', 8, 1, 'iTXt')):
            path = target(cache, inputs / filename)
            unchanged.append(path.read_bytes() == thumbnail(inputs / filename, depth=depth, interlace=interlace, text=text))
        self.check('foreign-cache-inputs-not-rewritten', all(unchanged), unchanged)
        if redirected:
            outside = cache.parent.parent / 'user-originals'
            self.check('redirected-source-directory-not-modified', outside.stat().st_mode & 0o777 == 0o755
                and len(list(outside.iterdir())) == 3 and (cache / 'normal').is_symlink(), str(outside))
        self.check('cache-admission-and-retirement', result['idleInterests'] == result['interests'] == result['requests'] == 0
                   and not result['workerRunning'], result)

    def cache_clear(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        red = self.args.case == 'cache-clear-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Cache clear red requires an explicit immutable baseline source')
        name = self.args.case
        before = {path.name: path.read_bytes() for path in inputs.iterdir() if path.is_file() and os.access(path, os.R_OK)}
        result, output = self.qt(self.args.baseline_source if red else self.args.source,
                                 self.args.source / 'Scripts/dev/fixtures/image-decoding/cache-clear.qml', inputs, name)
        probes, toasts, released = result['probes'], result['toasts'], result['released']
        private = self.work / (name + '-profile/cache/thumbnails/atmosphera-representations-v1')
        self.check('actual-clear-button-clicked', result['clicked'] and len(toasts) == 1, toasts)
        self.check('released-adapter-output-was-owner-representation', released['success']
                   and Path(released['path']).is_relative_to(private), released)
        if red:
            self.check('actual-clear-button-leaves-owner-representations', toasts[0]['type'] == 'notice'
                       and probes['releasedAfterButton'] and not result['ownerClear'], dict(probes=probes, toasts=toasts), red=True)
            return result
        self.check('clear-toast-reports-completed-owner-clear', toasts[0]['type'] == 'notice' and toasts[0]['phase'] == 2,
                   toasts)
        self.check('released-representation-removed', not probes['releasedAfterButton'], probes)
        self.check('held-representation-kept-and-rendered', probes['heldAfterButton'] and result['held']['statusAfterButton'] == 1
                   and max(abs(a - b) for a, b in zip(pixel(output / 'held-after-clear.png'), COLORS[0])) <= 8,
                   dict(held=result['held'], probes=probes))
        self.check('retired-legacy-output-removed-plugin-folder-kept', not probes['legacyAfterButton']
                   and probes['pluginAfterButton'], probes)
        self.check('sources-unchanged', before == {path.name: path.read_bytes() for path in inputs.iterdir() if path.is_file() and os.access(path, os.R_OK)},
                   sorted(before))
        self.check('released-last-interest-then-cleared', result['clearResult'] and result['clearResult']['ok']
                   and result['clearResult']['removed'] >= 1 and not probes['heldAfterRelease'], result['clearResult'])
        self.check('cleared-representation-regenerates', result['regenerated']['status'] == 1 and probes['regeneratedExists']
                   and result['regenerated']['path'] == result['held']['path']
                   and max(abs(a - b) for a, b in zip(pixel(output / 'regenerated.png'), COLORS[0])) <= 8, result['regenerated'])
        return result

    def icons(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        icon_set = inputs / 'icon-set'
        icon_set.mkdir()
        # WebP bytes under an .svg icon-set name: content, not suffix, decides.
        for name, source in (('glyph-webp.svg', 'Still.webp'), ('glyph-png.png', 'frame-1.png'),
                             ('glyph-svg.svg', 'Still.svg'), ('glyph-corrupt.svg', 'Corrupt.webp')):
            shutil.copyfile(inputs / source, icon_set / name)
        (icon_set / 'icons.json').write_text(json.dumps(dict(name='Image fixtures', icons={
            'fixture-glyph-' + kind: dict(filename='glyph-' + kind + ('.png' if kind == 'png' else '.svg'))
            for kind in ('webp', 'png', 'svg', 'corrupt')})))
        manifest['iconSet'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(icon_set.iterdir())}
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        red = self.args.case == 'icons-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Icon red requires an explicit immutable baseline source')
        result, output = self.qt(self.args.baseline_source if red else self.args.source,
                                 self.args.source / 'Scripts/dev/fixtures/image-decoding/icons.qml', inputs, self.args.case)
        apps, glyphs = result['apps'], result['glyphs']
        icon = (35, 65, 225)
        def near(actual, expected, tolerance=8):
            return max(abs(a - b) for a, b in zip(actual, expected)) <= tolerance
        def center(name):
            return pixel(output / (name + '.png'))
        def glyph_center(name):
            width, height, _ = read_png(output / (name + '.png'))
            return pixel(output / (name + '.png'), width // 2, height // 2)
        def warning(name):
            width, height, pixels = read_png(output / (name + '.png'))
            return sum(near(pixels[(y * width + x) * 4:(y * width + x + 1) * 4], result['warningColor'])
                       for y in range(height) for x in range(width))
        self.check('icon-set-registered', result['glyphCount'] == 4, result['glyphCount'])
        if red:
            self.check('theme-icon-webp-bytes-under-png-name-not-presented', apps['webp']['status'] == 3
                       and center('app-webp')[3] == 0, dict(consumer=apps['webp'], center=center('app-webp')), red=True)
            self.check('icon-set-webp-file-mask-not-presented', not near(glyph_center('glyph-webp'), (*icon, 255)),
                       dict(consumer=glyphs['webp'], center=glyph_center('glyph-webp')), red=True)
            return result
        for kind, color in (('webp', COLORS[0]), ('png', COLORS[1]), ('svg', COLORS[0])):
            self.check('theme-icon-' + kind + '-presented', apps[kind]['status'] == 1 and not apps[kind]['failed']
                       and near(center('app-' + kind), color) and warning('app-' + kind) == 0,
                       dict(consumer=apps[kind], center=center('app-' + kind)))
        self.check('theme-lookup-failure-uses-ordinary-fallback', apps['missing']['status'] == 1 and not apps['missing']['failed']
                   and apps['missing']['source'].endswith('fixture-png-app.png') and near(center('app-missing'), COLORS[1])
                   and warning('app-missing') == 0, dict(consumer=apps['missing'], center=center('app-missing')))
        self.check('theme-decode-failure-is-labelled-fallback', apps['corrupt']['status'] == 1 and apps['corrupt']['failed']
                   and apps['corrupt']['reason'] and apps['corrupt']['source'].endswith('fixture-svg-app.svg')
                   and near(center('app-corrupt'), COLORS[0]) and warning('app-corrupt') > 10,
                   dict(consumer=apps['corrupt'], center=center('app-corrupt'), warning=warning('app-corrupt')))
        for kind in ('webp', 'png', 'svg'):
            self.check('icon-set-' + kind + '-mask-presented', not glyphs[kind]['failed']
                       and near(glyph_center('glyph-' + kind), (*icon, 255)) and warning('glyph-' + kind) == 0,
                       dict(consumer=glyphs[kind], center=glyph_center('glyph-' + kind)))
        self.check('icon-set-failure-is-labelled', glyphs['corrupt']['failed'] and glyphs['corrupt']['reason']
                   and not near(glyph_center('glyph-corrupt'), (*icon, 255)) and warning('glyph-corrupt') > 10,
                   dict(consumer=glyphs['corrupt'], warning=warning('glyph-corrupt')))
        return result

    def artwork(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        red = self.args.case == 'artwork-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Artwork red requires an explicit immutable baseline source')
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding' / (self.args.case + '.qml')
        result, output = self.qt(self.args.baseline_source if red else self.args.source, fixture, inputs, self.args.case)
        def near(actual, expected, tolerance=8):
            return max(abs(a - b) for a, b in zip(actual, expected)) <= tolerance
        def count(name, color):
            width, height, pixels = read_png(output / (name + '.png'))
            return sum(near(pixels[i * 4:i * 4 + 4], color) for i in range(width * height))
        control = dict(consumer=result['controlCenter'], center=pixel(output / 'control-center.png'),
                       art=count('control-center', COLORS[0]))
        options = dict(consumer=result['appOptions'], art=count('app-options', COLORS[0]))
        if red:
            self.check('bar-custom-icon-webp-not-presented', control['art'] == 0, control, red=True)
            self.check('app-options-theme-icon-webp-not-presented', options['art'] == 0, options, red=True)
            return result
        icons = result['icons']
        for kind in ('webp', 'svg'):
            self.check('image-icon-' + kind + '-presented', icons[kind]['status'] == 1 and not icons[kind]['failed']
                       and near(pixel(output / ('icon-' + kind + '.png')), COLORS[0])
                       and count('icon-' + kind, result['warningColor']) == 0,
                       dict(consumer=icons[kind], center=pixel(output / ('icon-' + kind + '.png'))))
        # Quickshell's icon provider answers a missing name with its own
        # placeholder: a provider result presented in process, not a failure.
        self.check('image-icon-provider-presented-in-process', icons['provider']['status'] == 1 and not icons['provider']['failed'],
                   icons['provider'])
        for kind in ('corrupt', 'unprovided'):
            self.check('image-icon-' + kind + '-failure-labelled', icons[kind]['status'] == 3 and icons[kind]['failed']
                       and icons[kind]['reason'] and count('icon-' + kind, result['warningColor']) > 10,
                       dict(consumer=icons[kind], warning=count('icon-' + kind, result['warningColor'])))
        self.check('image-icon-provider-never-reaches-cli', icons['unprovided']['code'] == 'provider-failed', icons['unprovided'])
        self.check('bar-custom-icon-webp-presented', near(control['center'], COLORS[0]) and control['art'] > 40, control)
        self.check('app-options-theme-icon-webp-presented', options['art'] > 15, options)
        return result

    def owner(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/owner.qml', inputs, 'owner')
        self.check('raw-webp-package-control', result['raw'] == (1 if installed else 3), result['raw'])
        for i, row in enumerate(result['formats']):
            consumer, center = row['consumer'], pixel(output / f'format-{i}.png')
            self.check('owner-format-' + row['name'], consumer['state'] == 'ready' and consumer['status'] == 1
                       and consumer['result']['generation'] == consumer['generation']
                       and max(abs(a - b) for a, b in zip(center, COLORS[0])) <= 8,
                       dict(consumer=consumer, center=center))
        webp = result['formats'][0]['consumer']
        self.check('native-first-or-independent-fallback', webp['result']['origin'] == ('native' if installed else 'fallback')
                   and (installed or webp['result']['format'] == 'png'), webp)
        self.check('opaque-provider-failure-is-explicit', result['provider']['state'] == 'unavailable'
                   and result['provider']['errorCode'] == 'provider-failed' and not result['provider']['url'], result['provider'])
        for name in ('corrupt', 'missing'):
            row = result[name]
            self.check('owner-' + name + '-failure', row['state'] == 'unavailable' and bool(row['errorReason']) and not row['url'], row)
        self.check('disabled-is-idle-not-failure', result['disabled']['state'] == result['sharedA']['state'] == 'idle', result['disabled'])
        self.check('source-replacement-pixels', result['replacing']['state'] == 'ready'
                   and pixel(output / 'replacing.png') == list(COLORS[1]), result['replacing'])
        self.check('retired-generation-rejected', result['staleRejected'], result['staleRejected'])
        self.check('last-interest-retains-result', result['sharedB']['state'] == 'ready'
                   and pixel(output / 'shared-survivor.png') == list(COLORS[0]), result['sharedB'])
        self.check('data-source-ignores-mime-hint', result['data']['state'] == 'ready'
                   and pixel(output / 'data.png') == list(COLORS[0]), result['data'])
        self.check('still-representation-is-frame-zero', result['firstFrame']['result']['frames'] == 1
                   and pixel(output / 'first-frame.png') == list(COLORS[0]), result['firstFrame'])
        motion = result['motion']
        self.check('owner-motion-pause-retains-representation', result['pausePreserved'], result['pausePreserved'])
        events = result['events']
        centers = [pixel(path) for path in output.glob('motion-*.png')]
        self.check('owner-preserved-animation', motion['state'] == 'ready' and motion['frameCount'] == 3
                   and motion['result']['frames'] == 3 and motion['result']['delaysMs'] == manifest['delaysMs']
                   and len(events) >= 6 and all(b['frame'] == (a['frame'] + 1) % 3 for a, b in zip(events, events[1:]))
                   and {tuple(p) for p in centers} == set(COLORS)
                   and (installed or motion['result']['format'] == 'gif'), dict(consumer=motion, events=events, centers=centers))
        self.check('owner-retirement-shuts-worker', result['finalInterests'] == result['finalRequests'] == 0
                   and not result['workerRunning'], result)
        for mode, code in (('malformed', 'worker-protocol'), ('shape', 'worker-protocol'), ('death', 'worker-exit')):
            shim = self.work / ('fault-' + mode)
            shim.mkdir()
            executable = shim / 'python3'
            # Replace only this fixture's first worker process. Qt's genuine
            # codec condition is unchanged; a later explicit request invokes
            # the actual production worker through the unchanged Python CLI.
            executable.write_text('#!/usr/bin/python3\nimport json,os,sys\nfrom pathlib import Path\n'
                f'marker=Path({str(shim / "started")!r})\n'
                'if sys.argv[-1].endswith("/image-worker.py") and not marker.exists():\n'
                ' marker.touch()\n print(json.dumps({"event":"ready"}),flush=True)\n sys.stdin.readline()\n'
                + (' print(' + repr('not-json' if mode == 'malformed' else '{}') + ',flush=True)\n sys.stdin.read()\n sys.exit(0)\n'
                   if mode in ('malformed', 'shape') else ' os._exit(13)\n')
                + 'os.execv("/usr/bin/python3",["python3",*sys.argv[1:]])\n')
            executable.chmod(0o755)
            failure, failure_output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/owner-fault.qml',
                inputs, 'owner-' + mode, dict(PATH=str(shim) + ':' + os.environ['PATH']))
            self.check('owner-' + mode + '-settles-without-loop', failure['first']['status'] == 'unavailable'
                       and failure['first']['code'] == code and failure['deliveries'] == 1, failure)
            self.check('owner-' + mode + '-explicit-retry', failure['retry']['state'] == 'ready'
                       and pixel(failure_output / 'retry.png') == list(COLORS[0])
                       and failure['finalInterests'] == failure['finalRequests'] == 0 and not failure['workerRunning'], failure)
        # The independent locker installs a reviewed subset, not a link to all
        # shell services. Exercise the same source API in that assembled graph
        # without starting a session lock or authentication operation.
        stage = self.work / 'locker-stage'
        packaged = self.command(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', self.args.source],
            timeout=90, env=dict(os.environ, srcdir=str(self.args.source.parent), _gitname=self.args.source.name,
                                pkgdir=str(stage), pkgver=(self.args.source / 'VERSION').read_text().strip()))
        self.check('owner-locker-package-assembly', packaged.returncode == 0, dict(exit=packaged.returncode, stderr=packaged.stderr))
        lock = stage / 'etc/xdg/quickshell/atmosphera-lockscreen'
        self.check('owner-locker-minimal-graph', not (lock / 'Services/Plugins').exists()
                   and not (lock / 'Portals').exists(), dict(root=str(lock)))
        locked, lock_output = self.qt(lock, self.args.source / 'Scripts/dev/fixtures/image-decoding/owner.qml',
                                     inputs, 'owner-locker', assembled=True)
        centers = [pixel(path) for path in lock_output.glob('motion-*.png')]
        self.check('owner-locker-standalone-consumer', locked['motion']['state'] == 'ready'
                   and locked['motion']['frameCount'] == 3 and {tuple(p) for p in centers} == set(COLORS)
                   and all(row['consumer']['state'] == 'ready' for row in locked['formats'])
                   and locked['finalInterests'] == locked['finalRequests'] == 0 and not locked['workerRunning'], locked)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--baseline-source', type=Path)
    parser.add_argument('--baseline-plugins', type=Path)
    parser.add_argument('--qt-webp', choices=('present', 'absent'), required=True)
    parser.add_argument('--case', choices=CASES, required=True)
    parser.add_argument('--results', type=Path)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    run = Run(args, profile)
    try:
        if args.case == 'red':
            run.red()
        elif args.case == 'remote-red':
            run.remote_red()
        elif args.case == 'wallpaper-remote':
            run.wallpaper_remote()
        elif args.case in ('wallpaper-wizard', 'wizard-red'):
            run.wallpaper_wizard()
        elif args.case in ('icons-red', 'icons'):
            run.icons()
        elif args.case in ('artwork-red', 'artwork'):
            run.artwork()
        elif args.case in ('cache-clear-red', 'cache-clear'):
            run.cache_clear()
        elif args.case == 'owner':
            run.owner()
        elif args.case in ('cache', 'cache-red', 'cache-read', 'cache-read-red'):
            run.cache_contract()
        elif args.case in ('producer-capture', 'producer-retirement-red', 'notification-adapter'):
            run.producer_capture()
        elif args.case in ('notification-service-red', 'notification-service'):
            run.notification_service()
        elif args.case == 'legacy':
            run.legacy()
        elif args.case == 'backdrops':
            run.backdrops()
        elif args.case == 'rounded':
            run.rounded()
        elif args.case == 'wallpaper-admission':
            run.wallpaper_admission()
        elif args.case == 'wallpaper-setup':
            run.wallpaper_setup()
        elif args.case == 'wallpaper-scan':
            run.wallpaper_scan()
        elif args.case == 'wallpaper-gallery':
            run.wallpaper_gallery()
        elif args.case == 'desktop-wallpaper':
            run.desktop_wallpaper()
        elif args.case == 'chooser':
            run.chooser()
        else:
            raise NotImplementedError('Required image cohort not implemented: ' + args.case)
        current = {key: source_manifest(path) for key, path in
                   (('source', args.source), ('plugins', args.plugins), ('baselineSource', args.baseline_source),
                    ('baselinePlugins', args.baseline_plugins)) if path is not None}
        run.check('qualified-inputs-unchanged', current == run.inputs, {key: row['sha256'] for key, row in current.items()})
    except BaseException as error:
        result = run.record('failed', repr(error))
        (run.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        raise
    result = run.record('complete')
    (run.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('IMAGE_DECODING: ' + ('RED_CONTROLS_PASS' if args.case == 'red' else 'PASS'), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
