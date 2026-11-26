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
from .storage import atomic_write, directory, read_bytes


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
    stage = None
    if leaf is not None:
        if not re.fullmatch(r'[1-9][0-9]*\.png', leaf):
            raise ValueError('Invalid provider snapshot stage')
        stage = capture_dir / leaf
    try:
        raw = (read_bytes(stage, limit=source_byte_budget()) if stage is not None
               else source_bytes(data['source']))
        if not raw:
            raise ValueError('Empty retained source')
        original_format = data['format']
        extension = 'png' if stage is not None else original_format
        if not re.fullmatch('[a-z0-9]+', extension):
            extension = 'image'
        digest = hashlib.sha256(raw).hexdigest()
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
                    file.write(raw)
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
                    leaf = packet['stage']
                    if not re.fullmatch(r'[1-9][0-9]*\.png', leaf):
                        raise ValueError('Invalid snapshot stage')
                    (stage / leaf).unlink(missing_ok=True)
                elif action != 'prepare':
                    raise ValueError('Unknown retention operation')
                reply['ok'] = True
            except (OSError, TypeError, ValueError, KeyError):
                # Source and history fields can contain private paths or URL tokens.
                reply.update(code='retention-unavailable', reason='Could not save or read retained image data')
            emit(reply)


if __name__ == '__main__':
    run(serve, sys.argv[1])
