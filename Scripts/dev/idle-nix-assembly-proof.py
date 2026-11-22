#!/usr/bin/env python3
"""Evaluate real Nix assembly and prove the child loads its packaged Wayland lib.

Dependency values are sentinels; this is not a full Nixpkgs/Qt build.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--guest-uuid', required=True)
    args = parser.parse_args()
    def run(command, **kwargs):
        return subprocess.run(command, check=True, text=True, capture_output=True, timeout=90, **kwargs)
    assert run(['id', '-un']).stdout.strip() == 'tester'
    assert run(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid']).stdout.strip() == args.guest_uuid
    assert run(['systemd-detect-virt', '--vm']).stdout.strip() in ('qemu', 'kvm')
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    assert run(['findmnt', '-T', str(work), '-n', '-o', 'FSTYPE']).stdout.strip() not in ('tmpfs', 'ramfs')
    library = work / 'wayland/lib'
    library.mkdir(parents=True)
    shutil.copyfile('/usr/lib/libwayland-client.so.0', library / 'libwayland-client.so.0')
    recipe = json.loads(run(['sudo', '-n', 'env', 'TMPDIR=' + os.environ['TMPDIR'], 'NIX_REMOTE=local',
        'nix-instantiate', '--eval', '--read-write-mode', '--strict', '--json',
        str(args.source / 'Scripts/dev/fixtures/locker-nix-assembly.nix'),
        '--arg', 'calendarSupport', 'false', '--argstr', 'waylandPrefix', str(library.parent)]).stdout)
    (work / 'recipe.json').write_text(json.dumps(recipe, indent=2))
    assert '--prefix LD_LIBRARY_PATH : ' + str(library) in recipe['preFixup']
    stage = work / 'stage'
    run(['bash', '-eu', '-c', recipe['installPhase']], cwd=recipe['src'], env=dict(os.environ, out=str(stage)))
    # Read the evaluated Qt wrapper arguments, not a separately maintained path.
    wrapped = run(['bash', '-eu', '-c', 'qtWrapperArgs=();\n' + recipe['preFixup'] + '\nprintf "%s\\0" "${qtWrapperArgs[@]}"'],
        env=dict(os.environ, out=str(stage))).stdout.split('\0')
    index = wrapped.index('LD_LIBRARY_PATH')
    assert wrapped[index - 1:index + 3] == ['--prefix', 'LD_LIBRARY_PATH', ':', str(library)]
    probe = run(['python3', '-B', str(stage / 'share/atmosphera/Scripts/python/idle-input-protocol.py')],
        env=dict(os.environ, LD_LIBRARY_PATH=wrapped[index + 2], LD_DEBUG='libs'))
    (work / 'loader.log').write_text(probe.stderr)
    assert 'calling init: ' + str(library / 'libwayland-client.so.0') in probe.stderr
    (work / 'result.json').write_text(json.dumps(dict(passed=True,
        scope='real recipe evaluation/installPhase and v2 probe with evaluated wrapper library path; no full Nix build')))
    print('IDLE_NIX_ASSEMBLY: PASS packaged library loaded; v2 probe exit=0')


if __name__ == '__main__':
    main()
