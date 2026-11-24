#!/usr/bin/env python3
"""Guest control for transporting the candidate source into a package build."""
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace

from image_decoding_packages import snapshot


def main():
    with tempfile.TemporaryDirectory(prefix='image-package-transport-') as tmp:
        root = Path(tmp)
        source, work = root / 'source', root / 'work'
        (source / 'Scripts' / 'nested').mkdir(parents=True)
        (source / 'empty').mkdir()
        script = source / 'Scripts' / 'nested' / 'fixture'
        script.write_bytes(b'fixture\n')
        script.chmod(0o755)
        (source / 'Scripts' / 'link').symlink_to('nested/fixture')
        work.mkdir()

        def check(name, condition, detail):
            if not condition:
                raise AssertionError((name, detail))

        repo = snapshot(SimpleNamespace(args=SimpleNamespace(source=source), work=work, out=root, check=check))
        clone = root / 'clone'
        subprocess.run(['git', 'clone', '--quiet', str(repo), str(clone)], check=True)
        if ((clone / script.relative_to(source)).read_bytes() != script.read_bytes()
                or not os.access(clone / script.relative_to(source), os.X_OK)
                or os.readlink(clone / 'Scripts' / 'link') != 'nested/fixture'
                or not (repo / 'empty').is_dir() or (clone / 'empty').exists()):
            raise AssertionError('Git transport did not preserve the candidate leaves')
    print('PASS package transport: nested executable and link survive clone; source directory receipt unchanged')


if __name__ == '__main__':
    main()
