"""Literal source staging and opened-file identity for independent decoders."""
import asyncio
import base64
from contextlib import asynccontextmanager
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile
from urllib.parse import unquote, unquote_to_bytes, urlsplit

from .process import command, CommandError


class SourceError(Exception):
    def __init__(self, code, reason):
        super().__init__(reason)
        self.code = code


def identity(info):
    return tuple(getattr(info, key) for key in ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns'))


def local_path(source):
    if source.startswith('file:'):
        parsed = urlsplit(source)
        if parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
            raise SourceError('invalid-source', 'A local image needs a literal file URL')
        return Path(os.fsdecode(unquote_to_bytes(parsed.path))).absolute()
    if '://' in source or source.startswith('data:'):
        return None
    return Path(os.fsdecode(source)).absolute()


@asynccontextmanager
async def prepare(source, root, revision='', emit=lambda event: None):
    root = Path(root)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    # The safe operation-private basename is intentional: brackets, colon and
    # leading '-' in the user's filename never reach ImageMagick's parser.
    with tempfile.TemporaryDirectory(prefix='.source-', dir=root) as directory:
        directory = Path(directory)
        target = directory / 'source.bin'
        path, before = None, None
        source_hash = hashlib.sha256()
        try:
            path = local_path(source)
            if path is not None:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                with os.fdopen(fd, 'rb') as stream:
                    info = os.fstat(stream.fileno())
                    if not stat.S_ISREG(info.st_mode):
                        raise SourceError('unreadable', 'Image source is not a readable regular file')
                    before = identity(info)
                    with target.open('xb') as output:
                        while block := stream.read(1024 * 1024):
                            output.write(block)
                            source_hash.update(block)
                            await asyncio.sleep(0)
                    if before != identity(os.fstat(stream.fileno())) or before != identity(path.stat()):
                        raise SourceError('source-changed', 'Image source changed while being read')
            elif source.startswith('data:'):
                header, value = source.split(',', 1)
                value = unquote_to_bytes(value)
                payload = base64.b64decode(value, validate=True) if header.endswith(';base64') else value
                target.write_bytes(payload)
                source_hash.update(payload)
            elif urlsplit(source).scheme.lower() in ('http', 'https'):
                try:
                    # Keep URL credentials and query tokens out of diagnostics.
                    await command([sys.executable, '-B', str(Path(__file__).with_name('download.py')), source, target],
                                  directory, 30, name='download')
                except CommandError as error:
                    raise SourceError('download-failed', 'Could not download the image') from error
                with target.open('rb') as stream:
                    while block := stream.read(1024 * 1024):
                        source_hash.update(block)
            elif source.startswith('image://'):
                raise SourceError('provider-required', 'A Qt image provider must be retained in process')
            else:
                raise SourceError('invalid-source', 'Unsupported image source')
        except FileNotFoundError as error:
            raise SourceError('missing', 'Image source does not exist') from error
        except PermissionError as error:
            raise SourceError('unreadable', 'Image source is not readable') from error
        except (ValueError, OSError) as error:
            raise SourceError('invalid-source', 'Image source could not be read') from error
        if not target.stat().st_size:
            raise SourceError('invalid-image', 'Image source is empty')
        def current():
            if path is None:
                return True
            try:
                return before == identity(path.stat())
            except OSError:
                return False
        yield dict(path=target, directory=directory, original=path, stat=before,
                   contentSha256=source_hash.hexdigest(), revision=revision, current=current)
