"""Shared disk-backed workspace guard for guest test and lint entry points.

Guest RAM-backed storage must never hold workspaces or TMPDIR. The guard checks
the property itself: the filesystem that actually backs a resolved path, taken
from this process's mount table. Reserved runtime roots and an empty path are
rejected as well. Only the standard library and /proc are used, so callers can
validate before creating directories or starting processes.
"""
import os
from pathlib import Path
import re

# Runtime roots never used as workspaces, compared in literal and resolved form.
MEMORY_BACKED_ROOTS = ('/tmp', '/dev/shm', '/run', '/var/run')
MEMORY_FILESYSTEMS = frozenset({'tmpfs', 'ramfs', 'devtmpfs', 'hugetlbfs'})
MESSAGE = 'use disk-backed workspace and TMPDIR'
MOUNTINFO = '/proc/self/mountinfo'


def _unescape(field):
    """Decode mountinfo's octal escapes (space, tab, newline, backslash)."""
    return re.sub(r'\\([0-7]{3})', lambda match: chr(int(match.group(1), 8)), field)


def backing_filesystem(path):
    """Type of the mount containing path; the last of stacked mounts wins."""
    resolved = Path(path).resolve()
    best = fstype = None
    with open(MOUNTINFO, encoding='utf-8', errors='surrogateescape') as table:
        for line in table:
            fields, _, rest = line.partition(' - ')
            mountpoint = Path(_unescape(fields.split()[4]))
            if resolved == mountpoint or mountpoint in resolved.parents:
                if best is None or len(mountpoint.parts) >= len(best.parts):
                    best, fstype = mountpoint, rest.split()[0]
    if fstype is None:
        raise ValueError(f'{MESSAGE}: no mount contains {resolved}')
    return fstype


def require_disk_backed_paths(*paths):
    """Reject empty paths, reserved runtime roots and memory-backed filesystems."""
    roots = {form for root in MEMORY_BACKED_ROOTS for form in (Path(root), Path(root).resolve())}
    for path in paths:
        if path is None or (isinstance(path, str) and not path.strip()):
            raise ValueError(MESSAGE)
        resolved = Path(path).resolve()
        if any(resolved == root or root in resolved.parents for root in roots):
            raise ValueError(MESSAGE)
        if backing_filesystem(resolved) in MEMORY_FILESYSTEMS:
            raise ValueError(MESSAGE)


def check_execution_paths(parser, workspace):
    """Validate an entry point's workspace and TMPDIR before it creates either."""
    tmpdir = os.environ.get('TMPDIR', '')
    if not tmpdir.strip():
        parser.error('set TMPDIR to a disk-backed directory inside the assigned VM')
    try:
        require_disk_backed_paths(workspace, tmpdir)
    except ValueError:
        parser.error('use disk-backed workspace and TMPDIR inside the assigned VM')
