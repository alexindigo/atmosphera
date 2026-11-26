#!/usr/bin/env python3
"""Guest control for qualifying the exact candidate source, including dirty leaves."""
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace

from image_decoding_packages import qualify


def main():
    with tempfile.TemporaryDirectory(prefix='image-package-transport-') as tmp:
        root = Path(tmp)
        source, out = root / 'source', root / 'out'
        (source / 'Scripts' / 'nested').mkdir(parents=True)
        script = source / 'Scripts' / 'nested' / 'fixture'
        script.write_bytes(b'fixture\n')
        script.chmod(0o755)
        (source / 'Scripts' / 'link').symlink_to('nested/fixture')
        out.mkdir()
        for variant in ('atmosphera', 'atmosphera-git'):
            (source / 'packaging/aur' / variant).mkdir(parents=True)

        def check(name, condition, detail):
            if not condition:
                raise AssertionError((name, detail))

        def command(argv, *, cwd=None, timeout=None):
            if argv[0] == 'makepkg':
                assert cwd in {source / 'packaging/aur/atmosphera', source / 'packaging/aur/atmosphera-git'}
                return SimpleNamespace(returncode=0, stdout='\tdepends = qt6-imvqml\n\tdepends = qt6-mpvqml\n\tdepends = quickshell\n')
            assert argv[0] == 'nix' and f'path:{source}#default' in argv and '--no-update-lock-file' in argv
            assert script.read_bytes() == b'fixture\n' and os.access(script, os.X_OK)
            assert os.readlink(source / 'Scripts/link') == 'nested/fixture'
            return SimpleNamespace(returncode=0, stdout='{"inputs":["/nix/store/hash-qt6-imvqml-0.1.2"],"preFixup":"/nix/store/hash-qt6-imvqml-0.1.2/qml"}', stderr='')

        qualify(SimpleNamespace(args=SimpleNamespace(source=source), out=out, check=check, command=command))
        assert {entry.name for entry in out.iterdir()} == {'atmosphera.SRCINFO', 'atmosphera-git.SRCINFO', 'nix-eval.log'}
    print('PASS package qualification uses the exact candidate path without a Git round trip')


if __name__ == '__main__':
    main()
