"""Retire only a proven, completed, rebuildable image fixture source copy."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time

from image_decoding_evidence import source_manifest


def atomic_receipt(path, record):
    """Failure preserves the previous complete receipt, never a truncated one."""
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(record, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        Path(temporary).unlink(missing_ok=True)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def preserve_object(path, record, store):
    """Publish once by content hash. Existing immutable objects are verified."""
    target = store / record['sha256']
    if not target.exists():
        fd, temporary = tempfile.mkstemp(prefix='.object-', dir=store)
        try:
            digest = hashlib.sha256()
            with os.fdopen(fd, 'wb') as output, path.open('rb') as source:
                while block := source.read(1024 * 1024):
                    digest.update(block)
                    output.write(block)
                if digest.hexdigest() != record['sha256']:
                    raise ValueError('Fixture input changed during object preservation')
                output.flush()
                os.fchmod(output.fileno(), 0o444)
                os.fsync(output.fileno())
            try:
                os.link(temporary, target)
            except FileExistsError:
                pass
            sync_directory(store)
        finally:
            Path(temporary).unlink(missing_ok=True)
    fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o222:
            raise ValueError('Fixture object is not an owned immutable file')
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
        if digest != record['sha256']:
            raise ValueError('Fixture object does not match its content address')
    return str(target)


def settle_fixture_session(proc, timeout=2):
    """Wait for an exited session leader's fd-owned cleanup to finish."""
    if proc.poll() is None:
        raise ValueError('Fixture session leader has not exited')
    deadline = time.monotonic() + timeout
    while True:
        try:
            # Popen started a private session. An orphaned child can still
            # hold this group after the leader is reaped. Never signal it.
            os.killpg(proc.pid, 0)
        except ProcessLookupError:
            return
        if time.monotonic() >= deadline:
            raise ValueError('Fixture session still has a live consumer: ' + str(proc.pid))
        time.sleep(.02)


def retire_fixture_copy(source, copy, receipt, output, work_root):
    source, copy, receipt, output, work_root = map(Path, (source, copy, receipt, output, work_root))
    if (copy != copy.resolve() or copy.parent != work_root.resolve() or copy == source
            or not copy.is_dir() or output.exists()):
        raise ValueError('Expected a completed private fixture copy and a fresh receipt')
    base = json.loads(receipt.read_text())
    if source_manifest(source) != base:
        raise ValueError('Canonical source changed after fixture creation')
    actual = source_manifest(copy)
    changed = {key: row for key, row in actual['files'].items() if base['files'].get(key) != row}
    removed = set(base['files']) - set(actual['files'])
    if removed or not changed or set(changed) - {'image-decoding-fixture.qml', '.qmlls.ini'}:
        raise ValueError('Fixture copy contains unexplained changes')
    for process in Path('/proc').iterdir():
        if not process.name.isdecimal() or int(process.name) == os.getpid():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            if (str(copy).encode() in (process / 'cmdline').read_bytes()
                    or Path(os.readlink(process / 'cwd')).is_relative_to(copy)):
                raise ValueError('Fixture copy still has a live consumer: ' + process.name)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    delta = {}
    for key, record in changed.items():
        row = dict(record=record)
        if record['type'] == 'file':
            data = (copy / key).read_bytes()
            if hashlib.sha256(data).hexdigest() != record['sha256']:
                raise ValueError('Fixture input changed during preservation')
            row['bytesBase64'] = base64.b64encode(data).decode()
        delta[key] = row
    # The copy itself supplies every byte. Canonical source edits after its
    # initial check cannot invalidate immutable reconstruction objects.
    scratch = Path(os.environ['TMPDIR'])
    if scratch != scratch.resolve() or not copy.is_relative_to(scratch.parent):
        raise ValueError('Fixture objects must stay in the guest disk workspace')
    store = scratch.parent / '.image-fixture-objects'
    store.mkdir(mode=0o700, exist_ok=True)
    if store.resolve() != store or store.stat().st_uid != os.getuid():
        raise ValueError('Fixture objects need an owned canonical disk directory')
    objects = {row['sha256']: preserve_object(copy / key, row, store)
               for key, row in actual['files'].items() if row['type'] == 'file'}
    record = dict(source=str(source), copy=str(copy), sourceReceipt=str(receipt), baseSha256=base['sha256'],
                  copySha256=actual['sha256'], baseManifest=base, copyManifest=actual,
                  objects=objects, deltas=delta, retired=False)
    atomic_receipt(output, record)
    if source_manifest(copy) != actual:
        raise ValueError('Fixture input changed before retirement')
    shutil.rmtree(copy)
    record['retired'] = not copy.exists()
    atomic_receipt(output, record)
    if not record['retired']:
        raise AssertionError('Fixture source copy did not retire')
    return record
