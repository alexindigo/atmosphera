"""Directory-bound cache I/O; source paths are never cache parents."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import secrets
import stat


FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def owned(fd):
    if os.fstat(fd).st_uid != os.getuid():
        raise PermissionError('Image cache directory belongs to another account')


@contextmanager
def directory(path, create=True, private=True):
    """Open each literal directory component, without following parent links."""
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('Image cache needs an absolute literal directory')
    fd = os.open('/', FLAGS)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, FLAGS, dir_fd=fd)
            os.close(fd)
            fd = child
        owned(fd)
        if private:
            os.fchmod(fd, 0o700)
        yield fd
    finally:
        os.close(fd)


def descriptor_path(fd):
    # A decoder child must address the parent's still-open descriptor, not its
    # own close-on-exec descriptor table. The parent holds it until every child
    # is joined and the operation-private directory has been retired.
    return Path(f'/proc/{os.getpid()}/fd/{fd}')


def identity(info):
    return tuple(getattr(info, field) for field in ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns'))


@contextmanager
def open_file(path):
    """Read an existing regular cache leaf, holding its parent and identity.

    Readers never create/chmod directories. The current predicate also checks
    the literal parent path after asynchronous snapshot validation, so a renamed
    directory or leaf cannot turn a validated snapshot into an unrelated hit URL.
    Ordinary user source paths deliberately do not use this cache boundary.
    """
    path = Path(path)
    with directory(path.parent, create=False, private=False) as parent:
        parent_info = os.fstat(parent)
        fd = os.open(path.name, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
        with os.fdopen(fd, 'rb') as stream:
            owned(stream.fileno())
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise ValueError('Image cache entry is not a regular file')

            def current():
                try:
                    if not stream.closed and identity(before) != identity(os.fstat(stream.fileno())):
                        return False
                    with directory(path.parent, create=False, private=False) as now:
                        info = os.fstat(now)
                        return ((parent_info.st_dev, parent_info.st_ino) == (info.st_dev, info.st_ino)
                                and identity(before) == identity(os.stat(path.name, dir_fd=now, follow_symlinks=False)))
                except OSError:
                    return False

            yield stream, current


def read_bytes(path):
    with open_file(path) as (stream, current):
        data = stream.read()
        if not current():
            raise OSError(errno.ESTALE, 'Image cache entry changed during capture')
        return data


def atomic_write(path, data, root):
    path, root = Path(path), Path(root)
    relative = path.relative_to(root)
    if '..' in relative.parts or len(relative.parts) < 1:
        raise ValueError('Image cache output is outside its owner')
    with directory(root) as base:
        fd = os.dup(base)
        temporary = None
        try:
            for part in relative.parts[:-1]:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, FLAGS, dir_fd=fd)
                try:
                    owned(child)
                    os.fchmod(child, 0o700)
                except BaseException:
                    os.close(child)
                    raise
                os.close(fd)
                fd = child
            candidate = '.atmosphera-' + secrets.token_hex(16)
            output = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                             0o600, dir_fd=fd)
            temporary = candidate
            with os.fdopen(output, 'wb') as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, relative.name, src_dir_fd=fd, dst_dir_fd=fd)
            temporary = None
            os.fsync(fd)
            # A parent swap cannot redirect the write. Do not publish a URL
            # into the replacement tree if the bound directory was moved away.
            with directory(path.parent, create=False, private=False) as current:
                before, after = os.fstat(fd), os.fstat(current)
                if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
                    raise OSError(errno.ESTALE, 'Image cache directory changed during publication')
        finally:
            if temporary is not None:
                try:
                    os.unlink(temporary, dir_fd=fd)
                except FileNotFoundError:
                    pass
            os.close(fd)
