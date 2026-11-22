"""Retire only a proven, completed, rebuildable image fixture source copy."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil

from image_decoding_evidence import source_manifest


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
            if process.stat().st_uid == os.getuid() and str(copy).encode() in (process / 'cmdline').read_bytes():
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
    # This finite delta and the complete source receipt reconstruct every byte
    # and mode. Settings, cache, VFS, captures and failed runs are separate roots.
    record = dict(source=str(source), copy=str(copy), sourceReceipt=str(receipt), baseSha256=base['sha256'],
                  copySha256=actual['sha256'], deltas=delta, retired=False)
    output.write_text(json.dumps(record, indent=2) + '\n')
    if source_manifest(copy) != actual:
        raise ValueError('Fixture input changed before retirement')
    shutil.rmtree(copy)
    record['retired'] = not copy.exists()
    output.write_text(json.dumps(record, indent=2) + '\n')
    if not record['retired']:
        raise AssertionError('Fixture source copy did not retire')
    return record
