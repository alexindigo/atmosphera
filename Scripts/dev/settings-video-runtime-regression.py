#!/usr/bin/env python3
"""Actual video monitor command routes with native owners. Assigned guest only."""
import argparse
import base64
from dataclasses import dataclass
import decimal
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from guest_profile import activate_profile, profile_argument, protect_owned_process

CASES = ('startup', 'startup-enabled', 'routes', 'upgrade', 'empty', 'reset', 'namespace-reset', 'timer-failure', 'mpv-volume', 'inner', 'inner-failure', 'thumbnails', 'thumbnail-failure', 'thumbnail-generation', 'thumbnail-retry')


@dataclass
class OwnedResult:
    returncode: int
    stdout: str
    stderr: str
    environment: dict


def run_owned(profile, command, env, timeout):
    environment = dict(env, **profile.child_environment(''))
    process = subprocess.Popen(command, env=environment,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    guard = protect_owned_process(process)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        guard.terminate()
        process.communicate(timeout=10)
        raise
    profile.verify()
    return OwnedResult(process.returncode, stdout, stderr, environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--case', choices=('all',)+CASES, default='all')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the explicit verified guest')
    lock = (profile.work_base / '.plugin-settings-host-assets.lock').open('a+')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    args.work_root.mkdir(parents=True, exist_ok=False)
    args.output.mkdir(parents=True, exist_ok=False)
    args.installed = args.work_root / 'install'
    shutil.copytree(args.source, args.installed, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '*.bak'))
    (args.installed / '.qmlls.ini').touch(exist_ok=True)
    inputs = {str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (args.plugins / 'video-wallpaper').rglob('*') if p.is_file()}
    inputs.update({str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (Path(__file__), args.source / 'Scripts/dev/fixtures/settings-video-runtime.qml')})
    (args.output / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    probe = args.installed/'i5-video-runtime.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-video-runtime.qml').read_bytes())
    manifest = (args.plugins/'video-wallpaper/manifest.json').read_text()
    cases = []
    try:
        numeric = args.work_root/'number-helper'
        numeric.mkdir()
        shutil.copy2(args.source/'Scripts/dev/fixtures/settings-native-number-presentation.qml', numeric/'shell.qml')
        number_file = numeric/'user.json'
        number_file.write_text('{"rows":[{"id":"fixture","knownNumber":123,"customField":123,"fraction":1.25}]}')
        result = run_owned(profile, ['qs', '-p', str(numeric/'shell.qml'), '--no-color'],
                           dict(os.environ, I5_NUMBER_FILE=str(number_file)), 25)
        text = result.stdout+result.stderr
        (args.output/'number-helper.log').write_text(text)
        assert result.returncode == 0 and 'I5_NUMBER_PRESENTATION: PASS' in text, text[-6000:]
        cases.append(dict(id='unknown-safe-number-consumer', status='PASS'))
        helper = args.work_root/'command-helper'
        shutil.copytree(args.plugins/'video-wallpaper', helper/'video-wallpaper')
        (helper/'shell.qml').write_text('import Quickshell\nimport "./video-wallpaper/fixtures"\nMonitorCommandsFixture {}\n')
        helper_file = helper/'user.json'
        helper_file.write_text('{"monitors":{"__proto__":{"currentWallpaper":"original","wide":18446744073709551615,"huge":1e400,"decimal":0.123456789012345678901234567890,"__proto__":{"keep":true}},"constructor":{"volume":0.5,"isMuted":false,"wide":18446744073709551615},"remove-me":{}}}')
        for cold in ('0', '1'):
            result = run_owned(profile, ['qs', '-p', str(helper/'shell.qml'), '--no-color'],
                               dict(os.environ, I5_MAP_FILE=str(helper_file), I5_MAP_COLD=cold), 35)
            text = result.stdout+result.stderr
            (args.output/('command-helper-'+cold+'.log')).write_text(text)
            marker = 'I5_MONITOR_COMMAND: '+('COLD_PASS' if cold == '1' else 'SAVED_PASS')
            assert result.returncode == 0 and marker in text, text[-6000:]
            raw = helper_file.read_text()
            row = json.loads(raw, parse_float=decimal.Decimal)['monitors']['__proto__']
            assert row['wide'] == 18446744073709551615 and row['huge'] == decimal.Decimal('1e400')
            assert row['decimal'] == decimal.Decimal('0.123456789012345678901234567890') and row['__proto__'] == dict(keep=True)
            assert '1e400' in raw and '0.123456789012345678901234567890' in raw
            cases.append(dict(id='command-helper-'+cold, status='PASS'))
        for case in CASES if args.case == 'all' else (args.case,):
            (args.output / 'status.json').write_text(json.dumps(dict(status='RUNNING', current=case, completed=len(cases))) + '\n')
            root = args.work_root/case
            config = root/'c'
            (config/'settings/plugins').mkdir(parents=True)
            plugin = config/'plugins/video-wallpaper'
            shutil.copytree(args.plugins/'video-wallpaper', plugin)
            (config/'settings.json').write_text('{"settingsVersion":62}')
            (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
            # Use the real output name, never assume the display's inherited name.
            sockets = list(Path('/run/user/'+str(os.getuid())).glob('niri.*.sock'))
            assert len(sockets) == 1, 'expected one compositor socket inside assigned guest'
            outputs = subprocess.run(['niri', 'msg', '--json', 'outputs'], env=dict(os.environ, NIRI_SOCKET=str(sockets[0])),
                                     check=True, capture_output=True, text=True, timeout=10)
            names = sorted(json.loads(outputs.stdout))
            assert names
            prefix = json.dumps(names[0])
            original = ('{'+prefix+':{"currentWallpaper":"legacy-choice","volume":0.5,"thumbCacheReady":false,"opaque":18446744073709551615},'
                        '"__proto__":{"volume":0.25,"wide":18446744073709551615,"huge":1e400,"decimal":0.123456789012345678901234567890,"__proto__":{"keep":true}},'
                         '"monitorSpecific":true,"enabled":false,"thumbCacheReady":true,"opaqueRoot":18446744073709551615}').encode()
            legacy = plugin/'settings.json'
            if case in ('startup', 'startup-enabled'):
                # Startup now exercises the sole producer's selected file as
                # well as its directory inventory, not a nonexistent label.
                original = original.replace(b'"currentWallpaper":"legacy-choice"',
                    b'"currentWallpaper":' + json.dumps(str(root/'media/media.mp4')).encode())
            if case == 'startup-enabled':
                original = original.replace(b'"enabled":false', b'"enabled":true,"activeBackend":"none"')
            legacy.write_bytes(original)
            before = legacy.stat()
            user = config/'settings/plugins/video-wallpaper.json'
            media_dir = root/'media'
            media_dir.mkdir()
            thumbs = root/'thumbs'
            thumbs.mkdir()
            media = media_dir/'media.mp4'
            valid_media = root/'valid.mp4'
            if case in ('startup', 'startup-enabled', 'mpv-volume', 'thumbnails', 'thumbnail-generation', 'thumbnail-retry'):
                built = subprocess.run(['timeout', '15', 'ffmpeg', '-nostdin', '-y', '-f', 'lavfi', '-i',
                                        'color=c=black:s=32x32:r=2', '-t', '1', '-c:v', 'mpeg4', str(media)],
                                       capture_output=True, text=True, timeout=20)
                (args.output/'mpv-media.log').write_text(built.stdout+built.stderr)
                assert built.returncode == 0 and media.is_file()
                if case == 'thumbnail-retry':
                    shutil.copy2(media, valid_media)
            if case in ('thumbnail-failure', 'thumbnail-retry'):
                media.write_text('invalid media - must not produce a ready cache')
            control = root/'thumbnail-control.json'
            control.write_text('{"calls":0}')
            # The mandated workspace makes a per-case MPV socket exceed Linux
            # sockaddr_un.sun_path. Keep the real socket on the same disk using
            # the explicit profile's short private runtime, not guest /tmp.
            socket_root = Path(tempfile.mkdtemp(prefix='', dir=profile.runtime_base))
            socket_root.chmod(0o700)
            mpv_socket = socket_root / 'm'
            assert len(os.fsencode(str(mpv_socket) + '-' + names[0])) < 104
            (args.output / (case + '-socket.json')).write_text(json.dumps(dict(path=str(mpv_socket),
                finalBytes=len(os.fsencode(str(mpv_socket) + '-' + names[0])), diskRuntime=str(profile.runtime_base))) + '\n')
            binary = root/'bin'
            binary.mkdir()
            if case == 'thumbnail-generation':
                shutil.copy2(args.source/'Scripts/dev/fixtures/thumbnail-ffmpeg-control.py', binary/'ffmpeg')
                (binary/'ffmpeg').chmod(0o755)
            image, other = root/'wallpaper.png', root/'other-wallpaper.png'
            image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII='))
            other.write_bytes(image.read_bytes())
            cache = root/'cache'
            cache.mkdir()
            cache_file = cache/'wallpapers.json'
            cache_file.write_text(json.dumps(dict(wallpapers={names[0]: dict(light=str(image), dark=str(image))})))
            if case == 'upgrade':
                user.write_bytes(original)
            if case == 'empty':
                user.write_text('{"monitors":{}}')
            if case in ('timer-failure', 'inner-failure'):
                user.write_bytes(original)
                user.parent.chmod(0o555)
            try:
                modes = ('routes', 'cold') if case in ('routes', 'upgrade') else (case, 'reset-cold') if case in ('reset', 'namespace-reset') else (case,)
                for mode in modes:
                    env = dict(os.environ, I5_VIDEO_MODE=mode, I5_VIDEO_MANIFEST=manifest,
                               I5_VIDEO_SOCKET=str(mpv_socket), I5_VIDEO_MEDIA=str(media),
                               I5_VIDEO_MEDIA_DIR=str(media_dir), I5_VIDEO_THUMBS=str(thumbs),
                               I5_THUMB_CONTROL=str(control), I5_THUMB_VALID=str(valid_media),
                               PATH=str(binary)+os.pathsep+os.environ['PATH'],
                               I5_VIDEO_IMAGE=str(image), I5_VIDEO_OTHER_IMAGE=str(other), I5_VIDEO_CACHE_FILE=str(cache_file),
                               ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                               ATMOSPHERA_STATE_DIR=str(root/'state'), QML_DISABLE_DISK_CACHE='1')
                    result = run_owned(profile, ['qs', '-p', str(probe), '--no-color'], env, 55)
                    text = result.stdout+result.stderr
                    (args.output/(case+'-'+mode+'.log')).write_text(text)
                    print(case+'-'+mode+': exit='+str(result.returncode), flush=True)
                    assert result.returncode == 0 and 'I5_VIDEO_RUNTIME: PASS '+mode in text, text[-6000:]
                    assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-6000:]
                    vfs = list((Path(result.environment['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
                    assert len(vfs) == 1, 'actual Video qs/native lint universe missing or ambiguous'
                    lint = subprocess.run(['bash', str(args.installed / 'Scripts/dev/qmllint.sh'), str(probe)],
                        env=dict(result.environment, QS_VFS=str(vfs[0])), cwd=args.installed,
                        capture_output=True, text=True, timeout=120)
                    (args.output / (case + '-' + mode + '-lint.log')).write_text(lint.stdout + lint.stderr)
                    assert lint.returncode == 0, 'Video native-universe fixture lint failed'
                    after = legacy.stat()
                    assert legacy.read_bytes() == original and (after.st_ino, after.st_mtime_ns, after.st_mode) == (before.st_ino, before.st_mtime_ns, before.st_mode)
                    if case in ('routes', 'upgrade'):
                        raw = user.read_text()
                        data = json.loads(raw, parse_float=decimal.Decimal)
                        assert data['monitors'][names[0]]['opaque'] == 18446744073709551615
                        assert data['monitors'][names[0]]['thumbCacheReady'] is False
                        row = data['monitors']['__proto__']
                        assert row['wide'] == 18446744073709551615 and row['huge'] == decimal.Decimal('1e400')
                        assert row['decimal'] == decimal.Decimal('0.123456789012345678901234567890')
                        assert row['__proto__'] == dict(keep=True)
                        assert '1e400' in raw and '0.123456789012345678901234567890' in raw
                        if case == 'upgrade':
                            assert data[names[0]]['currentWallpaper'] == 'legacy-choice' and data['opaqueRoot'] == 18446744073709551615
                            assert data['thumbCacheReady'] is True and data[names[0]]['thumbCacheReady'] is False
                    elif case in ('reset', 'namespace-reset') and user.exists():
                        assert 'monitors' not in json.loads(user.read_bytes())
                    elif case in ('timer-failure', 'inner-failure'):
                        assert user.read_bytes() == original
                    elif case == 'mpv-volume':
                        assert json.loads(user.read_bytes())['monitors'][names[0]]['volume'] == 0
                    elif case == 'inner':
                        assert json.loads(user.read_bytes())['monitors'][names[0]]['noctaliaWallpaper'] == str(image)
                        assert json.loads(cache_file.read_bytes())['wallpapers'][names[0]] == dict(light=str(image), dark=str(image))
                    elif case in ('thumbnails', 'thumbnail-generation', 'thumbnail-retry'):
                        assert (thumbs/'media.bmp').is_file() and (thumbs/'media.bmp').stat().st_size > 54
                        assert not user.exists()
                        if case == 'thumbnail-generation':
                            assert json.loads(control.read_text()) == dict(calls=2, finished=True, code=0)
                    elif case == 'thumbnail-failure':
                        assert not (thumbs/'media.bmp').exists()
                        assert not user.exists()
                    elif case in ('startup', 'startup-enabled'):
                        assert not user.exists()
                    cases.append(dict(id=case+'-'+mode, status='PASS'))
            finally:
                user.parent.chmod(0o755)
                if socket_root.is_dir() and not any(socket_root.iterdir()):
                    socket_root.rmdir()
        probe.unlink()
        assert args.installed.resolve() == args.installed and not (args.installed / '.git').exists()
        shutil.rmtree(args.installed)
        (args.output/'install-cleanup.json').write_text(json.dumps(dict(removed=str(args.installed),
            retained='isolated configurations, exact input fingerprints and receipts')) + '\n')
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=cases, selection=args.case), indent=2)+'\n')
        (args.output/'status.json').write_text(json.dumps(dict(status='PASS', completed=len(cases))) + '\n')
        print('SETTINGS_VIDEO_RUNTIME: PASS')
    except Exception as error:
        (args.output/'status.json').write_text(json.dumps(dict(status='FAIL', completed=len(cases), error=str(error))) + '\n')
        raise
    finally:
        probe.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
