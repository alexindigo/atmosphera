"""Private handoff from a held worker job to the shell's mpvqml producer."""
import asyncio
from itertools import count

from .process import CommandError


class VideoFrames:
    def __init__(self, emit):
        self.emit = emit
        self.sequence = count(1)
        self.pending = {}

    async def capture(self, source, size, destination):
        ticket = str(next(self.sequence))
        reply = asyncio.get_running_loop().create_future()
        self.pending[ticket] = reply
        try:
            self.emit(dict(event='video-frame-request', job=ticket, path=str(source), source=source.as_uri(),
                           width=size, height=size, destination=destination.as_uri()))
            code = await reply
            if code:
                raise CommandError(code, 'The video frame producer could not capture a frame')
        except asyncio.CancelledError:
            self.emit(dict(event='video-frame-cancel', job=ticket))
            raise
        finally:
            del self.pending[ticket]

    def result(self, message):
        job, code = message.get('job'), message.get('code')
        if (set(message) != {'command', 'job', 'code'} or not isinstance(job, str)
                or not isinstance(code, str) or len(code) > 64):
            raise ValueError('Invalid video frame reply')
        if (reply := self.pending.get(job)) is not None and not reply.done():
            reply.set_result(code)
