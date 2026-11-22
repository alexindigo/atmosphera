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
        self.slots = asyncio.Semaphore(2)

    async def request(self, item):
        key = item.get('id', item.get('path'))
        envelope = {field: item[field] for field in ('id', 'generation', 'path', 'stamp', 'pixels', 'width', 'height', 'animationIntent') if field in item}
        try:
            if item.get('operation') == 'inspect' and 'source' in item:
                result = await self.cache.render(item, inspection_slots=self.slots)
            else:
                async with self.slots:
                    result = await (self.cache.render(item) if 'source' in item else self.cache.get(item['path'], item['pixels']))
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
        for key, task in self.tasks.items():
            if wanted.get(key) != self.wanted.get(key):
                task.cancel()
                self.retired.add(task)
                task.add_done_callback(self.retired.discard)
        self.tasks = {key: task for key, task in self.tasks.items() if wanted.get(key) == self.wanted.get(key)}
        for key, item in wanted.items():
            if key not in self.tasks:
                self.tasks[key] = asyncio.create_task(self.request(item))
        self.wanted = wanted

    async def close(self):
        tasks = list(set(self.tasks.values()) | self.retired)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


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
                    worker.replace(json.loads(line))
                except (ValueError, TypeError, UnicodeError):
                    # A protocol failure settles the current batch. It cannot
                    # silently keep requests alive or retry indefinitely.
                    await worker.close()
                    worker.replace([])
                    emit(dict(event='protocol-error', code='invalid-request', reason='Invalid image request message'))
    finally:
        await worker.close()
        transport.close()
