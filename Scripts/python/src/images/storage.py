"""Directory-bound private cache writes; source paths are never cache parents."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import secrets


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
