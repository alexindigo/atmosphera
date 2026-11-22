#!/usr/bin/env python3
"""Image decoding end-consumer regression controller; explicit owned guest only."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from guest_profile import activate_profile, profile_argument, protect_owned_process
from image_decoding_fixtures import COLORS, create_fixtures, pixel, read_png
from image_decoding_evidence import source_manifest
from qml_probe import bootstrap_fixture


CASES = ('red', 'owner', 'legacy', 'chooser', 'chooser-wallpaper', 'shell', 'plugins', 'packaging', 'all', 'review-results')
ERRORS = re.compile(r'ReferenceError|TypeError|SyntaxError|Cannot assign|Unable to assign|Binding loop|'
                    r'Failed to load configuration|is not installed|Component is not ready')


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
        (profile / 'config/settings.json').write_text(json.dumps(defaults))
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
                deadline = time.monotonic() + 25
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
        if self.args.case == 'chooser':
            lint_paths += [str(shell / p) for p in ('Services/Files/FileTypes.qml', 'Services/Files/FileThumbnails.qml',
                'Services/Files/FileThumbnail.qml', 'Services/UI/ImageWorker.qml', 'Modules/FileChooser/FileEntryArtwork.qml',
                'Modules/FileChooser/FileEntry.qml', 'Modules/FileChooser/FileQuickLook.qml')]
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
        elif args.case == 'owner':
            run.owner()
        elif args.case == 'legacy':
            run.legacy()
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
