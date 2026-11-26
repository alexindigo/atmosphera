"""Sample dev input through the same installed image owner as the shell."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def sample_rgba(source, path):
    env = dict(os.environ, ATMO_SAMPLE_SOURCE=path.resolve().as_uri(), QT_QPA_PLATFORM='offscreen')
    # Quickshell restricts relative imports to the selected configuration
    # directory. Stage just the fixture and its production byte encoder.
    with tempfile.TemporaryDirectory(prefix='atmo-sample-', dir=env['TMPDIR']) as work:
        entry = Path(work) / 'shell.qml'
        shutil.copyfile(source / 'Scripts/dev/fixtures/theming-sample-cli.qml', entry)
        shutil.copyfile(source / 'Helpers/ImageBytes.js', Path(work) / 'ImageBytes.js')
        result = subprocess.run(['qs', '-p', str(entry), '--no-duplicate'], env=env,
                                capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    rows = [line.split('ATMO_RGBA|', 1)[1] for line in (result.stdout + result.stderr).splitlines()
            if 'ATMO_RGBA|' in line]
    if len(rows) != 1:
        raise ValueError('Expected one imvqml RGBA sample')
    return rows[0] + '\n'
