"""Two-slot replacement-interest worker shared by image and video adapters."""
import asyncio
import json
import os
import signal
import sys

from .cache import Cache
from .process import CommandError
from .sources import SourceError


class Worker:
    def __init__(self, cache, emit):
        self.cache, self.emit = cache, emit
        self.tasks, self.wanted = {}, {}
        self.retired = set()
        self.leases = {}
        self.slots = asyncio.Semaphore(2)

    def _release(self, key):
        fd = self.leases.pop(key, None)
        if fd is not None:
            os.close(fd)

    def _restore_lease(self, key, url):
        # Lease snapshots and clear commands share one synchronous protocol
        # order. Restoring a held URL cannot wait for a decoder task turn.
        try:
            lease = self.cache.lease(dict(status='hit', url=url))
        except (OSError, ValueError):
            lease = None
        if lease is not None:
            self.leases[key] = lease

    def clear(self, message):
        # Synchronous on the protocol loop: a sweep completes before EOF can
        # retire this process, and its own leases cannot interleave with it.
        try:
            return dict(event='cleared', id=message['id'], **self.cache.clear(message.get('legacy', [])))
        except OSError:
            return dict(event='clear-failed', id=message['id'], code='cache-clear-failed',
                        reason='The image cache could not be cleared')

    async def request(self, item):
        key = item.get('id', item.get('path'))
        envelope = {field: item[field] for field in ('id', 'generation', 'path', 'stamp', 'pixels', 'width', 'height', 'animationIntent') if field in item}
        if 'lease' in item:
            # A settled consumer still holds this URL. Never re-render it; a
            # name already cleared simply has no lease to restore.
            self._restore_lease(key, item['lease'])
            return
        try:
            for _attempt in range(3):
                if item.get('operation') == 'inspect' and 'source' in item:
                    result = await self.cache.render(item, inspection_slots=self.slots)
                else:
                    async with self.slots:
                        result = await (self.cache.render(item) if 'source' in item else self.cache.get(item['path'], item['pixels']))
                # Lease before the URL is published: an owner clear in this or
                # another process keeps a leased name until the interest retires.
                try:
                    lease = self.cache.lease(result)
                except OSError:
                    continue
                if lease is not None:
                    self.leases[key] = lease
                break
            else:
                result = dict(url='', status='unavailable', code='cache-changed',
                              reason='The image cache entry was cleared while it was being published')
            self.emit(dict(envelope, **result))
        except asyncio.CancelledError:
            self.emit(dict(event='cancelled', id=key))
            raise
        except (SourceError, CommandError, OSError, ValueError, KeyError, TypeError) as error:
            self.emit(dict(envelope, url='', status='unavailable', code=getattr(error, 'code', 'decode-unavailable'),
                           reason=str(error) if isinstance(error, (SourceError, CommandError)) else 'Image could not be read'))

    def replace(self, items):
        if not isinstance(items, list) or any(not isinstance(item, dict) or not item.get('id', item.get('path')) for item in items):
            raise ValueError('Invalid image interests')
        wanted = {item.get('id', item.get('path')): item for item in items}
        if len(wanted) != len(items):
            raise ValueError('Duplicate image request IDs')
        def same(key):
            # The lease form of a request this process already settled and
            # leased is the same interest; releasing it would open a window.
            old, new = self.wanted.get(key), wanted.get(key)
            return old == new or (new is not None and old is not None and 'lease' in new and key in self.leases
                                  and (old.get('id'), old.get('generation')) == (new.get('id'), new.get('generation')))
        for key in list(self.leases):
            if not same(key):
                self._release(key)
        for key, task in self.tasks.items():
            if not same(key):
                task.cancel()
                self.retired.add(task)
                task.add_done_callback(self.retired.discard)
        self.tasks = {key: task for key, task in self.tasks.items() if same(key)}
        for key, item in wanted.items():
            if 'lease' in item:
                if key not in self.leases:
                    self._restore_lease(key, item['lease'])
            elif key not in self.tasks:
                self.tasks[key] = asyncio.create_task(self.request(item))
        self.wanted = wanted

    async def close(self):
        tasks = list(set(self.tasks.values()) | self.retired)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for key in list(self.leases):
            self._release(key)


async def serve():
    os.nice(10)
    def emit(event):
        print(json.dumps(event), flush=True)
    worker = Worker(Cache(emit=emit), emit)
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    transport, _ = await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, reader.feed_eof)
    emit(dict(event='ready'))
    pending = bytearray()
    try:
        while block := await reader.read(65536):
            pending.extend(block)
            while b'\n' in pending:
                line, _, rest = pending.partition(b'\n')
                pending = bytearray(rest)
                try:
                    message = json.loads(line)
                    if isinstance(message, dict):
                        legacy = message.get('legacy', [])
                        if (message.get('command') != 'clear' or not isinstance(message.get('id'), str)
                                or not set(message) <= {'command', 'id', 'legacy'} or not isinstance(legacy, list)
                                or not all(isinstance(path, str) and os.path.isabs(path) and '..' not in path.split('/')
                                           for path in legacy)):
                            raise ValueError('Unknown image worker command')
                        emit(worker.clear(message))
                    else:
                        worker.replace(message)
                except (ValueError, TypeError, UnicodeError):
                    # A protocol failure settles the current batch. It cannot
                    # silently keep requests alive or retry indefinitely.
                    await worker.close()
                    worker.replace([])
                    emit(dict(event='protocol-error', code='invalid-request', reason='Invalid image request message'))
    finally:
        await worker.close()
        transport.close()
