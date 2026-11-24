"""Actual candidate package builds and installed image-consumer qualification."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time

from guest_profile import protect_owned_process
from image_decoding_evidence import source_manifest
from image_decoding_fixtures import COLORS, create_fixtures, pixel


def command(run, name, argv, *, cwd=None, env=None, timeout=7100):
    log = run.out / (name + '.log')
    with log.open('w') as output:
        launch = list(map(str, argv))
        if launch[0] == 'sudo':
            # Keep an unprivileged, identity-fenced supervisor while the
            # authorized guest package transaction runs as its own child.
            launch = [sys.executable, '-c', 'import subprocess,sys; sys.exit(subprocess.call(sys.argv[1:]))', *launch]
        proc = subprocess.Popen(launch, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True)
        guard = protect_owned_process(proc)
        try:
            code = proc.wait(timeout=timeout)
        finally:
            if proc.poll() is None:
                guard.terminate()
                proc.wait(timeout=30)
    record = dict(argv=list(map(str, argv)), cwd=str(cwd) if cwd else None, exit=code,
                  process=guard.identity.record() if guard.identity else None, log=str(log))
    (run.out / (name + '-command.json')).write_text(json.dumps(record, indent=2) + '\n')
    run.check(name, code == 0, record)
    return log


def snapshot(run):
    """Synthetic Git transport fixture, not a commit to either project branch."""
    root = run.work / 'aur-source'
    shutil.copytree(run.args.source, root, symlinks=True, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    subprocess.run(['git', 'init', '--quiet', '--initial-branch=main', str(root)], check=True)
    manifest = source_manifest(root)
    with (run.out / 'aur-snapshot-import.log').open('w') as log:
        proc = subprocess.Popen(['git', '-C', str(root), 'fast-import', '--quiet'], stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        stream = proc.stdin
        files = []
        for mark, (name, row) in enumerate(manifest['files'].items(), 1):
            if row['type'] == 'file':
                data = (root / name).read_bytes()
                mode = '100755' if row['mode'] & 0o111 else '100644'
            elif row['type'] == 'link':
                data = os.fsencode(row['target'])
                mode = '120000'
            else:
                # Directories stay in the source receipt, but Git only stores leaves.
                continue
            stream.write(f'blob\nmark :{mark}\ndata {len(data)}\n'.encode() + data + b'\n')
            files.append(f'M {mode} :{mark} {json.dumps(name, ensure_ascii=False)}\n')
        message = b'Image package source fixture\n'
        stream.write(f'commit refs/heads/main\ncommitter Image fixture <fixture@example.invalid> {int(time.time())} +0000\ndata {len(message)}\n'.encode()
                     + message + ''.join(files).encode() + b'\ndone\n')
        stream.close()
        code = proc.wait(timeout=120)
    run.check('candidate-git-transport-fixture', code == 0 and source_manifest(root) == manifest,
              dict(exit=code, source=manifest['sha256']))
    return root


def installed(run, installed_root, launcher, inputs, label, *, clean=False):
    # No production imports are rewritten: only the fixture entry lives in this
    # private root; every installed directory is reached through an exact link.
    before = source_manifest(installed_root)
    root = run.work / (label + '-root')
    root.mkdir()
    for path in installed_root.iterdir():
        (root / path.name).symlink_to(path, target_is_directory=path.is_dir())
    fixture = run.args.source / 'Scripts/dev/fixtures/image-decoding/owner.qml'
    environment = dict(IMAGE_ICON_DIR=str(installed_root / 'builtin/plugins/atmosphera-icons'))
    if clean:
        # Nix on a non-NixOS guest has no host GPU-driver integration. Exercise
        # real Wayland presentation without importing Arch GL/Qt libraries.
        environment['QT_QUICK_BACKEND'] = 'software'
    result, output = run.qt(root, fixture, inputs, label, assembled=True, launcher=launcher,
                            clean_environment=clean, extra_env=environment)
    rows = result['formats']
    run.check(label + '-installed-still-pixels', all(row['consumer']['state'] == 'ready' and
              max(abs(a-b) for a, b in zip(pixel(output / f'format-{i}.png'), COLORS[0])) <= 8 for i, row in enumerate(rows)), rows)
    frames = {tuple(pixel(p)) for p in output.glob('motion-*.png')}
    motion = result['motion']
    run.check(label + '-installed-motion-pixels', motion['state'] == 'ready' and motion['frameCount'] == 3
              and motion['result']['frames'] == 3 and frames == set(COLORS), dict(motion=motion, frames=sorted(frames)))
    run.check(label + '-native-plugin-visible', result['raw'] == 1 and rows[0]['consumer']['result']['origin'] == 'native', result['raw'])
    run.check(label + '-worker-quiescent', result['finalInterests'] == result['finalRequests'] == 0 and not result['workerRunning'],
              dict(interests=result['finalInterests'], requests=result['finalRequests'], worker=result['workerRunning']))
    if clean:
        process = json.loads((output / 'process.json').read_bytes())
        run.check(label + '-real-nix-qt-plugin', process['cleanEnvironment'] and process['imagePlugins']
                  and all(p.startswith('/nix/store/') for p in process['imagePlugins'])
                  and any(p.startswith('/nix/store/') and Path(p).name in ('qs', 'quickshell', '.quickshell-wrapped')
                          for p in process['executables']), process)
    run.check(label + '-installed-tree-unchanged', source_manifest(installed_root) == before, before['sha256'])


def qualify(run):
    if run.args.qt_webp != 'present':
        raise ValueError('installed packages require the genuine present lane; run absent consumers before installation')
    for tool in ('makepkg', 'nix', 'podman'):
        if not shutil.which(tool):
            raise RuntimeError('Provision the named guest prerequisite before packaging: ' + tool)
    inputs = run.work / 'fixtures'
    manifest = create_fixtures(inputs, run.commands)
    (run.out / 'fixture-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    delegates = run.command(['magick', '-list', 'format'])
    for name in ('WEBP', 'HEIC', 'AVIF', 'PNG', 'GIF'):
        lines = [line for line in delegates.stdout.splitlines() if line.split() and line.split()[0].rstrip('*') == name]
        run.check('packaged-delegate-' + name, delegates.returncode == 0 and lines and
                  ('r' in lines[0].split()[2] if name in ('WEBP', 'HEIC', 'AVIF') else 'w' in lines[0].split()[2]), lines)
    source = snapshot(run)
    build = run.work / 'aur-build'
    build.mkdir()
    env = dict(os.environ, ATMOSPHERA_CHECKOUT=str(source), ATMOSPHERA_REF='main', BUILDDIR=str(build),
               PKGDEST=str(build), SRCDEST=str(build), MAKEFLAGS='-j2', CMAKE_BUILD_PARALLEL_LEVEL='2')
    command(run, 'aur-candidate-build', ['makepkg', '--syncdeps', '--noconfirm'], cwd=source / 'dev/vm/aur', env=env)
    packages = list(build.glob('atmosphera-git-*.pkg.tar.zst'))
    run.check('aur-exactly-one-candidate', len(packages) == 1, [str(p) for p in packages])
    pkginfo = run.command(['bsdtar', '-xOf', str(packages[0]), '.PKGINFO'])
    stable = run.command(['makepkg', '--printsrcinfo'], cwd=source / 'packaging/aur/atmosphera', env=env)
    (run.out / 'candidate.PKGINFO').write_text(pkginfo.stdout)
    (run.out / 'stable.SRCINFO').write_text(stable.stdout)
    for dep in ('qt6-imageformats', 'imagemagick', 'ffmpeg', 'python', 'libwebp', 'libheif'):
        run.check('aur-required-' + dep, 'depend = ' + dep + '\n' in pkginfo.stdout and 'depends = ' + dep + '\n' in stable.stdout,
                  dict(package=pkginfo.returncode, stable=stable.returncode))
    command(run, 'aur-candidate-normal-install', ['sudo', '-n', 'env', 'TMPDIR=' + os.environ['TMPDIR'],
                                                'pacman', '-U', '--noconfirm', str(packages[0])])
    installed(run, Path('/etc/xdg/quickshell/atmosphera'), Path('/usr/local/bin/atmosphera'), inputs, 'aur-shell')
    installed(run, Path('/etc/xdg/quickshell/atmosphera-lockscreen'), Path('/usr/local/bin/atmosphera'), inputs, 'aur-locker')
    # Build from the actual candidate and immutable flake.lock, never a sentinel
    # callPackage evaluation or the guest's Arch Quickshell on PATH.
    link = run.work / 'nix-result'
    home_mode = stat.S_IMODE(run.profile.home.stat().st_mode)
    try:
        # The Nix sandbox drops supplementary groups; grant traversal only for
        # its disk-backed build root, not directory listing, then restore it.
        run.profile.home.chmod(home_mode | 0o001)
        command(run, 'nix-candidate-build', ['nix', '--extra-experimental-features', 'nix-command flakes', 'build',
                                          '--no-update-lock-file', '--max-jobs', '1', '--cores', '2', '--out-link', str(link),
                                          'path:' + str(run.args.source)], cwd=run.args.source)
    finally:
        run.profile.home.chmod(home_mode)
    run.check('nix-builder-home-mode-restored', stat.S_IMODE(run.profile.home.stat().st_mode) == home_mode, home_mode)
    prefix = link.resolve(strict=True)
    closure = run.command(['nix-store', '--query', '--requisites', str(prefix)], timeout=900)
    (run.out / 'nix-closure.txt').write_text(closure.stdout)
    run.check('nix-mandatory-decoder-closure', closure.returncode == 0 and
              all(any(name in Path(line).name for line in closure.stdout.splitlines()) for name in
                  ('imagemagick', 'ffmpeg', 'python3', 'qtimageformats', 'libheif')), closure.stdout.splitlines())
    installed(run, prefix / 'share/atmosphera', prefix / 'bin/atmosphera', inputs, 'nix-shell', clean=True)
    installed(run, prefix / 'etc/xdg/quickshell/atmosphera-lockscreen', prefix / 'bin/atmosphera', inputs, 'nix-locker', clean=True)
    image = 'localhost/atmosphera-image-package:' + run.out.name
    command(run, 'devcontainer-candidate-build', ['podman', 'build', '--memory=2g', '--memory-swap=2g',
             '--cpu-period=100000', '--cpu-quota=200000', '--tag', image, '--file', str(run.args.source / '.devcontainer/Dockerfile'),
             str(run.args.source / '.devcontainer')], cwd=run.args.source)
    tools = run.command(['podman', 'run', '--rm', '--memory=1g', '--memory-swap=1g', '--pids-limit=256', '--cpus=1',
                         '--network=none', image, 'sh', '-ec',
                         'pacman -Q qt6-imageformats imagemagick ffmpeg libwebp libheif; python3 --version; ffmpeg -version; magick -list format'], timeout=900)
    (run.out / 'devcontainer-tools.txt').write_text(tools.stdout + tools.stderr)
    run.check('devcontainer-required-tools-and-delegates', tools.returncode == 0 and all(name in tools.stdout for name in
              ('qt6-imageformats', 'imagemagick', 'ffmpeg', 'libwebp', 'libheif', 'WEBP', 'HEIC', 'AVIF', 'PNG', 'GIF')), tools.returncode)
