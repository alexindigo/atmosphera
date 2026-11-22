"""Async facade for lifetime-bound, disk-streaming decoder commands."""
import asyncio
import json
from pathlib import Path
import sys


class CommandError(Exception):
    def __init__(self, code, reason):
        super().__init__(reason)
        self.code = code


async def command(argv, directory, timeout, *, name='command', emit=lambda event: None):
    paths = {key: str(Path(directory) / (name + '.' + suffix))
             for key, suffix in (('stdout', 'stdout'), ('stderr', 'stderr'), ('identity', 'child.json'), ('result', 'result.json'))}
    spec = dict(paths, argv=list(map(str, argv)), timeout=timeout)
    watcher = await asyncio.create_subprocess_exec(sys.executable, '-B', str(Path(__file__).with_name('owned_command.py')),
                                                    json.dumps(spec), stdin=asyncio.subprocess.PIPE,
                                                    stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
    emit(dict(event='command', argv=spec['argv'], watcher=watcher.pid, files=paths))
    try:
        await watcher.wait()
    finally:
        # Closing the exact owner's control pipe joins its watcher/group. Never
        # kill only the watcher and strand ImageMagick's delegate grandchildren.
        watcher.stdin.close()
        await watcher.wait()
    result_path = Path(paths['result'])
    if watcher.returncode or not result_path.is_file():
        raise CommandError('decoder-failed', 'Decoder supervisor failed')
    result = json.loads(result_path.read_text())
    emit(dict(event='command-result', **result, files=paths))
    if result['timeout']:
        raise CommandError('timeout', 'Image decoding timed out')
    if result['cancelled']:
        raise asyncio.CancelledError
    if result['exit']:
        raise CommandError('decoder-failed', 'Decoder could not read this image')
    return Path(paths['stdout'])
