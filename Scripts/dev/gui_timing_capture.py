"""External byte-exact console capture. The shell's stdout is never a disk file."""
import hashlib
from pathlib import Path
import threading


class ConsoleCapture:
    def __init__(self, stream, destination):
        self.stream = stream
        self.destination = Path(destination)
        self.error = None
        self.bytes = 0
        self.digest = hashlib.sha256()
        self.thread = threading.Thread(target=self._drain, name='gui-console-drain')
        self.thread.start()

    def _drain(self):
        try:
            with self.destination.open('xb') as output:
                while True:
                    chunk = self.stream.read1(65536)
                    if not chunk:
                        break
                    written = output.write(chunk)
                    if written != len(chunk):
                        raise OSError('short console write')
                    self.bytes += len(chunk)
                    self.digest.update(chunk)
        except BaseException as error:
            self.error = error
        finally:
            self.stream.close()

    def finish(self):
        self.thread.join(timeout=15)
        if self.thread.is_alive():
            raise RuntimeError('console collector did not reach EOF')
        if self.error is not None:
            raise RuntimeError('console collector failed') from self.error
        with self.destination.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if self.destination.stat().st_size != self.bytes or actual != self.digest.hexdigest():
            raise RuntimeError('console capture differs from drained bytes')
        return dict(path=str(self.destination), bytes=self.bytes, sha256=actual, joined=True)
