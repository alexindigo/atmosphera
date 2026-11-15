"""Own disposable root-level QML probes without adopting caller-owned files."""
from contextlib import ExitStack
import os
from pathlib import Path
import tempfile


def _remove_owned(path, identity):
    try:
        current = path.lstat()
    except FileNotFoundError:
        return
    if (current.st_dev, current.st_ino) != identity:
        raise RuntimeError(f'probe cleanup refused replaced file: {path}')
    path.unlink()


class ProbeFiles:
    """Acquire exclusively and unwind every acquired file on partial failure."""
    def __init__(self, source, fixture):
        self._files = ExitStack()
        try:
            content = Path(fixture).read_bytes()
            fd, name = tempfile.mkstemp(dir=source, prefix='.atcq-probe-', suffix='.qml')
            self.probe = Path(name)
            with os.fdopen(fd, 'wb') as stream:
                self._own(self.probe, stream)
                stream.write(content)
            qmlls = Path(source) / '.qmlls.ini'
            try:
                stream = qmlls.open('x')
            except FileExistsError:
                pass
            else:
                with stream:
                    self._own(qmlls, stream)
        except BaseException:
            self.close()
            raise

    def _own(self, path, stream):
        stat = os.fstat(stream.fileno())
        self._files.callback(_remove_owned, path, (stat.st_dev, stat.st_ino))

    def close(self):
        self._files.close()
