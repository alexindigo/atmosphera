#!/usr/bin/env python3
"""Image decoding end-consumer regression controller; explicit owned guest only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from guest_profile import activate_profile, profile_argument, protect_owned_process
from image_decoding_fixtures import COLORS, create_fixtures, pixel
from image_decoding_evidence import source_manifest
from qml_probe import bootstrap_fixture


CASES = ('red', 'owner', 'chooser-wallpaper', 'shell', 'plugins', 'packaging', 'all', 'review-results')
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

    def qt(self, source, fixture, inputs, name):
        # Actual production imports are copied, never mocked or rewritten. Only
        # the separate test entry and private XDG preferences are synthesized.
        shell = self.work / name
        before = source_manifest(source)
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
                   ATMOSPHERA_CONFIG_DIR=str(profile / 'config') + '/', ATMOSPHERA_CACHE_DIR=str(profile / 'cache') + '/',
                   ATMOSPHERA_STATE_DIR=str(profile / 'state') + '/', ATMOSPHERA_SETTINGS_FILE=str(profile / 'config/settings.json'),
                   XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'),
                   XDG_STATE_HOME=str(profile / 'state'), XDG_DATA_HOME=str(profile / 'data'), TMPDIR=str(profile / 'tmp'))
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
        lint = self.command(['bash', str(shell / 'Scripts/dev/qmllint.sh'), str(entry)], timeout=900,
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
