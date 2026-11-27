#!/usr/bin/env python3
"""Guest control for qualifying the exact candidate source, including dirty leaves."""
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace

from image_decoding_packages import qualify
from image_decoding_review import inspect, packages


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
                return SimpleNamespace(returncode=0, stdout=f'pkgbase = {cwd.name}\n'
                    '\tdepends = qt6-imvqml>=0.1.6\n\tdepends = qt6-mpvqml>=0.3.0\n\tdepends = quickshell\n'
                    '\tdepends = python\n\toptdepends = qt6-5compat: optional\n'
                    f'\npkgname = {cwd.name}\n')
            assert argv[0] == 'nix' and f'path:{source}#default' in argv and '--no-update-lock-file' in argv
            assert script.read_bytes() == b'fixture\n' and os.access(script, os.X_OK)
            assert os.readlink(source / 'Scripts/link') == 'nested/fixture'
            return SimpleNamespace(returncode=0, stdout=json.dumps(dict(inputs=['/nix/store/hash-qt6-imvqml-0.1.6'],
                preFixup='qtWrapperArgs+=(\n'
                '  --prefix PATH : /nix/store/hash-python3-3.13/bin:/nix/store/hash-quickshell-0.2/bin\n'
                '  --prefix QML_IMPORT_PATH : /nix/store/hash-qt6-imvqml-0.1.6/lib/qt-6/qml\n)\n')), stderr='evaluation warning\n')

        outputs = []

        def record(name, condition, detail):
            check(name, condition, detail)
            outputs.append(dict(id=name, result='PASS'))

        qualify(SimpleNamespace(args=SimpleNamespace(source=source), out=out, check=record, command=command))
        assert packages(out)['nixDecoder'] == '/nix/store/hash-qt6-imvqml-0.1.6'
        expected = dict(source='test-source')
        outputs.append(dict(id='qualified-inputs-unchanged', result='PASS'))
        contract = json.loads((Path(__file__).parent / 'fixtures/image-decoding/required-cases.json').read_text())
        (out / 'result.json').write_text(json.dumps(dict(case='packaging', inputs=expected, state='complete',
                                                        qtWebp='present', cases=outputs)))
        assert inspect(out, contract['packaging'], expected, 'present')['endpoints'] == []

        def reject(file, mutate, reason):
            path = out / file
            original = path.read_text()
            path.write_text(mutate(original))
            try:
                packages(out)
            except AssertionError as problem:
                assert reason in str(problem), problem
            else:
                raise AssertionError('Unnoticed bad package receipt: ' + reason)
            finally:
                path.write_text(original)

        reject('atmosphera.SRCINFO', lambda text: text.replace('depends = qt6-imvqml', 'optdepends = qt6-imvqml'),
               'atmosphera: missing dependencies')
        reject('atmosphera-git.SRCINFO', lambda text: text + '\tdepends = imagemagick>=7\n',
               'atmosphera-git: retired dependencies')
        reject('nix-eval.json', lambda text: text.replace(':/nix/store/hash-quickshell', ':/nix/store/hash-ffmpeg-8/bin:/nix/store/hash-quickshell'),
               'Retired direct Nix dependencies: ffmpeg-8')
        reject('nix-eval.json', lambda text: text.replace('QML_IMPORT_PATH', 'NOT_AN_IMPORT_PATH'),
               'Wrapper missing imvqml QML import path')
    print('PASS package qualification and independent artifact review')


if __name__ == '__main__':
    main()
