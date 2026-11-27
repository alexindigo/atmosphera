"""Persist already-validated originals. This process never opens an image codec."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
from urllib.parse import unquote_to_bytes, urlsplit

from .limits import source_byte_budget
from .lease import run
from .notification_originals import NotificationOriginals
from .storage import atomic_write, clear_legacy, directory, read_bytes
from .writes import write_exact


NATIVE_STAGE = re.compile(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}')
PNG_STAGE = re.compile(r'[1-9][0-9]*\.png')


def snapshot_stage(directory, leaf):
    if not isinstance(leaf, str) or not (PNG_STAGE.fullmatch(leaf) or NATIVE_STAGE.fullmatch(leaf)):
        raise ValueError('Invalid snapshot stage')
    return directory / leaf


def source_bytes(source):
    limit = source_byte_budget()
    if source.startswith('data:'):
        header, body = source.split(',', 1)
        raw = unquote_to_bytes(body)
        raw = base64.b64decode(raw, validate=True) if header.lower().endswith(';base64') else raw
    else:
        url = urlsplit(source)
        if url.scheme != 'file' or url.netloc or url.query or url.fragment:
            raise ValueError('Expected a leased local input')
        path = Path(os.fsdecode(unquote_to_bytes(url.path)))
        raw = read_bytes(path, limit=limit)
    if not raw or len(raw) > limit:
        raise ValueError('Invalid retained source size')
    return raw


def publish(data, capture_dir, notification, frames):
    leaf = data.get('stage')
    stage = snapshot_stage(capture_dir, leaf) if leaf is not None else None
    try:
        raw = (read_bytes(stage, limit=source_byte_budget()) if stage is not None
               else source_bytes(data['source']))
        if not raw:
            raise ValueError('Empty retained source')
        original_format = data['format']
        extension = 'png' if stage is not None and PNG_STAGE.fullmatch(leaf) else original_format
        if not re.fullmatch('[a-z0-9]+', extension):
            extension = 'image'
        digest = hashlib.sha256(raw).hexdigest()
        if stage is not None and NATIVE_STAGE.fullmatch(leaf) and digest != data.get('sha256'):
            raise ValueError('Retained snapshot digest mismatch')
        name = f'atmosphera-{digest}.{extension}'
        if data.get('notification'):
            if notification is None:
                raise ValueError('Notification history is not open')
            dest = notification.directory
            target = dest / name
            notification.publish(data['key'], name, lambda: atomic_write(target, raw, dest))
        elif data.get('frame'):
            target = frames / name
            atomic_write(target, raw, frames)
        else:
            dest = Path(data['directory'])
            if not dest.is_absolute() or '..' in dest.parts:
                raise ValueError('Invalid original destination')
            # User-selected wallpaper directories are not private cache roots.
            target = dest / name
            dest.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(prefix='.atmosphera-', dir=dest, delete=False) as file:
                temporary = Path(file.name)
                try:
                    write_exact(file, raw)
                    file.flush()
                    os.fsync(file.fileno())
                    os.replace(temporary, target)
                finally:
                    temporary.unlink(missing_ok=True)
        return dict(originalPath=str(target), originalFormat=extension, contentSha256=digest)
    finally:
        if stage is not None:
            stage.unlink(missing_ok=True)


def serve(cache, *, shell_pid):
    def emit(packet):
        print(json.dumps(packet, ensure_ascii=True), flush=True)

    def stop(_sig, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    # The worker owns temporary snapshots; EOF, including shell exit, retires
    # every unpublished file regardless of the ordering of QML destruction.
    images = Path(cache) / 'images'
    parent = images / 'staging'
    with directory(parent), tempfile.TemporaryDirectory(prefix='.originals-', dir=parent) as staging:
        stage = Path(staging)
        emit({'stage': str(stage)})
        owner = None
        for line in sys.stdin:
            reply = {'ok': False}
            try:
                packet = json.loads(line)
                reply['id'] = packet['id']
                action = packet['action']
                if packet.get('store'):
                    store = packet['store']
                    location = Path(store['directory']), Path(store['history'])
                    if owner is None:
                        owner = NotificationOriginals(*location, shell_pid)
                    elif (owner.directory, owner.history) != location:
                        raise ValueError('Notification retention store changed')
                if action == 'history':
                    reply['rows'] = owner.update(wanted=packet['wanted'], live=packet.get('live'),
                                                 load=packet.get('load', False), rows=packet.get('rows'))
                elif action == 'publish':
                    reply.update(publish(packet, stage, owner, images / 'video-wallpapers'))
                elif action == 'discard':
                    snapshot_stage(stage, packet['stage']).unlink(missing_ok=True)
                elif action == 'clear-legacy':
                    refused = sum(clear_legacy(images / relative)['refused']
                                  for relative in ('wallpapers/thumbnails', 'wallpapers/large', 'contributors'))
                    if refused:
                        raise ValueError('Legacy image cache refused its owner sweep')
                elif action != 'prepare':
                    raise ValueError('Unknown retention operation')
                reply['ok'] = True
            except (OSError, TypeError, ValueError, KeyError):
                # Source and history fields can contain private paths or URL tokens.
                reply.update(code='retention-unavailable', reason='Could not save or read retained image data')
            emit(reply)


if __name__ == '__main__':
    run(serve, sys.argv[1])
