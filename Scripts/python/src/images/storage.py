"""Directory-bound cache I/O; source paths are never cache parents."""
from contextlib import contextmanager, ExitStack
import errno
import fcntl
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


LEAF = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC
LOCK = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC


@contextmanager
def namespace(root, exclusive):
    """Serialize lease admission against a clear sweep of one private namespace.

    Holders of the shared side only check and lease names; a sweep holds the
    exclusive side, so no name can gain a lease between its check and unlink.
    """
    # Leasing may create the namespace like a writer; a sweep never creates it.
    with directory(root, create=not exclusive, private=not exclusive) as base:
        fd = os.open('.namespace.lock', LOCK, 0o600, dir_fd=base)
        try:
            owned(fd)
            fcntl.flock(fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
            yield base
        finally:
            os.close(fd)


def lease(root, path):
    """Hold a published name for as long as its consumer holds the URL.

    The advisory lock lives on a per-name lease file rather than the inode, so
    an equivalent concurrent publication that replaces the inode keeps its lease.
    Returns the lease descriptor; a vanished or foreign leaf raises OSError.
    """
    path, root = Path(path), Path(root)
    relative = path.relative_to(root)
    if len(relative.parts) != 2 or '..' in relative.parts or relative.name.startswith('.'):
        raise ValueError('Image cache lease is outside its representation namespace')
    with namespace(root, False) as base:
        with directory(path.parent, create=False, private=False) as parent:
            leaf = os.open(path.name, LEAF, dir_fd=parent)
            try:
                owned(leaf)
                if not stat.S_ISREG(os.fstat(leaf).st_mode):
                    raise OSError(errno.EINVAL, 'Image cache entry is not a regular file')
            finally:
                os.close(leaf)
        try:
            os.mkdir('leases', mode=0o700, dir_fd=base)
        except FileExistsError:
            pass
        leases = os.open('leases', FLAGS, dir_fd=base)
        try:
            owned(leases)
            fd = os.open(relative.parts[0] + '-' + relative.name + '.lease', LOCK, 0o600, dir_fd=leases)
        finally:
            os.close(leases)
        try:
            owned(fd)
            fcntl.flock(fd, fcntl.LOCK_SH)
        except BaseException:
            os.close(fd)
            raise
        return fd


def _sweep(parent, leases, name, entry):
    if entry.startswith('.'):
        return 'kept'
    info = os.stat(entry, dir_fd=parent, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        return 'kept'
    lease_name = name + '-' + entry + '.lease'
    held = None
    if leases is not None:
        try:
            held = os.open(lease_name, os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=leases)
        except FileNotFoundError:
            pass
    try:
        if held is not None:
            try:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return 'kept'
        os.unlink(entry, dir_fd=parent)
        if held is not None:
            os.unlink(lease_name, dir_fd=leases)
        return 'removed'
    finally:
        if held is not None:
            os.close(held)


def clear(root, names):
    """Remove unleased owner representations; never staging, sources or links.

    Entries are addressed only through no-follow descriptors of the owner's own
    namespace directories. Another writer's in-flight leaf, a leased name, a
    planted non-regular entry or a redirected namespace directory is retained.
    """
    counts = dict(removed=0, kept=0, refused=0)
    with ExitStack() as stack:
        try:
            base = stack.enter_context(namespace(root, True))
        except FileNotFoundError:
            return counts
        try:
            leases = os.open('leases', FLAGS, dir_fd=base)
            stack.callback(os.close, leases)
        except FileNotFoundError:
            leases = None
        for name in names:
            try:
                parent = os.open(name, FLAGS, dir_fd=base)
            except FileNotFoundError:
                continue
            except OSError:
                counts['refused'] += 1
                continue
            try:
                owned(parent)
                for entry in os.listdir(parent):
                    counts[_sweep(parent, leases, name, entry)] += 1
            finally:
                os.close(parent)
    return counts


def clear_legacy(path):
    """Remove top-level legacy shell outputs (flat *.png) from a retired folder.

    Subdirectories belong to plugins that still own their thumbnails there.
    """
    counts = dict(removed=0, kept=0, refused=0)
    try:
        with directory(path, create=False, private=False) as parent:
            for entry in os.listdir(parent):
                info = os.stat(entry, dir_fd=parent, follow_symlinks=False)
                if (entry.startswith('.') or not entry.endswith('.png') or not stat.S_ISREG(info.st_mode)
                        or info.st_uid != os.getuid()):
                    counts['kept'] += 1
                    continue
                os.unlink(entry, dir_fd=parent)
                counts['removed'] += 1
    except FileNotFoundError:
        pass
    except OSError as error:
        if error.errno not in (errno.ELOOP, errno.ENOTDIR):
            raise
        counts['refused'] += 1
    return counts


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
