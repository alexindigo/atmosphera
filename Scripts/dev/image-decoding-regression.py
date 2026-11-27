#!/usr/bin/env python3
"""Image decoding end-consumer regression controller; explicit owned guest only."""
import argparse
import base64
from itertools import groupby
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

from guest_profile import activate_profile, profile_argument, protect_owned_process
from image_decoding_fixtures import COLORS, colored_png, create_fixtures, pixel, read_png
from image_decoding_evidence import displays_retired, source_manifest
from image_decoding_workspace import retire_fixture_copy, settle_fixture_session
from image_decoding_jobs import Worker, supervise
from image_decoding_bus import address_for, private_bus
from qml_probe import bootstrap_fixture


CASES = ('red', 'icons-red', 'icons', 'artwork-red', 'artwork', 'launcher-red', 'launcher', 'text-red', 'text', 'cache-clear-red', 'cache-clear', 'remote-red', 'wizard-red', 'cache-red', 'cache', 'cache-read-red', 'cache-read', 'producer-capture', 'producer-retirement-red', 'notification-adapter', 'notification-service-red', 'notification-service', 'notification-body', 'wallpaper-wizard', 'wallpaper-remote', 'owner', 'source-admission', 'download-burst', 'legacy', 'backdrops', 'rounded', 'wallpaper-admission', 'wallpaper-setup', 'wallpaper-scan', 'wallpaper-gallery', 'desktop-wallpaper', 'parallax-wallpaper', 'chooser', 'chooser-wallpaper', 'shell', 'plugins', 'packaging', 'all', 'review-results')
ERRORS = re.compile(r'ReferenceError|TypeError|SyntaxError|Cannot assign|Unable to assign|Binding loop|'
                    r'Failed to load configuration|is not installed|Component is not ready|'
                    r'completion callback threw|Wallpaper settlement callback failed|Completion callback failed for request')
GROUPS = {
    'chooser-wallpaper': ('chooser', 'legacy', 'backdrops', 'wallpaper-admission', 'wallpaper-setup',
                          'wallpaper-wizard', 'wallpaper-scan', 'wallpaper-gallery', 'wallpaper-remote',
                          'desktop-wallpaper', 'parallax-wallpaper'),
    'shell': ('rounded', 'icons', 'artwork', 'launcher', 'text', 'producer-capture', 'notification-adapter',
              'notification-service', 'notification-body', 'cache', 'cache-read', 'cache-clear'),
    'all': ('owner', 'download-burst', 'chooser-wallpaper', 'shell', 'plugins', 'packaging'),
}


def peer_closed(connection):
    """Observe the held HTTP client, independent of handler scheduling."""
    try:
        return not connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT)
    except BlockingIOError:
        return False
    except ConnectionResetError:
        return True


def warning_coverage(path, color, *, background=None):
    """Measure equivalent opaque warning pixels in a straight-alpha grab."""
    width, height, rgba = read_png(path)
    offsets = range(0, len(rgba), 4)
    if background is not None:
        bg_width, bg_height, bg = read_png(background)
        if (bg_width, bg_height) != (width, height):
            raise AssertionError('Warning and background grabs differ in size')
        # On transparent parts of the paired fallback, straight RGB and alpha
        # describe the warning itself, not its blend with the fallback art.
        offsets = (i for i in offsets if bg[i + 3] == 0)
    return sum(rgba[i + 3] for i in offsets
               if max(abs(a - b) for a, b in zip(rgba[i:i + 3], color[:3])) <= 8) / 255


def red_warning_coverage(pixels, color):
    """Measure blended warning coverage over neutral chrome or green icons."""
    return sum(max(0, r - g) * a / 255 for r, g, _, a in pixels) / (color[0] - color[1])


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
        changed = []
        for source, baseline in ((args.source, getattr(args, 'lint_baseline_source', None)), (args.plugins, args.baseline_plugins)):
            if baseline is not None:
                before = source_manifest(baseline)['files']
                after = source_manifest(source)['files']
                changed.extend(str(source / name) for name, row in after.items()
                               if name.endswith('.qml') and before.get(name) != row)
        (self.out / 'changed-qml.txt').write_text(''.join(path + '\n' for path in sorted(changed)))
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

    def aggregate(self):
        """Run every cohort through its real driver and retain every assertion."""
        children = self.out / 'cohorts'
        children.mkdir()
        for case in GROUPS[self.args.case]:
            argv = ['python3', '-B', str(self.args.source / 'Scripts/dev/image-decoding-regression.py'),
                    '--guest-profile', str(self.args.guest_profile), '--source', str(self.args.source),
                    '--plugins', str(self.args.plugins), '--qt-webp', self.args.qt_webp,
                    '--case', case, '--output', str(children / case), '--work-root', str(self.work / case)]
            for flag, path in (('--baseline-source', self.args.baseline_source), ('--baseline-plugins', self.args.baseline_plugins)):
                if path is not None:
                    argv.extend((flag, str(path)))
            if self.args.lint_baseline_source is not None:
                argv.extend(('--lint-baseline-source', str(self.args.lint_baseline_source)))
            result = self.command(argv, timeout=7200)
            (self.out / (case + '.log')).write_text(result.stdout + result.stderr)
            report = children / case / 'result.json'
            data = json.loads(report.read_text()) if report.is_file() else {}
            self.check('cohort-' + case, result.returncode == 0 and data.get('state') == 'complete'
                       and data.get('cases') and all(row['result'] == 'PASS' for row in data['cases'])
                       and data.get('inputs') == {key: row['sha256'] for key, row in self.inputs.items()},
                       dict(exit=result.returncode, result=str(report), checks=len(data.get('cases', [])),
                             failure=data.get('failure', ''), log=str(self.out / (case + '.log'))))
        if self.args.case == 'all':
            for name, argv in (
                ('boundary', ['python3', '-B', str(self.args.source / 'Scripts/dev/image-decoding-boundary-check.py'),
                              '--source', str(self.args.source), '--plugins', str(self.args.plugins), '--selftest',
                              '--manifest', str(self.args.source / 'Scripts/dev/fixtures/image-decoding/consumers.json'),
                              '--report', str(self.out / 'boundary.json')]),
                 ('private-bus', ['python3', '-B', str(self.args.source / 'Scripts/dev/image-decoding-bus-selftest.py'),
                                  '--guest-profile', str(self.args.guest_profile), '--output', str(self.out / 'private-bus')])):
                result = self.command(argv, timeout=1800)
                (self.out / (name + '.log')).write_text(result.stdout + result.stderr)
                self.check('contract-' + name, result.returncode == 0, dict(exit=result.returncode, log=str(self.out / (name + '.log'))))

    def qt(self, source, fixture, inputs, name, extra_env=None, assembled=False, launcher=None, clean_environment=False):
        result = self._qt(source, fixture, inputs, name, extra_env, assembled, launcher, clean_environment)
        if not assembled:
            retire_fixture_copy(source, self.work / name, self.out / (name + '-source.json'),
                                self.out / (name + '-source-retired.json'), self.work)
        return result

    def private_bus_address(self):
        # Aggregate evidence/work paths can exceed sockaddr_un.sun_path. The
        # admitted profile already owns a short disk-backed IPC runtime root.
        return address_for(self.profile)

    def _qt(self, source, fixture, inputs, name, extra_env=None, assembled=False, launcher=None, clean_environment=False):
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
        if self.args.case in ('desktop-wallpaper', 'parallax-wallpaper', 'wallpaper-software-baseline'):
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
            (legacy / 'thumbnails/legacy.png').write_bytes((inputs / 'frame-0.png').read_bytes())
            (legacy / 'thumbnails/original.png').symlink_to(inputs / 'Still.webp')
            (legacy / 'thumbnails/mpvpaper/plugin.bmp').write_bytes(b'plugin-owned')
            contributors = profile / 'cache/images/contributors'
            contributors.mkdir()
            (contributors / 'legacy.png').write_bytes((inputs / 'frame-0.png').read_bytes())
        if name == 'cache-clear':
            # A previous process produced this valid entry and exited, so it
            # cannot be kept alive by the current owner's memory cache.
            cold = self.work / 'cache-clear-seed-profile/cache/images/decoded'
            shutil.copytree(cold, profile / 'cache/images/decoded')
        if self.args.case in ('icons-red', 'icons', 'artwork-red', 'artwork', 'launcher-red', 'launcher'):
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
        child_environment = self.profile.child_environment('image-')
        child_environment.setdefault('QT_QPA_PLATFORM', 'wayland')
        base_environment = dict(HOME=str(self.profile.home), LANG='C.UTF-8', PATH='/nonexistent') if clean_environment else os.environ
        env = dict(base_environment, **child_environment,
                    QML_DISABLE_DISK_CACHE='1', IMAGE_FIXTURES=str(inputs), IMAGE_OUTPUT=str(output),
                    IMAGE_DATA='data:image/jpeg;base64,' + base64.b64encode((inputs / 'Still.webp').read_bytes()).decode(),
                    ATMOSPHERA_CONFIG_DIR=str(profile / 'config') + '/', ATMOSPHERA_CACHE_DIR=str(profile / 'cache') + '/',
                    IMAGE_ICON_DIR=str(self.args.source / 'builtin/plugins/atmosphera-icons'),
                   ATMOSPHERA_STATE_DIR=str(profile / 'state') + '/', ATMOSPHERA_SETTINGS_FILE=str(profile / 'config/settings.json'),
                   XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'),
                    XDG_STATE_HOME=str(profile / 'state'), XDG_DATA_HOME=str(profile / 'data'), TMPDIR=str(profile / 'tmp'))
        env.update(extra_env or {})
        argv = [str(launcher), 'run', '--path', str(entry)] if launcher else ['qs', '-p', str(entry)]
        with (output / 'qt.log').open('w') as log:
            proc = subprocess.Popen(argv, env=env, cwd=shell, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
            guard = protect_owned_process(proc)
            try:
                # Inspect the actual fresh reader process, not an environment
                # flag that merely claims a plugin condition.
                maps, executables, environments = set(), set(), []
                deadline = time.monotonic() + (90 if self.args.case in ('notification-service', 'plugins') else 25)
                while proc.poll() is None:
                    try:
                        maps.update(line.split()[-1] for line in Path(f'/proc/{proc.pid}/maps').read_text().splitlines()
                                    if 'imageformats/' in line)
                        executables.add(os.readlink(f'/proc/{proc.pid}/exe'))
                        if launcher:
                            values = dict(part.split(b'=', 1) for part in Path(f'/proc/{proc.pid}/environ').read_bytes().split(b'\0') if b'=' in part)
                            selected = {key: os.fsdecode(values[os.fsencode(key)]) for key in ('PATH', 'QT_PLUGIN_PATH', 'QML_IMPORT_PATH', 'NIXPKGS_QT6_QML_IMPORT_PATH') if os.fsencode(key) in values}
                            if selected not in environments:
                                environments.append(selected)
                    except FileNotFoundError:
                        pass
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Qt consumer watchdog')
                    time.sleep(.05)
                code = proc.wait(timeout=25)
                settle_fixture_session(proc)
            except BaseException as error:
                (output / 'primary-error.txt').write_text(repr(error) + '\n')
                raise
            finally:
                try:
                    if proc.poll() is None:
                        guard.terminate()
                        proc.wait(timeout=10)
                except BaseException as error:
                    (output / 'cleanup-error.txt').write_text(repr(error) + '\n')
                    raise
                finally:
                    (output / 'process.json').write_text(json.dumps(dict(argv=argv,
                        identity=guard.identity.record() if guard.identity else None, exit=proc.returncode,
                        imagePlugins=sorted(maps), executables=sorted(executables),
                        cleanEnvironment=clean_environment, environments=environments), indent=2) + '\n')
        text = (output / 'qt.log').read_text()
        errors = [line for line in text.splitlines() if ERRORS.search(line)]
        if code or errors:
            raise AssertionError(dict(exit=code, runtimeErrors=errors, log=str(output / 'qt.log')))
        vfs = (shell / '.qmlls.ini').resolve(strict=True).parent
        if not vfs.is_relative_to(self.profile.runtime_base) or not (vfs / 'qs/Commons/qmldir').is_file():
            raise AssertionError('Consumer did not generate authoritative QML tooling')
        lint_paths = [str(entry)]
        historical = source == self.args.baseline_source
        owner_paths = ('Services/UI/ImageWorker.qml', 'Services/UI/ImageSource.qml') if historical else (
            'Services/UI/ImageInput.qml', 'Services/UI/ImageRetention.qml')
        if self.args.case in ('owner', 'source-admission', 'legacy'):
            lint_paths += [str(shell / p) for p in (*owner_paths,
                                                    'Services/UI/ImageCacheService.qml', 'Widgets/NImage.qml', 'Widgets/AtmoIcon.qml')]
            if not assembled:
                lint_paths.append(str(shell / 'Widgets/NImageIcon.qml'))
        if self.args.case in ('cache', 'cache-read'):
            lint_paths += [str(shell / p) for p in (*owner_paths, 'Widgets/NImage.qml',
                'Services/UI/ImageCacheService.qml', 'Modules/FileChooser/FileEntryArtwork.qml')]
        if self.args.case in ('cache-clear-red', 'cache-clear'):
            owner = 'Services/UI/ImageWorker.qml' if self.args.case.endswith('-red') else 'Services/UI/ImageRetention.qml'
            lint_paths += [str(shell / p) for p in (owner, 'Services/UI/ImageCacheService.qml',
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
        if self.args.case == 'launcher':
            lint_paths += [str(shell / p) for p in ('Modules/Panels/Launcher/LauncherListDelegate.qml',
                'Modules/Panels/Launcher/LauncherGridDelegate.qml', 'Modules/Panels/Launcher/ClipboardPreview.qml')]
        if self.args.case == 'text':
            lint_paths += [str(shell / p) for p in ('Widgets/NImageText.qml', 'Modules/Notification/Notification.qml',
                'Modules/Panels/NotificationHistory/NotificationHistoryPanel.qml', 'Modules/Panels/Changelog/ChangelogContent.qml',
                'Modules/Tooltip/Tooltip.qml', 'Modules/Panels/Launcher/LauncherCore.qml', 'Widgets/NLabel.qml', 'Widgets/NHeader.qml',
                'Modules/Dialog/DialogPanel.qml', 'Modules/Panels/Settings/Tabs/Connections/BluetoothSubTab.qml',
                'Modules/DesktopWidgets/Widgets/DesktopAppShortcut.qml', 'Modules/Panels/Settings/Tabs/ColorScheme/ColorCustomizer.qml',
                'Modules/Panels/Settings/Tabs/Idle/BehaviorSubTab.qml', 'Modules/Panels/Settings/Tabs/LockScreen/AppearanceSubTab.qml',
                'Widgets/AtmoIcon.qml', 'builtin/plugins/demo-custom-lockscreen/LockScreenView.qml', 'Services/Version.qml')]
        if self.args.case == 'plugins':
            lint_paths += [str(shell / p) for p in ('Widgets/NImage.qml', 'Widgets/NImageIcon.qml', 'Widgets/NImageText.qml')]
            lint_paths += [str(p) for p in getattr(self, 'plugin_lint', [])]
        if self.args.case == 'chooser':
            lint_paths += [str(shell / p) for p in ('Services/Files/FileTypes.qml', 'Modules/FileChooser/FileEntryArtwork.qml',
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
                'Services/UI/ImageCacheService.qml', *owner_paths, 'Modules/Panels/Wallpaper/WallpaperPanel.qml')]
        if self.args.case == 'desktop-wallpaper':
            lint_paths += [str(shell / p) for p in ('Modules/Background/Background.qml', 'Modules/Background/Overview.qml')]
        if self.args.case == 'parallax-wallpaper':
            lint_paths += [str(shell / 'Modules/Background/Overview.qml'), str(self.args.plugins / 'parallax-wallpaper/ParallaxBackground.qml')]
        if self.args.case in ('producer-capture', 'producer-retirement-red', 'notification-adapter'):
            lint_paths += [str(shell / p) for p in (*owner_paths, 'Services/UI/ImageCacheService.qml')]
        if self.args.case == 'notification-body':
            lint_paths += [str(shell / p) for p in ('Services/System/NotificationService.qml', 'Widgets/NImageText.qml',
                'Modules/Notification/Notification.qml', 'Modules/Panels/NotificationHistory/NotificationHistoryPanel.qml')]
        if self.args.case == 'notification-service':
            lint_paths += [str(shell / p) for p in ('Services/System/NotificationService.qml', 'Services/UI/ImageCacheService.qml',
                'Widgets/NImageRounded.qml', 'Widgets/NNotificationImage.qml', 'Modules/Notification/Notification.qml',
                'Modules/Panels/NotificationHistory/NotificationHistoryPanel.qml')]
        lint = self.command(['bash', str(self.args.source / 'Scripts/dev/qmllint.sh'), *lint_paths], timeout=900,
                            cwd=shell, env=dict(env, PATH=os.environ['PATH'], QS_VFS=str(vfs)))
        (output / 'qmllint.log').write_text(lint.stdout + lint.stderr)
        if lint.returncode or 'Failed to import qs.' in lint.stderr:
            raise AssertionError('Composite-aware consumer fixture lint failed')
        rows = [json.loads(line.split('IMAGE_BASELINE|', 1)[1]) for line in text.splitlines() if 'IMAGE_BASELINE|' in line]
        grabs = [json.loads(line.split('IMAGE_GRAB|', 1)[1]) for line in text.splitlines() if 'IMAGE_GRAB|' in line]
        bad_grabs = [row for row in grabs if not row['saved']]
        if len(rows) != 1 or not grabs or bad_grabs:
            raise AssertionError(dict(baselines=len(rows), grabs=len(grabs), failedGrabs=bad_grabs))
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
        with private_bus(self.profile, self.out) as actual:
            red = self.args.case == 'producer-retirement-red'
            adapter = self.args.case == 'notification-adapter'
            if red and self.args.baseline_source is None:
                raise ValueError('Producer retirement red requires an explicit immutable baseline source')
            source = self.args.baseline_source if red else self.args.source
            name = 'producer-retirement-red' if red else 'notification-adapter' if adapter else 'producer-capture'
            fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding' / (name + ('.qml.in' if red else '.qml'))
            result, output = self.qt(source, fixture,
                                     inputs, name, extra_env=dict(DBUS_SESSION_BUS_ADDRESS=actual,
                                      IMAGE_LEGACY_HOLD_CALLBACKS='1' if red else '0',
                                      IMAGE_PRODUCER=str(self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-producer.py')))
        if red:
            self.check('producer-file-retirement-old-adapter', len(result['legacyFiles']) == 4
                       and all(row['path'] and not row['success'] and row['statusAfterLoss'] == 3 for row in result['legacyFiles']),
                       result['legacyFiles'], red=True)
            self.check('retirement-red-real-producer', result['producerExit'] == 0 and not result['producerErrors']
                       and all(not (inputs / name).exists() for name in names), result)
            return result
        if adapter:
            return self.notification_adapter_results(result, output, inputs, expected)
        self.check('capture-native-reader-control', result['raw'] == (1 if installed else 3), result['raw'])
        self.check('capture-binary-padding-exact', all(base64.b64decode(row['url'].split(',', 1)[1], validate=True)
                   == bytes(i % 256 for i in range(row['length'])) for row in result['bytes']) and len(result['bytes']) == 7, result['bytes'])
        captures = result['captured']
        self.check('capture-provider-revisions-observed', len(captures) == 9 and len({r['original'] for r in captures[1:5]}) == 4
                   and captures[1]['id'] == captures[2]['id'] == captures[3]['id'] != captures[4]['id'],
                   [{k: v for k, v in row.items() if k not in ('source', 'snapshot')} for row in captures])
        self.check('capture-provider-gone-before-presentation', len(result['late']) == 4
                   and all(row['state'] == 'unavailable' and row['code'] for row in result['late']) and result['producerExit'] == 0
                   and not result['producerErrors'], result['late'])
        self.check('capture-files-gone-before-presentation', all(not (inputs / name).exists() for name in names), names)
        rows = sorted(result['results'], key=lambda row: row['index'])
        self.check('capture-exact-original-bytes', len(rows) == 9 and all(Path(rows[index]['path']).read_bytes()
                   == source.read_bytes() for index, source in zip((0, 5, 7, 8), [expected[0], *expected])), rows)
        self.check('capture-same-url-replacement-bytes', captures[5]['original'] == captures[6]['original']
                   and captures[5]['id'] != captures[6]['id'] and Path(rows[6]['path']).read_bytes()
                   == (inputs / 'frame-1.png').read_bytes(), captures[6]['original'])
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
        self.check('capture-refusal-reasons', len(result['refusals']) == 3 and all(not row['success'] and not row['path']
                   and row['detail']['code'] and row['detail']['reason'] for row in result['refusals']), result['refusals'])
        cache = self.work / 'producer-capture-profile/cache/images/staging'
        remaining = list(cache.glob('.originals-*'))
        self.check('capture-cancel-and-quiescence', not result['cancelled'] and not remaining
                   and not (output / 'cancelled').exists(), dict(callbacks=result['cancelled'], staging=list(map(str, remaining))))
        return result

    def notification_adapter_results(self, result, output, inputs, expected):
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
        self.check('adapter-validated-original', all(row['success'] and row['detail']['ok']
                   and row['detail']['originalPath'] == row['path'] and Path(row['path']).is_file()
                   and row['detail']['contentSha256'] == hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()
                   for row in rows), rows)
        self.check('adapter-explicit-failures', len(result['failures']) == 4 and all(not row['path'] and not row['success']
                   and row['detail']['code'] and row['detail']['reason'] for row in result['failures']), result['failures'])
        self.check('adapter-cancel-suppressed', not result['cancelled'], result['cancelled'])
        cache = self.work / 'notification-adapter-profile/cache'
        remaining = list(cache.glob('images/staging/.originals-*')) + list(cache.glob('image-source-*'))
        self.check('adapter-quiescence', not remaining, [str(p) for p in remaining])
        return result

    def notification_body(self):
        """Body/summary image markup through the actual service, popup and
        history: stripped by the service (orchestrator decision), text kept,
        no image interest, no request."""
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                payload = (inputs / 'Still.webp').read_bytes()
                self.send_response(200)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            def log_message(self, *_args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            with private_bus(self.profile, self.out) as actual:
                result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-body.qml',
                    inputs, 'notification-body', extra_env=dict(DBUS_SESSION_BUS_ADDRESS=actual,
                    ATMOSPHERA_NOTIF_HISTORY_FILE=str(inputs / 'history.json'),
                    IMAGE_HTTP_BASE='http://127.0.0.1:' + str(server.server_port),
                    IMAGE_PRODUCER=str(self.args.source / 'Scripts/dev/fixtures/image-decoding/notification-body-producer.py')))
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()
            (self.out / 'http.json').write_text(json.dumps(requests, indent=2) + '\n')
        self.check('notification-body-producer', result['producerExit'] == 0 and not result['producerErrors'], result)
        self.check('notification-body-no-request', requests == [], requests)
        for cohort in ('popup', 'history'):
            model = result[cohort + 'Model']
            shown = result[cohort + 'Texts']
            fields = [str(row.get(key, '')) for row in model for key in ('summary', 'body')]
            self.check('notification-body-' + cohort + '-text-kept-without-images',
                       len(model) == 1 and any('end-marker' in f and 'world' in f for f in fields)
                       and any('summary-marker' in f for f in fields) and not any('<img' in f or 'background=' in f for f in fields)
                       and shown and all(t['images'] == 0 for t in shown) and any('end-marker' in t['text'] for t in shown if t['visible'])
                       and not any('<img' in t['text'] for t in shown), dict(model=model, texts=shown))
        # Stored history keeps the text (image URLs at most as visible text),
        # never an image tag, background attribute or Markdown image.
        stored = json.loads(Path(result['historyFile']).read_text())['notifications'] if result['historyFile'] else []
        self.check('notification-body-history-file-without-image-markup', len(stored) == 1
                   and 'end-marker' in stored[0]['body'] and 'md art' in stored[0]['bodyMarkdown']
                   and not any('<img' in stored[0][k] or 'background=' in stored[0][k] for k in ('body', 'summary'))
                   and not any('![' in stored[0][k] or '<img' in stored[0][k] for k in ('bodyMarkdown', 'summaryMarkdown')), stored)
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
        try:
            with private_bus(self.profile, self.out) as actual:
                name = 'notification-service-red' if red else 'notification-service'
                fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding' / (name + ('.qml.in' if red else '.qml'))
                result, output = self.qt(source, fixture,
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
                    'overflow-trigger', 'same-provider-first', 'same-provider-replacement',
                    'same-provider-new', 'clear-with-popup', 'cold-provider', 'cold-file', 'closed']
        actual = []
        for stage, color in [('same-provider-first', COLORS[0]), ('same-provider-replacement', COLORS[2]),
                             ('same-provider-new', COLORS[2])]:
            target = next(row for row in snapshots[stage]['history'] if row['summary'] == stage)
            rows = [dict(cohort=row['cohort'], status=row['status'], rgba=pixel(output / row['file']))
                    for row in result['widgets'] if row['stage'] == stage and row['id'] == target['id']]
            actual.append(dict(stage=stage, expected=list(color), rows=rows, id=target['id'],
                               revision=target['imageRevision'], source=target['originalImage']))
        self.check('notification-service-same-provider-actual-pixels',
                   len({row['source'] for row in actual}) == 1 and actual[0]['id'] == actual[1]['id'] != actual[2]['id']
                   and actual[0]['revision'] != actual[1]['revision']
                   and all({row['cohort'] for row in step['rows']} == {'popup', 'history'}
                           and all(row['status'] == 1 and row['rgba'] == step['expected'] for row in step['rows'])
                           for step in actual), actual)
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
                   and first['cachedImage'].endswith('.webp') and not first['imageRepresentation'], first)
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
        left = [str(path) for name in ('notification-service', 'notification-history-cold')
                for path in (self.work / (name + '-profile') / 'cache').rglob('*')
                if path.name.startswith(('image-source-', '.originals-'))]
        self.check('notification-service-quiescence', result['interests'] == cold['interests'] == 0
                   and not left and not snapshots['closed']['popup'], dict(closed=snapshots['closed'], stages=left))
        shared = next(row['cachedImage'] for row in snapshots['clear-with-popup']['popup']
                      if row['summary'] == 'shared-two')
        shared_path = Path(unquote(urlsplit(shared).path))
        self.check('notification-service-last-reference-retires-original', urlsplit(shared).scheme == 'file'
                   and shared_path.parent.name == 'retained' and not shared_path.exists()
                   and all(row['cachedImage'] != shared for row in persisted), dict(url=shared, retained=shared_path.exists()))
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
        result, output = self.qt(args.baseline_source, args.source / 'Scripts/dev/fixtures/image-decoding/baseline.qml.in', inputs, 'baseline')
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

    def desktop_wallpaper(self, prefix='desktop-wallpaper', root=''):
        """The shell's desktop background, or a plugin background root with the
        same per-screen contract (parallax-wallpaper), and the shell overview."""
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work/'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out/'fixture-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        result, output = self.qt(self.args.baseline_source or self.args.source, self.args.source/'Scripts/dev/fixtures/image-decoding/desktop-wallpaper.qml',
                                 inputs, prefix, dict(IMAGE_DESKTOP_RED='1' if self.args.baseline_source and not root else '0', IMAGE_DESKTOP_ROOT=root))
        if self.args.baseline_source and not root:
            self.check('desktop-acknowledged-before-qt-presentation', any(not row['visible'] or row['transitioning']
                       for row in result['completions']), result, red=True)
            return result
        self.check(prefix+'-actual-fixture-configuration', result['effective'] == dict(overviewBlur=0, overviewTint=0,
                   transitionDuration=200), result['effective'])
        for endpoint in ('desktop', 'overview'):
            for name in ('valid', 'invalid', 'newest'):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check(prefix+'-'+endpoint+'-'+name, center == list(COLORS[0]), center)
            width, height, rgba = read_png(output/('valid-'+endpoint+'.png'))
            edge = list(rgba[(height//2*width+width//16)*4:(height//2*width+width//16)*4+4])
            self.check(prefix+'-'+endpoint+'-transparent-edge', edge[3] <= 10, edge)
            for index, name in enumerate(('none','fade','wipe','disc','stripes','pixelate','honeycomb')):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check(prefix+'-'+endpoint+'-'+name, center == list(COLORS[index % 2 + 1]), center)
            for name in ('solid', 'solid-invalid'):
                center = pixel(output/(name+'-'+endpoint+'.png'))
                self.check(prefix+'-'+endpoint+'-'+name, center == [18,52,86,255], center)
            self.check(prefix+'-'+endpoint+'-retained-complete-texture',
                       read_png(output/('valid-'+endpoint+'.png')) == read_png(output/('invalid-'+endpoint+'.png'))
                       and read_png(output/('solid-'+endpoint+'.png')) == read_png(output/('solid-invalid-'+endpoint+'.png')),
                       dict(imageBefore='valid', imageAfter='invalid', solidBefore='solid', solidAfter='solid-invalid'))
        self.check(prefix+'-explicit-static-representation', all(row['result'].get('frames') == 3
                   and row['result'].get('format') == 'webp' for row in result['snapshots'] if row['name'] in ('valid','newest')),
                   [row for row in result['snapshots'] if row['name'] in ('valid','newest')])
        checks = []
        for index, row in enumerate(result['completions']):
            name = Path(row['path']).name
            expected = ([18,52,86,255] if row['path'].startswith('solid:') else list(COLORS[0]) if name == 'Motion.webp'
                        else list(COLORS[int(name[6])]) if name.startswith('frame-') else None)
            capture = output/('ack-'+str(index)+'.png')
            observed = pixel(capture) if capture.is_file() else None
            checks.append(dict(event=row, observed=observed, expected=expected, captured=capture.is_file()))
        self.check(prefix+'-acknowledgment-after-presented-ready', len(checks) >= 9
                    and all(row['expected'] is not None and row['captured'] and row['event'].get('visible') is True
                            and row['observed'] == row['expected'] and not row['event']['transitioning'] for row in checks), checks)
        self.check(prefix+'-failure-reason', all(row['reason'] for row in result['snapshots']
                   if row['name'] in ('invalid','solid-invalid')), result['snapshots'])
        self.check(prefix+'-destruction-retires-all-interests', result['destroyed'] and not self.retired_acquisitions(prefix), result)
        return result

    def software_wallpaper_baseline(self):
        if os.environ.get('QT_QUICK_BACKEND') != 'software' or not self.args.baseline_source or not self.args.baseline_plugins:
            raise ValueError('Software comparison requires Qt Software and both immutable baseline trees')
        inputs = self.work / 'fixtures'
        create_fixtures(inputs, self.commands)
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding/desktop-wallpaper.qml'
        for variant, shell, plugins in (('baseline', self.args.baseline_source, self.args.baseline_plugins),
                                        ('candidate', self.args.source, self.args.plugins)):
            for kind, plugin in (('desktop', ''), ('parallax', str(plugins / 'parallax-wallpaper/ParallaxBackground.qml'))):
                name = f'{variant}-{kind}'
                result, output = self.qt(shell, fixture, inputs, name, dict(IMAGE_DESKTOP_SOFTWARE_PROBE='1', IMAGE_DESKTOP_ROOT=plugin))
                width, height, rgba = read_png(output / 'software-desktop.png')
                nontransparent = sum(alpha != 0 for alpha in rgba[3::4])
                snapshot = result['snapshots'][0]
                self.check('shader-software-' + name, len(result['snapshots']) == 1 and snapshot['ready']
                           and snapshot['current'].endswith('/Motion.webp') and width > 0 and height > 0 and nontransparent == 0,
                           dict(width=width, height=height, nontransparent=nontransparent, snapshot=snapshot))

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
                       and all(row['status'] == 1 and row['animationIntent'] == 'still' for row in motion)
                       and centers == [list(COLORS[0])]*11, dict(rows=motion,centers=centers))
            heic = [row for row in result['snapshots'] if row['cohort'] == cohort and row['index'] == 2]
            heic_pixels = [pixel(path) for path in output.glob(cohort+'-image-2-*.png')]
            self.check('wallpaper-gallery-'+cohort+'-heic-pixels',len(heic) == 1 and heic[0]['status'] == 1
                       and len(heic_pixels) == 1 and max(abs(a-b) for a,b in zip(heic_pixels[0],COLORS[0])) <= 8,heic)
            failed = [row for row in result['snapshots'] if row['cohort'] == cohort and row['index'] == 1]
            self.check('wallpaper-gallery-'+cohort+'-honest-failure',len(failed) == 1 and failed[0]['status'] == 3
                       and failed[0]['reason'],failed)
            width,height,pixels = read_png(output/(cohort+'-failure-tile.png'))
            # The warning badge is anchored to the lower right of the preview.
            # Exclude the filename and decorative chrome to its left, then count
            # equivalent opaque warning pixels in the composited tile.
            badge = (pixels[(y*width+x)*4:(y*width+x+1)*4]
                     for y in range(height//2,height) for x in range(3*width//4,width))
            warning = red_warning_coverage(badge, result['warningColor'])
            self.check('wallpaper-gallery-'+cohort+'-unobscured-warning',warning > 10,
                       dict(warningCoverage=warning,color=result['warningColor'],width=width,height=height))
        self.check('wallpaper-gallery-real-http-misleading-types',set(requests) == {'/motion.jpg','/bad.jpg','/heic.jpg'},requests)
        self.check('wallpaper-gallery-close-retires-presentations', result['retired'], result)
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
        if self.args.baseline_source is not None:
            actual = set(stages['union']['paths'])
            self.check('old-wallpaper-scan-loses-part-of-the-union', list(stages) == ['union']
                       and bool(actual) and actual < expected, stages['union'], red=True)
            return result
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
        red = self.args.case == 'wizard-red'
        source = self.args.source
        if red:
            source = self.args.baseline_source
            if source is None or source.resolve() == self.args.source.resolve():
                raise ValueError('Wizard red requires a separate immutable pre-admission wizard source')
        fixture = self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-wizard.qml'
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
            result, output = self.qt(source, fixture,
                inputs, 'wallpaper-wizard', dict(IMAGE_WIZARD_RED='1' if red else '0',
                IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}', NIRI_SOCKET=''))
            if not red:
                extra, extra_output = self.qt(source, fixture,
                    inputs, 'wallpaper-wizard-extra', dict(IMAGE_WIZARD_EXTRA='1',
                    IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}', NIRI_SOCKET=''))
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        (self.out/'http-requests.json').write_text(json.dumps(requests, indent=2)+'\n')
        stages = {row['name']: row for row in result['snapshots']}
        if red:
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
                   and extra_stages['partial']['scale'] == 1 and Path(extra_stages['partial']['other']).suffix == '.webp'
                   and Path(extra_stages['partial']['other']).read_bytes() == data
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
        self.check('wizard-final-quiescence', all(self.wallpaper_quiet(row) and row['queue'] == 0 and row['state'] == 'Idle'
                   for row in (result, extra)) and not any(self.retired_acquisitions(n) for n in ('wallpaper-wizard', 'wallpaper-wizard-extra')),
                   dict(main=result, extra=extra))
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
        self.check('setup-return-to-displayed-cancels-validation', result['returnPending']
                   and stages['returned']['selected'] == stages['returned']['cached'] == str(inputs / 'Still.webp')
                   and stages['returned']['state'] == 'ready' and pixel(output / 'returned.png') == list(COLORS[0]),
                   stages['returned'])
        gallery_centers = [pixel(path) for path in output.glob('gallery-*.png')]
        self.check('setup-gallery-is-static-frame-zero', len(result['galleryFrames']) == 11
                   and all(row['status'] == 1 and row['result']['frames'] == 3 for row in result['galleryFrames'])
                   and gallery_centers == [list(COLORS[0])]*11,
                   dict(rows=result['galleryFrames'], centers=gallery_centers))
        self.check('setup-destruction-retires-all-interests', result['destroyed'] and not self.retired_acquisitions('wallpaper-setup'), result)
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
        self.check('wallpaper-admission-quiescence', self.wallpaper_quiet(result), result)
        failure_notices = [row for row in result['notices'] if 20 <= row['tick'] < 60]
        self.check('wallpaper-failure-is-user-visible-not-success', len(failure_notices) == 2
                   and all(row['type'] == 'error' and row['title'] and row['reason'] for row in failure_notices), result['notices'])
        rejected, rejected_output = self.qt(self.args.source,
            self.args.source/'Scripts/dev/fixtures/image-decoding/wallpaper-rejection.qml', inputs,
            'wallpaper-rejection', dict(IMAGE_USE_ORIGINAL='1'))
        self.check('wallpaper-rejection-never-publishes-success', not rejected['completions'] and not rejected['events']
                   and rejected['path'] == str(inputs/'frame-0.png') and not rejected['favorites']
                   and len(rejected['callbacks']) == 1 and not rejected['callbacks'][0]['success']
                   and rejected['callbacks'][0]['detail']['reason'], rejected)
        self.check('wallpaper-rejection-keeps-prior-rendered-pixels', pixel(rejected_output/'after.png') == list(COLORS[0])
                   and read_png(rejected_output/'before.png') == read_png(rejected_output/'after.png'), rejected)
        self.check('wallpaper-rejection-visible-and-quiescent', len(rejected['notices']) == 2
                   and all(row['type'] == 'error' and row['reason'] for row in rejected['notices'])
                   and self.wallpaper_quiet(rejected), rejected)
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
        badge_region = (pixels[(y*width+x)*4:(y*width+x+1)*4]
                        for y in range(height//2,height) for x in range(width//2,width))
        warning = red_warning_coverage(badge_region, result['warningColor'])
        self.check('rounded-error-warning-is-actually-presented', warning > 10, dict(warningCoverage=warning))
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
        def with_held_request(source, name, assembled=False):
            release = threading.Event()
            started = threading.Condition()
            held = dict(started=0, closedBeforeRelease=0, answered=0,
                        workersAtAdmission=None, workersAtRelease=None, workersAfterExit=None)
            cache = self.work / (name + '-profile') / 'cache'
            data = (inputs / 'frame-0.png').read_bytes()

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/held.png':
                        with started:
                            held['started'] += 1
                            started.notify_all()
                        deadline = time.monotonic() + 8
                        while not release.is_set() and time.monotonic() < deadline:
                            readable, _, _ = select.select([self.connection], [], [], .05)
                            if readable and peer_closed(self.connection):
                                with started:
                                    if not release.is_set():
                                        held['closedBeforeRelease'] += 1
                                        started.notify_all()
                                break
                        if not release.wait(8):
                            self.send_error(504)
                            return
                        try:
                            self.respond(data)
                        except (BrokenPipeError, ConnectionResetError):
                            pass  # Retirement can close the original client socket.
                        finally:
                            with started:
                                held['answered'] += 1
                                started.notify_all()
                    elif self.path == '/admitted':
                        with started:
                            both_admitted = started.wait_for(lambda: held['started'] >= 2, timeout=8)
                        if both_admitted:
                            held['workersAtAdmission'] = sorted(p.name for p in cache.glob('image-source-*'))
                            self.respond()
                        else:
                            self.send_error(504)
                    elif self.path == '/release':
                        with started:
                            started.wait_for(lambda: held['closedBeforeRelease'] == 2, timeout=3)
                            held['workersAtRelease'] = sorted(p.name for p in cache.glob('image-source-*'))
                            release.set()
                            both_answered = started.wait_for(lambda: held['answered'] >= 2, timeout=8)
                        if both_answered:
                            self.respond()
                        else:
                            self.send_error(504)
                    else:
                        self.send_error(404)

                def respond(self, body=b''):
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, *_):
                    pass

            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                observed, output = self.qt(source, fixture, inputs, name,
                                           dict(IMAGE_HELD_SERVER=f'http://127.0.0.1:{server.server_port}'), assembled=assembled)
                deadline = time.monotonic() + 3
                while (workers := sorted(p.name for p in cache.glob('image-source-*'))) and time.monotonic() < deadline:
                    time.sleep(.02)
                held['workersAfterExit'] = workers
                (output / 'held-http.json').write_text(json.dumps(held, indent=2) + '\n')
                return observed, output, held
            finally:
                release.set()
                server.shutdown()
                thread.join()
                server.server_close()

        result, output, held = with_held_request(self.args.source, 'backdrops')
        def review(observed, captures, held, prefix):
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
            self.check(prefix + 'hide-retires-display', all(row['state'] == 'idle' and not row['resolved']
                       for row in observed['hidden'].values()), observed['hidden'])
            admitted, before_release, after_release = observed['heldStages']
            self.check(prefix + 'held-request-admitted-and-retired',
                       held['started'] == held['closedBeforeRelease'] == held['answered'] == 2, held)
            self.check(prefix + 'shared-download-worker-retires-at-exit', len(held['workersAtAdmission']) == 1
                       and held['workersAtAdmission'] == held['workersAtRelease'] and held['workersAfterExit'] == [], held)
            for name in ('backdrop', 'lock'):
                before_image = captures / ('held-before-' + name + '.png')
                after_image = captures / ('held-after-' + name + '.png')
                r, g, b, *_ = pixel(before_image)
                self.check(prefix + name + '-retired-request-cannot-replace-new-pixels',
                           admitted[name]['state'] == 'loading' and before_release[name]['state'] == 'ready'
                           and after_release[name] == before_release[name]
                           and b > 80 and b > 2*r and b > 2*g and read_png(before_image) == read_png(after_image),
                           dict(admitted=admitted[name], before=before_release[name], after=after_release[name], center=[r, g, b]))
        review(result, output, held, 'backdrops-')
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
        locked, locked_output, locked_held = with_held_request(lock, 'backdrops-locker', assembled=True)
        review(locked, locked_output, locked_held, 'backdrops-installed-')
        return result

    def legacy(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/legacy.qml', inputs, 'legacy')
        rows = {row['name']: row for row in result['presented']}
        for name, source in (('thumbnail', 'Motion.webp'), ('large', 'Motion.webp'), ('avatar', 'Still.webp'),
                             ('misleading', 'Misleading.png'), ('literal', 'bracket[0]: image.webp')):
            row = rows[name]
            path = urlsplit(row['url'])
            self.check('legacy-' + name + '-uses-original', path.scheme == 'file' and not path.netloc
                       and Path(unquote(path.path)) == inputs / source, row)
            center = pixel(output / (name + '.png'))
            self.check('legacy-' + name + '-presented-pixels', row['status'] == 1
                       and max(abs(a - b) for a, b in zip(center, COLORS[0])) <= 8,
                       dict(consumer=row, center=center))
        avatar = output / 'avatar.png'
        self.check('legacy-circular-avatar-alpha', pixel(avatar, 0, 0)[3] == 0 and pixel(avatar)[3] == 255,
                   dict(corner=pixel(avatar, 0, 0), center=pixel(avatar)))
        for name in ('corrupt', 'missing'):
            row = rows[name]
            self.check('legacy-' + name + '-honest-failure', row['status'] == 3 and not row['url'] and row['reason'], row)
        self.check('legacy-completion-retires-interests', result['retired'] == 7, result)
        self.check('legacy-cancelled-display-is-retired', result['cancelledStatus'] == 0
                   and result['cancelledDeliveries'] == 0, result)
        return result

    def chooser(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        video = inputs / 'Large.mp4'
        encoded = self.command(['ffmpeg', '-nostdin', '-v', 'error', '-loop', '1', '-i', inputs / 'frame-0.png',
                                '-t', '1', '-c:v', 'libx264', '-threads', '1', '-pix_fmt', 'yuv420p', video])
        if encoded.returncode:
            raise AssertionError('Could not encode large chooser fixture: ' + encoded.stderr)
        # A valid sparse MP4: append a skippable free atom, not arbitrary
        # bytes in the sample table. Cross the previous 256 MiB input cap.
        padding = 257 * 1024 * 1024
        with video.open('r+b') as stream:
            offset = stream.seek(0, 2)
            stream.write(padding.to_bytes(4, 'big') + b'free')
            stream.truncate(offset + padding)
        self.check('chooser-fixture-exceeds-old-video-limit', video.stat().st_size > 256 * 1024 * 1024,
                   video.stat().st_size)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/chooser.qml', inputs, 'chooser')
        self.check('chooser-off-is-idle', len(result['inactive']) == 3 and all(
            row['state'] == 'idle' and not row['source'] and not row['active'] for row in result['inactive']), result['inactive'])
        self.check('chooser-exercises-every-view-and-recovers', len(result['tiles']) == 24 and
                   len(result['failures']) == 6, dict(tiles=len(result['tiles']), failures=len(result['failures'])))
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
                   and result['quicklook']['frames'] == 3 and any(r['playing'] for r in result['frames'])
                   and {tuple(p) for p in colors} == set(COLORS), dict(consumer=result['quicklook'], colors=colors, frames=result['frames']))
        self.check('chooser-close-retires-presentations', len(result['retired']) == 3 and all(
            row['state'] == 'idle' and not row['source'] and not row['active'] for row in result['retired']), result['retired'])
        # Encode a landscape raster, then set a display matrix without rotating
        # the stored pixels. Upright playback has red on top and green below.
        red, green = ('0x%02X%02X%02X' % color[:3] for color in COLORS[:2])
        landscape = self.work / 'landscape.mp4'
        encoded = self.command(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', f'color=c={green}:s=160x90:r=8:d=1',
            '-vf', f'drawbox=x=80:y=0:w=80:h=90:color={red}:t=fill', '-c:v', 'libx264', '-threads', '1',
            '-pix_fmt', 'yuv420p', landscape])
        if encoded.returncode:
            raise AssertionError('Independent video fixture encoding failed: ' + encoded.stderr)
        rotated = self.command(['ffmpeg', '-nostdin', '-v', 'error', '-display_rotation', '90', '-i', landscape,
            '-c', 'copy', inputs / 'Shared.mp4'])
        if rotated.returncode:
            raise AssertionError('Video fixture display matrix failed: ' + rotated.stderr)
        shared, shared_output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/picker-sharing.qml',
            inputs, 'picker-sharing')
        self.check('closing-one-picker-retains-other-image', shared['bothReady'] and shared['survived'], shared)
        captured = shared_output / 'survivor.png'
        width, height, _ = read_png(captured)
        observed = [pixel(captured, width // 2, y) for y in (height // 4, height * 3 // 4)]
        self.check('chooser-video-honors-90-degree-display-rotation',
                   all(max(abs(a - b) for a, b in zip(actual, color)) <= 16 for actual, color in zip(observed, COLORS[:2])),
                   dict(captureSize=[width, height], top=observed[0], bottom=observed[1]))
        self.check('last-picker-close-retires-presentation', shared['bothRetired'], shared)
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
                   and calls['standalone']['detail']['originalFormat'] == 'webp'
                   and calls['standalone']['detail']['contentSha256'] == hashlib.sha256((inputs/'Motion.webp').read_bytes()).hexdigest(), calls['standalone'])
        self.check('remote-invalid-download-honest-reason-and-cancelled-callback-retired', not calls['invalid']['success']
                   and not calls['invalid']['path'] and calls['invalid']['detail']['reason']
                   and 'cancelled' not in calls, calls)
        self.check('remote-failed-input-never-emits-downloaded', sorted(row['id'] for row in result['downloads'])
                   == ['motion', 'motion', 'standalone'], result['downloads'])
        errors = [row for row in result['notices'] if row['type'] == 'error']
        self.check('remote-selection-failures-have-visible-useful-errors', len(errors) == 2 and all(row['reason'] for row in errors), errors)
        self.check('remote-final-lifetime-quiescence', self.wallpaper_quiet(result)
                   and not self.retired_acquisitions('remote'), result)
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
            self.args.source / 'Scripts/dev/fixtures/image-decoding' / ('cache-red.qml.in' if red else 'cache.qml'), inputs, name)
        colors = [pixel(output / f'thumbnail-{i}.png') for i in range(3)]
        if redirected:
            self.check('actual-chooser-symlinked-cache-' + ('borrowed' if red else 'refused'),
                (all(row['state']['imageReady'] for row in result['rows']) and colors == [list(COLORS[1])] * 3) if red else
                (all(row['state']['imageReady'] for row in result['rows']) and colors == [list(COLORS[0])] * 3),
                dict(rows=result['rows'], colors=colors), red=red)
        else:
            self.check('actual-chooser-foreign-still-cache-ignored',
                       all(row['state']['imageReady'] for row in result['rows'])
                       and colors == [list(COLORS[0])] * 3, dict(rows=result['rows'], colors=colors), red=red)
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
        self.check('cache-admission-and-retirement', (result['idleInterests'] == result['interests'] == result['requests'] == 0
                   and not result['workerRunning']) if red else (result['idleBeforeAdmission'] and result['idleAfterRetirement']
                   and not self.retired_acquisitions(name)), result)

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
        seed = None
        if not red:
            seed, _ = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/cache-clear-seed.qml',
                              inputs, 'cache-clear-seed')
        result, output = self.qt(self.args.baseline_source if red else self.args.source,
                                 self.args.source / 'Scripts/dev/fixtures/image-decoding' /
                                 ('cache-clear-red.qml.in' if red else 'cache-clear.qml'), inputs, name)
        probes, toasts = result['probes'], result['toasts']
        cache = self.work / (name + '-profile/cache')
        if red:
            released = result['released']
            self.check('actual-clear-button-clicked', result['clicked'] and len(toasts) == 1, toasts)
            self.check('released-adapter-output-was-owner-representation', released['success']
                       and Path(released['path']).is_relative_to(cache / 'thumbnails/atmosphera-representations-v1')
                       and probes['releasedBeforeButton'], dict(released=released, probes=probes))
            self.check('actual-clear-button-leaves-owner-representations', toasts[0]['type'] == 'notice'
                       and probes['releasedAfterButton'] and not result['ownerClear'], dict(probes=probes, toasts=toasts), red=True)
            return result
        self.check('actual-clear-button-clicked', result['clicked'], result['clicked'])
        events = result['events']
        owner = [row for row in events if row['event'] == 'owner']
        sequence = [row for row in events if row['event'] != 'owner']
        self.check('clear-toast-reports-completed-owner-clear', [row['event'] for row in sequence] == ['evicted', 'toast']
                   and len(owner) == 1 and sequence[0]['ticket'] == owner[0]['ticket'] > 0
                   and sequence[0]['result'] == owner[0]['result'] and owner[0]['result']['stage'] == 'complete'
                   and owner[0]['result']['removed'] >= 1 and len(toasts) == 1 and toasts[0]['type'] == 'notice'
                   and toasts[0]['phase'] == 2, dict(events=events, toasts=toasts))
        regenerated_entries = set(probes['regenerated']) - set(probes['cleared'])
        self.check('clear-evicts-populated-decoded-cache', seed['entry'] in regenerated_entries
                   and seed['entry'] in probes['populated'] and seed['entry'] not in probes['cleared'], probes)
        self.check('clear-keeps-live-pixels', max(abs(a - b) for a, b in zip(pixel(output / 'held-after-clear.png'), COLORS[0])) <= 8,
                   pixel(output / 'held-after-clear.png'))
        legacy = cache / 'images/wallpapers'
        self.check('clear-removes-only-shell-legacy-representations',
                   not (legacy / 'large/legacy-key.png').exists()
                   and not (legacy / 'thumbnails/legacy.png').exists()
                   and not (cache / 'images/contributors/legacy.png').exists()
                   and (legacy / 'thumbnails/original.png').is_symlink()
                   and (legacy / 'thumbnails/mpvpaper/plugin.bmp').read_bytes() == b'plugin-owned', str(legacy))
        original = Path(result['retained'])
        self.check('clear-preserves-retained-original', original.is_relative_to(cache / 'images/notifications/retained')
                   and original.read_bytes() == before['Still.webp'], str(original))
        self.check('sources-unchanged', before == {name: (inputs / name).read_bytes() for name in before},
                   sorted(before))
        regenerated = pixel(output / 'regenerated.png')
        self.check('cleared-cache-regenerates', bool(probes['regenerated'])
                   and set(probes['regenerated']) <= set(probes['populated']) and regenerated == list(COLORS[1]),
                   dict(cache=probes['regenerated'], center=regenerated))
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
        def warning(name, *, background=None):
            return warning_coverage(output / (name + '.png'), result['warningColor'], background=background)
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
        coverage = warning('app-corrupt', background=output / 'app-svg.png')
        self.check('theme-decode-failure-is-labelled-fallback', apps['corrupt']['status'] == 1 and apps['corrupt']['failed']
                   and apps['corrupt']['reason'] and apps['corrupt']['source'].endswith('fixture-svg-app.svg')
                   and near(center('app-corrupt'), COLORS[0]) and coverage > 10,
                   dict(consumer=apps['corrupt'], center=center('app-corrupt'), warningCoverage=coverage))
        for kind in ('webp', 'png', 'svg'):
            self.check('icon-set-' + kind + '-mask-presented', not glyphs[kind]['failed']
                       and near(glyph_center('glyph-' + kind), (*icon, 255)) and warning('glyph-' + kind) == 0,
                       dict(consumer=glyphs[kind], center=glyph_center('glyph-' + kind)))
        coverage = warning('glyph-corrupt')
        self.check('icon-set-failure-is-labelled', glyphs['corrupt']['failed'] and glyphs['corrupt']['reason']
                   and not near(glyph_center('glyph-corrupt'), (*icon, 255)) and coverage > 10,
                   dict(consumer=glyphs['corrupt'], warningCoverage=coverage))
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
        def warning(kind):
            return warning_coverage(output / ('icon-' + kind + '.png'), result['warningColor'])
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
                       and warning(kind) == 0,
                       dict(consumer=icons[kind], center=pixel(output / ('icon-' + kind + '.png'))))
        # Quickshell's icon provider answers a missing name with its own
        # placeholder: a provider result presented in process, not a failure.
        self.check('image-icon-provider-presented-in-process', icons['provider']['status'] == 1 and not icons['provider']['failed'],
                   icons['provider'])
        for kind in ('corrupt', 'unprovided'):
            coverage = warning(kind)
            self.check('image-icon-' + kind + '-failure-labelled', icons[kind]['status'] == 3 and icons[kind]['failed']
                       and icons[kind]['reason'] and coverage > 10,
                       dict(consumer=icons[kind], warningCoverage=coverage))
        self.check('image-icon-provider-never-reaches-cli', icons['unprovided']['code'] == 'invalid-source'
                   and 'provider' in icons['unprovided']['reason'], icons['unprovided'])
        self.check('bar-custom-icon-webp-presented', near(control['center'], COLORS[0]) and control['art'] > 40, control)
        self.check('app-options-theme-icon-webp-presented', options['art'] > 15, options)
        return result

    def launcher(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        red = self.args.case == 'launcher-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Launcher red requires an explicit immutable baseline source')
        result, output = self.qt(self.args.baseline_source if red else self.args.source,
                                 self.args.source / 'Scripts/dev/fixtures/image-decoding/launcher.qml', inputs, self.args.case)
        expected = {f'{view}-{kind}.png' for view in ('list', 'grid') for kind in ('art', 'failed', 'noart')}
        missing = sorted(name for name in expected if not (output / name).is_file())
        self.check('launcher-captures-complete', not missing, dict(missing=missing))
        def near(actual, expected, tolerance=8):
            return max(abs(a - b) for a, b in zip(actual, expected)) <= tolerance
        def counts(view, kind, *, measure_badge=False):
            name = f'{view}-{kind}'
            width, height, pixels = read_png(output / (name + '.png'))
            rows = [pixels[i * 4:i * 4 + 4] for i in range(width * height)]
            if measure_badge:
                # The fixed fixture places the list badge to the left of the
                # label and the grid warning at the lower right of the art
                # tile, above the label. Exclude subpixel text fringing.
                xs, ys = ((range(64), range(height)) if view == 'list'
                          else (range(64, width), range(48, 80)))
                warning = red_warning_coverage((rows[y * width + x] for y in ys for x in xs), result['warningColor'])
            else:
                warning = sum(near(p, result['warningColor']) for p in rows)
            return dict(art=sum(near(p, COLORS[0]) for p in rows), icon=sum(near(p, COLORS[1]) for p in rows),
                        warning=warning)
        self.check('launcher-rows-instantiated', result['listCount'] == result['gridCount'] == 3, result)
        for view in ('list', 'grid'):
            failed = counts(view, 'failed', measure_badge=not red)
            if red:
                self.check(view + '-failed-art-shows-ordinary-icon', failed['icon'] > 50 and failed['warning'] == 0,
                           failed, red=True)
                continue
            art, noart = counts(view, 'art'), counts(view, 'noart')
            self.check(view + '-art-presented', art['art'] > 50 and art['warning'] == 0 and art['icon'] == 0, art)
            self.check(view + '-failed-art-distinct-labelled', failed['warning'] > 10 and failed['icon'] == 0
                       and failed['art'] == 0, failed)
            self.check(view + '-no-art-ordinary-icon', noart['icon'] > 50 and noart['warning'] == 0, noart)
        return result

    def text(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        red = self.args.case == 'text-red'
        if red and self.args.baseline_source is None:
            raise ValueError('Text red requires an explicit immutable baseline source')
        fixture = self.args.source / 'Scripts/dev/fixtures/image-decoding' / (self.args.case + '.qml')
        fetched = []
        payload = (inputs / 'frame-0.png').read_bytes()
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                fetched.append(self.path)
                self.send_response(200)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.baseline_source if red else self.args.source, fixture, inputs, self.args.case,
                                     dict(IMAGE_TEXT_HTTP='http://127.0.0.1:' + str(server.server_port)))
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()
        (self.out / 'http.json').write_text(json.dumps(fetched, indent=2) + '\n')
        def near(actual, expected, tolerance=10):
            return max(abs(a - b) for a, b in zip(actual, expected)) <= tolerance
        def count(name, color):
            width, height, pixels = read_png(output / (name + '.png'))
            return sum(near(pixels[i * 4:i * 4 + 4], color) for i in range(width * height))
        if red:
            if self.args.qt_webp == 'absent':
                self.check('rich-text-webp-image-not-presented', count('rich', COLORS[0]) == 0, count('rich', COLORS[0]), red=True)
            self.check('markdown-inline-html-image-dropped', count('markdown', COLORS[0]) == 0, count('markdown', COLORS[0]), red=True)
            return result
        def center(name, state):
            return pixel(output / (name + '.png'), int(state['x'] + state['width'] / 2), int(state['y'] + state['height'] / 2))
        self.check('text-parser-resource-and-syntax-boundaries', all(result['parserChecks'].values()), result['parserChecks'])
        before, after = result['retainedBefore'], result['retained']
        self.check('text-only-update-retains-ready-image-sizes', len(after['states']) == 2
                   and all(s['state'] == 'ready' and s['placed'] and s['naturalWidth'] > 0 for s in after['states'])
                   and [(s['width'], s['height']) for s in before['states']] == [(s['width'], s['height']) for s in after['states']]
                   and near(center('retained', after['states'][0]), COLORS[1])
                   and near(center('retained', after['states'][1]), COLORS[0]), dict(before=before, after=after))
        self.check('markdown-backgrounds-blocked-before-conversion', not fetched
                   and result['guardedMarkdown']['imageCount'] == 0
                   and 'markdown cell' in result['guardedMarkdown']['plain']
                   and 'url(literal.png)' in result['guardedMarkdown']['plain']
                   and count('guarded-markdown', COLORS[0]) == 0,
                   dict(consumer=result['guardedMarkdown'], fetched=fetched))
        rich, markdown, failing, replaced, plain = (result[k] for k in ('rich', 'markdown', 'failing', 'replaced', 'plain'))
        slot = '\ufffc'
        self.check('rich-images-found-comment-ignored', rich['imageCount'] == 3 and rich['plain'].count(slot) == 3
                   and all(s['state'] == 'ready' and s['placed'] for s in rich['states']), rich)
        self.check('rich-text-and-link-kept', all(w in rich['plain'] for w in ('A bold link', 'tail', 'again'))
                   and rich['states'][0]['link'] == 'https://example.org/x' and not rich['states'][2]['link'], rich)
        self.check('rich-images-presented-at-slots', all(near(center('rich', s), COLORS[0]) for s in rich['states'])
                   and [s['width'] for s in rich['states']] == [32, 24, 32], [center('rich', s) for s in rich['states']])
        self.check('markdown-images-found-code-and-escapes-kept', markdown['imageCount'] == 3 and markdown['plain'].count(slot) == 3
                   and all(w in markdown['plain'] for w in ('Title', 'Text em', '![code](nope.png)', 'escaped', '![indented](nope.png)')),
                   markdown)
        self.check('markdown-inline-html-image-kept', markdown['states'][1]['state'] == 'ready'
                   and markdown['states'][1]['width'] == 20 and markdown['states'][1]['height'] == 20, markdown['states'][1])
        moving = markdown['states'][2]
        frames = [center(p.stem, moving) for p in sorted(output.glob('markdown-*.png'))]
        self.check('markdown-reference-image-animates', moving['state'] == 'ready' and moving['frames'] == 3
                   and len({tuple(f) for f in frames if f[3] == 255}) >= 2, dict(state=moving, frames=frames))
        self.check('markdown-still-presented', near(center(sorted(output.glob('markdown-*.png'))[-1].stem, markdown['states'][0]), COLORS[0]),
                   markdown['states'][0])
        state = failing['states'][0]
        self.check('failed-image-labelled-placeholder', state['state'] == 'unavailable' and state['reason']
                   and count('failing', result['warningColor']) > 10 and 'before' in failing['plain'] and 'after' in failing['plain'],
                   dict(state=state, warning=count('failing', result['warningColor'])))
        self.check('replaced-source-presents-new-image', near(center('replaced-before', replaced['states'][0]), COLORS[0])
                   and near(center('replaced-after', replaced['states'][0]), COLORS[1]), replaced)
        styled, light = result['styled'], result['styledLight']
        self.check('styled-text-keeps-line-breaks-and-images', styled['imageCount'] == 1 and styled['states'][0]['state'] == 'ready'
                   and 'line one\nline two' in styled['plain'], styled)
        self.check('styled-text-without-images-is-lightweight', light['lightweight'] and light['imageCount'] == 0
                   and light['truncated'], light)
        self.check('plain-text-acquires-no-image-work', plain['imageCount'] == 0 and plain['plain'] == 'Plain text only, no image work',
                   plain)
        capped = result['capped']
        kept, cut = capped['states']
        self.check('capped-lines-keep-first-image-cut-later-one', capped['truncated'] and capped['lineCount'] >= 3
                   and capped['height'] < capped['contentHeight'] and kept['state'] == 'ready' and kept['placed']
                   and near(center('capped', kept), COLORS[1]) and cut['y'] >= capped['height']
                   and count('capped', COLORS[0]) == 0 and 'second line' in capped['plain'],
                   dict(consumer=capped, cut=count('capped', COLORS[0])))
        backgrounds = result['backgrounds']
        self.check('rich-background-images-not-loaded-text-kept', backgrounds['imageCount'] == 0 and not fetched
                   and count('backgrounds', COLORS[0]) == 0
                   and all(w in backgrounds['plain'] for w in ('cell text', 'file', 'styled paragraph')),
                   dict(consumer=backgrounds, fetched=fetched, painted=count('backgrounds', COLORS[0])))
        tip = result['tooltip']
        self.check('tooltip-rich-image-presented-and-sized', not tip.get('missing') and tip['popupVisible']
                   and tip['imageCount'] == 1 and tip['states'][0]['state'] == 'ready' and tip['states'][0]['placed']
                   and near(center('tooltip', tip['states'][0]), COLORS[0])
                   and tip['popupWidth'] >= tip['states'][0]['x'] + 40 and tip['popupHeight'] >= tip['height']
                   and 'tip text' in tip['plain'] and 'after' in tip['plain'], tip)
        label, plain_label = result['label'], result['labelPlain']
        self.check('settings-description-image-presented', not label['lightweight'] and label['imageCount'] == 1
                   and label['states'][0]['state'] == 'ready' and near(center('label', label['states'][0]), COLORS[1])
                   and 'desc bold' in label['plain'], label)
        self.check('settings-description-without-image-lightweight', plain_label['lightweight']
                   and plain_label['imageCount'] == 0 and plain_label['plain'] == 'plain <b>description</b>', plain_label)
        green = (0, 255, 0, 255)
        self.check('link-color-rich-and-markdown', count('linked', green) > 20 and count('linked-markdown', green) > 20
                   and result['linked']['plain'] == 'LINKLINKLINK', dict(rich=count('linked', green), markdown=count('linked-markdown', green)))
        plain_format = result['plainFormat']
        self.check('plain-format-shows-markup-as-text', plain_format['imageCount'] == 0 and '<img src=' in plain_format['plain']
                   and count('plain-format', COLORS[0]) == 0, plain_format)
        notes = result['changelog']
        self.check('changelog-notes-images-presented', not notes.get('missing') and notes['format'] == 'markdown'
                   and '0.0.1' in notes['releaseContent'] and notes['imageCount'] == 2
                   and all(s['state'] == 'ready' and s['placed'] for s in notes['states'])
                   and near(center('changelog', notes['states'][0]), COLORS[0])
                   and center('changelog', notes['states'][1])[3] > 0
                   and notes['states'][1]['naturalWidth'] == 128
                   and all(w in notes['plain'] for w in ('Notes with art', 'in the text', 'a link')), notes)
        return result

    def changed_plugin_qml(self):
        """Plugin QML that differs from the baseline plugins tree (new files included)."""
        if self.args.baseline_plugins is None:
            raise ValueError('The plugins case needs --baseline-plugins to find changed plugin QML')
        changed = []
        for path in sorted(self.args.plugins.rglob('*.qml')):
            relative = path.relative_to(self.args.plugins)
            if any(part.startswith('.') for part in relative.parts):
                continue
            base = self.args.baseline_plugins / relative
            if not base.is_file() or base.read_bytes() != path.read_bytes():
                changed.append(path)
        return changed

    def formats(self):
        import gzip

        listed = self.command(['bash', '-c', 'source "$1"; printf "%s\n" "${imvqml_readers[@]}"',
                               'image-decoding-dependencies', self.args.source / '.devcontainer/imvqml-arch-runtime.sh'])
        readers = listed.stdout.splitlines()
        if listed.returncode or not readers:
            raise AssertionError('Cannot read the ImvQml runtime reader dependency list')
        packages = {name: self.command(['pacman', '-Q', name]).returncode == 0 for name in readers}
        self.check('format-reader-package-condition', all(installed == (self.args.qt_webp == 'present')
                                                          for installed in packages.values()), packages)
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        stills = ('frame-0.png', 'Still.webp', 'Still.jpg', 'Still.svg', 'Still.tiff', 'Still.avif', 'Still.heic',
                  'Still.jxl', 'Misleading.png', 'Oriented.jpg')
        restored = {'Still.bmp': COLORS[0]}
        for extension, original in (('jpeg', 'jpg'), ('tif', 'tiff'), ('heif', 'heic')):
            shutil.copyfile(inputs / ('Still.' + original), inputs / ('Still.' + extension))
            restored['Still.' + extension] = COLORS[0]
        (inputs / 'Still.svgz').write_bytes(gzip.compress((inputs / 'Still.svg').read_bytes(), mtime=0))
        restored['Still.svgz'] = COLORS[0]
        # Author simple gray pixels for the grayscale/HDR formats so the
        # oracle does not depend on an encoder's color-space conversion.
        for ext in ('ico', 'ppm', 'pnm', 'pgm', 'pbm', 'jp2', 'j2k', 'exr', 'hdr', 'dds', 'tga', 'icns'):
            path = inputs / ('Still.' + ext)
            if ext == 'icns':
                image = colored_png((255, 255, 255, 255), 128, 128)
                size = (len(image) + 8).to_bytes(4, 'big')
                path.write_bytes(b'icns' + (len(image) + 16).to_bytes(4, 'big') + b'ic07' + size + image)
            else:
                encoded = self.command(['magick', '-size', '96x64', 'xc:white',
                                        '-type', 'TrueColor', str(path)])
                if encoded.returncode:
                    raise AssertionError(f'Could not encode independent {ext} fixture: {encoded.stderr}')
                if ext == 'tga':
                    # Qt's reader requires a TGA 2.0 footer; ImageMagick's
                    # uncompressed raster is otherwise a valid TGA 1.0 file.
                    with path.open('ab') as raster:
                        raster.write(bytes(8) + b'TRUEVISION-XFILE.\0')
            restored[path.name] = (255, 255, 255, 255)
        manifest['files'].update({name: dict(sha256=hashlib.sha256((inputs / name).read_bytes()).hexdigest(),
                                            size=(inputs / name).stat().st_size) for name in restored})
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/formats.qml',
                                 inputs, 'formats', {'IMAGE_FORMAT_NAMES': json.dumps([
                                     *stills, *restored, 'Motion.webp', 'Motion.gif', 'Corrupt.webp', 'Still.webp'])})
        rows = result['images']
        tested_extensions = {Path(row['name']).suffix[1:] for row in rows if row['name'] != 'Corrupt.webp'}
        self.check('formats-cover-every-recognized-extension', tested_extensions == set(result['extensions']),
                   dict(tested=sorted(tested_extensions), recognized=sorted(result['extensions'])))
        observed = {name: [row for row in rows if row['name'] == name] for name in {row['name'] for row in rows}}
        def center(row):
            return pixel(output / (row['capture'] + '.png'))
        for name, expected in {**dict.fromkeys(stills, COLORS[0]), **restored}.items():
            samples = observed[name]
            if self.args.qt_webp == 'absent' and Path(name).suffix in ('.dds', '.icns', '.tga'):
                self.check('optional-reader-absent-' + name,
                           all(row['state'] == 'unavailable' and row['code'] == 'unsupported-format' for row in samples), samples)
                continue
            self.check('format-' + name, all(row['state'] == 'ready' and
                       max(abs(a - b) for a, b in zip(center(row), expected)) <= 12 for row in samples), samples)
        jpeg = observed['Oriented.jpg'][0]
        self.check('format-jpeg-orientation', jpeg['width'] == manifest['height'] and jpeg['height'] == manifest['width'], jpeg)
        for name in ('Motion.webp', 'Motion.gif'):
            samples = observed[name]
            pixels = {tuple(center(row)) for row in samples}
            self.check('format-animated-' + name, len(samples) == 18 and all(row['state'] == 'ready' and
                       row['frames'] == 3 for row in samples) and all(any(max(abs(a-b) for a,b in zip(want, got)) <= 8
                       for got in pixels) for want in COLORS), dict(pixels=sorted(pixels), samples=samples))
        self.check('malformed-image-recovers-on-next-source', rows[-2]['state'] == 'unavailable' and rows[-2]['code'] and
                   rows[-1]['name'] == 'Still.webp' and rows[-1]['state'] == 'ready' and
                   center(rows[-1]) == list(COLORS[0]), rows[-2:])

    def rotated_video(self):
        inputs = self.work / 'fixtures'
        create_fixtures(inputs, self.commands)
        red, green = ('0x%02X%02X%02X' % color[:3] for color in COLORS[:2])
        base = inputs / 'Landscape.mp4'
        video = inputs / 'Rotated.mp4'
        for argv in (
            ['-f', 'lavfi', '-i', f'color=c={green}:s=160x90:r=8:d=1', '-vf',
             f'drawbox=x=80:y=0:w=80:h=90:color={red}:t=fill', '-c:v', 'libx264', '-threads', '1', '-pix_fmt', 'yuv420p', base],
            ['-display_rotation', '90', '-i', base, '-c', 'copy', video],
        ):
            made = self.command(['ffmpeg', '-nostdin', '-v', 'error', *argv])
            if made.returncode:
                raise AssertionError(made.stderr)
        metadata = self.command(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', video])
        stream = json.loads(metadata.stdout)['streams'][0]
        self.check('fixture-has-landscape-raster-and-real-90-degree-matrix', (stream['width'], stream['height']) == (160, 90)
                   and any(row.get('rotation') == 90 for row in stream.get('side_data_list', [])), stream)
        for renderer, env in (('opengl', {'QT_QUICK_BACKEND': '', 'QSG_RHI_BACKEND': 'opengl'}),
                              ('software', {'QT_QUICK_BACKEND': 'software'})):
            result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/rotated-video.qml',
                                     inputs, 'rotated-video-' + renderer, env)
            self.check(renderer + '-renderer-observed', result['renderer'] == renderer, result)
            self.check(renderer + '-video-and-wallpaper-export-are-upright',
                       [result[k] for k in ('width', 'height', 'exportWidth', 'exportHeight')] == [90, 160, 90, 160]
                       and result['generated'] and Path(result['exported']).is_file(), result)
            observed = [pixel(output / 'video.png', x, y) for x in (45, 135) for y in (40, 120)]
            self.check(renderer + '-video-and-export-have-rotated-pixels', all(
                max(abs(a - b) for a, b in zip(actual, want)) <= 16
                for actual, want in zip(observed, COLORS[:2] * 2)), observed)

    def plugins(self):
        installed = self.command(['pacman', '-Q', 'qt6-imageformats']).returncode == 0
        self.check('genuine-qt-webp-package-condition', installed == (self.args.qt_webp == 'present'), dict(installed=installed))
        inputs = self.work / 'fixtures'
        manifest = create_fixtures(inputs, self.commands)
        wallcards = inputs / 'wallcards'
        wallcards.mkdir()
        for name in ('Still.webp', 'frame-1.png', 'Corrupt.webp'):
            shutil.copyfile(inputs / name, wallcards / name)
        escaped_name = 'Still #1?.webp'
        shutil.copyfile(inputs / 'Still.webp', wallcards / escaped_name)
        # Video wallpaper plugins: one real video in the first fixture color and
        # one broken file, through the owner's video thumbnails.
        videos = inputs / 'videos'
        videos.mkdir()
        made = self.command(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=0x%02X%02X%02X:s=160x90:r=8:d=2' % COLORS[0][:3],
                             '-c:v', 'mpeg4', '-q:v', '1', videos / 'Red.mp4'])
        if made.returncode:
            raise RuntimeError('Cannot create the fixture video: ' + made.stderr[-400:])
        (videos / 'Broken.mp4').write_bytes(b'not a video')
        (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        changed = self.changed_plugin_qml()
        (self.out / 'changed-plugin-qml.txt').write_text(''.join(str(p) + '\n' for p in changed))
        self.plugin_lint = changed
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(404)
                self.end_headers()
            def log_message(self, *_args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/plugins.qml', inputs,
                                     'plugins', dict(IMAGE_PLUGINS=str(self.args.plugins),
                                                     IMAGE_HTTP_BASE='http://127.0.0.1:' + str(server.server_port)))
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()
            (self.out / 'http.json').write_text(json.dumps(requests, indent=2) + '\n')
        def near(actual, expected, tolerance=10):
            return max(abs(a - b) for a, b in zip(actual, expected)) <= tolerance
        def count(name, color, tolerance=10):
            width, height, pixels = read_png(output / (name + '.png'))
            return sum(near(pixels[i * 4:i * 4 + 4], color, tolerance) for i in range(width * height))
        def warning(name):
            return warning_coverage(output / (name + '.png'), result['warningColor'])
        entries = {row['name']: row for row in result['entries']}
        self.check('plugin-roots-created', all(not row['error'] for row in entries.values()),
                   {name: row['error'] for name, row in entries.items() if row['error']})
        def images(name, kind='image'):
            return [row for row in entries[name]['images'] if row['kind'] == kind]
        for name, color in (('kde-phone', COLORS[0]), ('valent-phone', COLORS[0]), ('clipboard-image', COLORS[0]),
                            ('hermes-avatar', COLORS[0])):
            shown = images(name)
            self.check('plugin-' + name + '-presented', shown and all(row['state'] == 'ready' for row in shown if row['visible'])
                       and any(row['state'] == 'ready' for row in shown) and count(name, color) > 50,
                       dict(images=shown, pixels=count(name, color)))
        failed = images('hermes-avatar-failed')
        failed_warning, ready_warning = warning('hermes-avatar-failed'), warning('hermes-avatar')
        self.check('plugin-avatar-failure-labelled', any(row['state'] == 'unavailable' and row['code'] for row in failed)
                   and failed_warning > 5 and ready_warning == 0,
                   dict(images=failed, warningCoverage=failed_warning, readyWarningCoverage=ready_warning))
        sticker = images('sticker')
        frames = {tuple(pixel(path)) for path in output.glob('sticker-*.png')}
        self.check('plugin-sticker-keeps-animation', len(sticker) == 1 and sticker[0]['state'] == 'ready' and sticker[0]['animated']
                   and sticker[0]['frames'] == 3 and len(frames & {tuple(c) for c in COLORS}) >= 2,
                   dict(images=sticker, centers=sorted(frames)))
        preview = images('lwe-preview')
        text = images('lwe-preview', 'text')
        # Descriptions are escaped by the plugin (BBCode images become links):
        # NImageText at the site, no image work, preview through the owner.
        self.check('plugin-workshop-preview-and-description', any(row['state'] == 'ready' for row in preview)
                   and count('lwe-preview', COLORS[0]) > 50 and len(text) == 2 and all(t['count'] == 0 for t in text)
                   and count('lwe-preview', COLORS[1]) == 0, dict(images=preview, text=text))
        motion = [row for row in images('lwe-motion') if row['state'] == 'ready']
        self.check('plugin-workshop-motion-preview-animates', motion and motion[0]['animated'] and motion[0]['frames'] == 3, images('lwe-motion'))
        chat = images('chat-markdown', 'text')
        self.check('plugin-chat-markdown-image', chat and chat[0]['count'] == 1 and chat[0]['states'][0]['state'] == 'ready'
                   and count('chat-markdown', COLORS[0]) > 20, dict(text=chat, pixels=count('chat-markdown', COLORS[0])))
        # hermes-ssh-chat's terminal is plugin-generated rich text: every
        # character of the remote output is escaped, so image markup in it stays
        # text (each line intact) and nothing is fetched.
        terminal = [line.replace('\u00a0', ' ').rstrip() for line in re.split('[\n\u2028\u2029]', result['terminal'] or '')]
        self.check('plugin-hermes-terminal-escapes-external-data', requests == []
                   and all(line in terminal for line in result['terminalLines']), dict(requests=requests, terminal=terminal))
        videos = result['videos']
        galleries = result['galleries']
        ready_gallery = dict(visible=True, count=2)
        for gallery in ('mpv', 'vw'):
            self.check('plugin-' + gallery + '-browse-during-export', galleries['pending'][gallery] == ready_gallery, galleries)
        self.check('plugin-vw-export-does-not-reload-folder', galleries['afterExport'] == ready_gallery
                   and not galleries['galleryInvalidated'], galleries)
        for name in ('mpv-panel', 'vw-panel'):
            # Panels render the original video in still mode, independently of
            # the selected-wallpaper export.
            tiles = images(name, 'rounded')
            shown = [row for row in tiles if row['state'] == 'ready']
            failed = [row for row in tiles if row['state'] == 'unavailable']
            coverage = warning(name)
            self.check('plugin-' + name + '-video-thumbnails', len(tiles) == 2 and len(shown) == 1 and len(failed) == 1
                       and all(row['visible'] for row in tiles)
                       and shown[0]['source'].endswith('/Red.mp4')
                       and failed[0]['code'] and failed[0]['source'].endswith('/Broken.mp4')
                       and count(name, COLORS[0], 24) > 50 and coverage > 5,
                       dict(tiles=tiles, videos=videos, pixels=count(name, COLORS[0], 24), warningCoverage=coverage))
        self.check('plugin-video-producers-settle-honestly', videos['mpvReady'] and videos['vwSettled'] and videos['vwReady']
                   and all(row['code'] and row['reason'] for row in videos['failed'].values())
                   and not videos['obsoleteMpv']['code'] and not videos['obsoleteVw']['code'], videos)
        for name in ('mpvPath', 'vwPath'):
            frame = Path(videos[name])
            self.check('plugin-export-' + name, frame.is_file() and '/video-wallpapers/' in str(frame)
                       and near(pixel(frame), COLORS[0], 24), videos)
        cards = result['wallcards']
        files = {row['fileName']: row for row in (cards or {}).get('files', [])}
        self.check('plugin-wallcards-owner-thumbnails-and-colors', cards and cards['ready'] and not cards['loading'] and len(files) == 4
                   and files['Still.webp']['filterColor'] == 'Red' and files['frame-1.png']['filterColor'] == 'Green'
                   and all(files[n]['thumbnail'] == files[n]['filePath'] for n in ('Still.webp', 'frame-1.png'))
                   and files['Corrupt.webp']['thumbnail'] == files['Corrupt.webp']['filePath'] and files['Corrupt.webp']['filterColor'] == 'Monochrome'
                   and not (output / 'unused-wallcards-cache').exists(), cards)
        escaped = files.get(escaped_name, {})
        self.check('plugin-wallcards-samples-literal-name', escaped.get('filePath') == str(wallcards / escaped_name)
                   and escaped.get('thumbnail') == escaped.get('filePath')
                   and escaped.get('hexCode') == files['Still.webp']['hexCode']
                   and escaped.get('filterColor') == 'Red', escaped)
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
                       and consumer['result']['format'] and consumer['generation'] > 0
                       and max(abs(a - b) for a, b in zip(center, COLORS[0])) <= 8,
                       dict(consumer=consumer, center=center))
        webp = result['formats'][0]['consumer']
        self.check('owner-sniffs-webp-without-qt-codec', webp['result']['format'] ==
                   result['formats'][1]['consumer']['result']['format'] == 'webp', webp)
        self.check('opaque-provider-failure-is-explicit', result['provider']['state'] == 'unavailable'
                   and result['provider']['errorCode'] and result['provider']['errorReason'] and not result['provider']['url'], result['provider'])
        for name in ('corrupt', 'missing'):
            row = result[name]
            self.check('owner-' + name + '-failure', row['state'] == 'unavailable' and bool(row['errorReason']) and not row['url'], row)
        self.check('disabled-is-idle-not-failure', result['disabled']['state'] == result['sharedA']['state'] == 'idle', result['disabled'])
        self.check('source-replacement-pixels', result['replacing']['state'] == 'ready'
                   and pixel(output / 'replacing.png') == list(COLORS[1]), result['replacing'])
        self.check('retired-generation-rejected', result['originalGeneration'] < result['obsoleteGeneration']
                   < result['replacing']['generation'] and result['replacing']['url'].endswith('/frame-1.png'), result['replacing'])
        self.check('last-interest-retains-result', result['sharedB']['state'] == 'ready'
                   and pixel(output / 'shared-survivor.png') == list(COLORS[0]), result['sharedB'])
        self.check('data-source-ignores-mime-hint', result['data']['state'] == 'ready'
                   and pixel(output / 'data.png') == list(COLORS[0]), result['data'])
        self.check('still-representation-is-frame-zero', result['firstFrame']['frameCount'] == 3
                   and pixel(output / 'first-frame.png') == list(COLORS[0]), result['firstFrame'])
        motion = result['motion']
        paused = [tuple(pixel(path)) for path in sorted(output.glob('paused-*.png'))[2:-2]]
        self.check('owner-motion-pause-retains-representation', len(paused) >= 5 and len(set(paused)) == 1
                   and paused[0] in COLORS, paused)
        centers = [tuple(pixel(path)) for path in sorted(output.glob('motion-*.png'))]
        sequences = [[color for color, _ in groupby(pixel(path) for path in paths)] for paths in (
            sorted(p for p in output.glob('motion-*.png') if p.name < 'motion-' + sorted(output.glob('paused-*.png'))[0].name[7:]),
            sorted(p for p in output.glob('motion-*.png') if p.name > 'motion-' + sorted(output.glob('paused-*.png'))[-1].name[7:]))]
        self.check('owner-preserved-animation', motion['state'] == 'ready' and motion['frameCount'] == 3
                   and motion['result']['frames'] == 3 and motion['result']['format'] == 'webp'
                   and all(len(events) >= 3 and all(tuple(b) == COLORS[(COLORS.index(tuple(a)) + 1) % 3]
                       for a, b in zip(events, events[1:])) for events in sequences) and set(centers) == set(COLORS),
                   dict(consumer=motion, sequences=sequences, centers=centers))
        self.check('owner-display-retirement', displays_retired(result['retired'], len(result['formats']) + 10), result['retired'])
        self.owner_fault(inputs)
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
                   and displays_retired(locked['retired'], len(locked['formats']) + 10), locked)
        self.source_admission(inputs)
        return result

    def retired_acquisitions(self, name):
        cache = self.work / (name + '-profile') / 'cache'
        if not cache.is_dir():
            raise AssertionError(f'No real cache profile for acquisition retirement: {cache}')
        return [str(path) for pattern in ('image-source-*', '.originals-*') for path in cache.rglob(pattern)]

    def download_burst(self):
        inputs = self.work / 'fixtures'
        create_fixtures(inputs, self.commands)
        png = colored_png(COLORS[0])
        active, started, closed = {}, [], []
        guard = threading.Condition()
        advance = threading.Event()
        peak = 0

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                nonlocal peak
                if self.path == '/ready':
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(png)))
                    self.end_headers()
                    self.wfile.write(png)
                    return
                if self.path == '/truncated':
                    self.send_response(200)
                    self.send_header('Content-Length', '262144')
                    self.end_headers()
                    self.wfile.write(b'x' * 131072)
                    return
                index = int(self.path.rsplit('/', 1)[1])
                with guard:
                    active[index] = self.connection
                    started.append(index)
                    peak = max(peak, sum(not peer_closed(conn) for conn in active.values()))
                    if index == 2:
                        advance.set()
                try:
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(png)))
                    self.end_headers()
                    self.wfile.write(png[:1])
                    # Only completion of these earlier transfers frees the
                    # slots needed to get past the cancelled queued index 4.
                    if index in (1, 2, 3) and advance.wait(8):
                        self.wfile.write(png[1:])
                    ready, _, _ = select.select([self.connection], [], [], 13)
                    if ready and peer_closed(self.connection):
                        with guard:
                            closed.append(index)
                finally:
                    with guard:
                        del active[index]
                        guard.notify_all()

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        name = 'download-burst'
        size = 38
        try:
            result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/download-burst.qml',
                                     inputs, name, dict(IMAGE_BURST_URL=f'http://127.0.0.1:{server.server_port}',
                                                        IMAGE_BURST_SIZE=str(size)))
            deadline = time.monotonic() + 3
            with guard:
                guard.wait_for(lambda: not active, timeout=3)
            while self.retired_acquisitions(name) and time.monotonic() < deadline:
                time.sleep(.025)
            report = dict(peak=peak, started=started, closed=closed, active=sorted(active), result=result,
                          remaining=self.retired_acquisitions(name))
            (self.out / 'download-burst.json').write_text(json.dumps(report, indent=2) + '\n')
            self.check('remote-downloads-share-two-transfer-slots', peak == 2, report)
            self.check('queued-download-cancellation-observed', sorted(started) == [0, 1, 2, 3, 5, 6], report)
            self.check('remote-download-cancellation-retires-consumers', result['cancelled'] == ['idle', 'idle'], report)
            self.check('remote-download-queue-is-bounded', result['rejected'] == max(0, size - 34), report)
            self.check('truncated-download-fails-before-it-is-leased', result['failure'] == 'download-failed', report)
            self.check('download-sibling-lease-survives-cancellation', result['kept'] == 'ready'
                       and pixel(output / 'kept.png') == list(COLORS[0]), report)
            self.check('shell-exit-cleans-inflight-transfers-and-leases', not active and sorted(closed) == sorted(started)
                       and not report['remaining'], report)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    @staticmethod
    def wallpaper_quiet(row):
        return row['changes'] == row['reservations'] == 0

    def owner_fault(self, inputs=None):
        if inputs is None:
            inputs = self.work / 'fixtures'
            create_fixtures(inputs, self.commands)
        shutil.copyfile(inputs / 'Corrupt.webp', inputs / 'Retry.webp')
        shutil.copyfile(inputs / 'Still.webp', inputs / 'Retry-replacement.webp')
        failure, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/owner-fault.qml',
                                  inputs, 'owner-fault')
        first = failure['first']
        self.check('owner-malformed-settles-without-loop', first['state'] == 'unavailable' and first['code']
                   and first['reason'] and not first['url'] and failure['deliveries'] == 1, failure)
        self.check('owner-malformed-explicit-retry', failure['retry']['state'] == 'ready'
                   and failure['retry']['generation'] > first['generation']
                   and pixel(output / 'retry.png') == list(COLORS[0])
                   and failure['finalState'] == 'idle' and not failure['finalUrl'], failure)

    def source_admission(self, inputs=None):
        if inputs is None:
            inputs = self.work / 'fixtures'
            manifest = create_fixtures(inputs, self.commands)
            (self.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        # Force a synchronous Qt error via its explicit allocation limit, not
        # the machine's HEIF encoder/reader support. Encoded bytes fit the same
        # owner byte budget; the built-in PNG reader's full allocation does not.
        allocation_mib = 1
        byte_budget = allocation_mib * 1024 * 1024
        width, height = 1024, 768
        synchronous_source = self.work / 'native-allocation-rejected.png'
        encoded = colored_png(COLORS[0], width, height)
        assert len(encoded) < byte_budget < width * height * 4
        synchronous_source.write_bytes(encoded)
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                requests.append(self.path)
                data = (inputs / 'frame-0.png').read_bytes() if self.path == '/valid' else b'x' * (byte_budget + 1)
                self.send_response(200)
                if self.path != '/streamed':
                    self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                try:
                    for offset in range(0, len(data), 65536):
                        self.wfile.write(data[offset:offset + 65536])
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result, output = self.qt(self.args.source, self.args.source / 'Scripts/dev/fixtures/image-decoding/source-admission.qml',
                inputs, 'source-admission', dict(QT_IMAGEIO_MAXALLOC=str(allocation_mib),
                    IMAGE_SYNCHRONOUS_SOURCE=str(synchronous_source), IMAGE_REMOTE_URL=f'http://127.0.0.1:{server.server_port}'))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        self.check('owner-normalized-and-thumbnail-use-imvqml', result['settled']['formats'][:2] == ['webp', 'webp']
                   and result['settled']['normalized'] == result['settled']['thumbnail'] == 'ready'
                   and all(pixel(output / (name + '.png')) == list(COLORS[0]) for name in ('normalized', 'thumbnail')), result)
        self.check('owner-synchronous-error-keeps-render-interest', result['settled'].get('synchronous') == 'ready'
                   and result['settled']['formats'][2] == 'png' and result['settled']['extent'] == [width, height]
                   and pixel(output / 'synchronous.png') == list(COLORS[0]), result)
        self.check('owner-remote-one-bounded-owner-request', sorted(requests) == ['/declared', '/streamed', '/valid'], requests)
        for name in ('declared', 'streamed'):
            row = result['settled'].get(name, {})
            self.check('owner-source-too-large-' + name, row.get('failed') and row.get('code') == 'source-too-large' and row.get('reason'), row)
            width, height, rgba = read_png(output / (name + '.png'))
            self.check('owner-source-too-large-visible-badge-' + name, width == height == 96 and any(rgba[3::4]),
                       dict(width=width, height=height, visiblePixels=sum(a > 0 for a in rgba[3::4])))
        self.check('owner-terminal-error-publishes-details-first', len(result['terminalDetails']) == 2 and
                   all(row['code'] == 'source-too-large' and row['reason'] for row in result['terminalDetails']), result['terminalDetails'])
        self.check('owner-admitted-remote-presents-pixels', result['settled'].get('valid') == 'ready' and pixel(output / 'valid.png') == list(COLORS[0]), result)
        leases = self.retired_acquisitions('source-admission')
        self.check('owner-admission-retires-all-interests', displays_retired(result['retired'], 6)
                   and not leases, dict(retired=result['retired'], leases=leases))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--baseline-source', type=Path)
    parser.add_argument('--baseline-plugins', type=Path)
    parser.add_argument('--lint-baseline-source', type=Path, help='Immutable shell baseline for changed-QML reporting, never a red control')
    parser.add_argument('--qt-webp', choices=('present', 'absent'), default='absent', help=argparse.SUPPRESS)
    parser.add_argument('--case', choices=(*CASES, 'formats', 'map-favicon', 'rotated-video', 'owner-fault', 'wallpaper-software-baseline', 'staging-restart'), required=True)
    parser.add_argument('--results', type=Path)
    parser.add_argument('--job-control', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.case == 'review-results' and args.results is None:
        parser.error('review-results requires --results')
    profile = activate_profile(args.guest_profile)
    for path in (args.source, args.plugins, args.baseline_source, args.baseline_plugins, args.lint_baseline_source):
        if path is not None and (path != path.resolve() or not path.is_dir() or not path.is_relative_to(profile.workspace)):
            raise ValueError('Canonical source inside the named execution workspace required')
    if args.case != 'review-results':
        missing = [tool for tool in ('python3', 'magick', 'ffmpeg', 'ffprobe', 'qs', 'dbus-daemon', 'busctl') if not shutil.which(tool)]
        if missing:
            raise RuntimeError('Missing guest prerequisites before fixture creation: ' + ', '.join(missing))
    status = supervise(args, profile)
    if status is not None:
        return status
    with Worker(args, profile):
        return execute(args, profile)


def execute(args, profile):
    run = Run(args, profile)
    try:
        if args.case in GROUPS:
            run.aggregate()
        elif args.case == 'red':
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
        elif args.case in ('launcher-red', 'launcher'):
            run.launcher()
        elif args.case in ('text-red', 'text'):
            run.text()
        elif args.case in ('cache-clear-red', 'cache-clear'):
            run.cache_clear()
        elif args.case == 'owner':
            run.owner()
        elif args.case == 'owner-fault':
            run.owner_fault()
        elif args.case == 'source-admission':
            run.source_admission()
        elif args.case == 'download-burst':
            run.download_burst()
        elif args.case == 'staging-restart':
            inputs = run.work / 'fixtures'
            create_fixtures(inputs, run.commands)
            result, _ = run.qt(args.source, args.source / 'Scripts/dev/fixtures/image-decoding/staging-restart.qml',
                               inputs, 'staging-restart')
            run.check('staging-worker-recovers-after-exit', result['recovered'], result)
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
        elif args.case == 'notification-body':
            run.notification_body()
        elif args.case == 'desktop-wallpaper':
            run.desktop_wallpaper()
        elif args.case == 'parallax-wallpaper':
            run.desktop_wallpaper('parallax-wallpaper', str(args.plugins / 'parallax-wallpaper/ParallaxBackground.qml'))
        elif args.case == 'wallpaper-software-baseline':
            run.software_wallpaper_baseline()
        elif args.case == 'chooser':
            run.chooser()
        elif args.case == 'plugins':
            run.plugins()
        elif args.case == 'formats':
            run.formats()
        elif args.case == 'rotated-video':
            run.rotated_video()
        elif args.case == 'map-favicon':
            inputs = run.work / 'fixtures'
            create_fixtures(inputs, run.commands)
            report, output = run.qt(args.source, args.source / 'Scripts/dev/fixtures/image-decoding/map-favicon.qml', inputs,
                                    'map-favicon', dict(IMAGE_PLUGINS=str(args.plugins)))
            actual = pixel(output / 'map-favicon.png')
            run.check('current-niri-map-uses-imvqml-never-legacy-image', report == dict(nativeCreations=0,
                      shared=True, format='webp') and actual == list(COLORS[0]), dict(report=report, pixel=actual))
        elif args.case == 'packaging':
            from image_decoding_packages import qualify
            qualify(run)
        elif args.case == 'review-results':
            from image_decoding_review import review
            review(run)
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
