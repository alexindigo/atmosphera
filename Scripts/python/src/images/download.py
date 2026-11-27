"""Shared, stdin-owned HTTP(S) snapshot acquisition."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

SOURCE_TOO_LARGE_EXIT = 3
TRANSFER_SLOTS = 2
QUEUE_SIZE = 32
TRANSFER_IDLE_LIMIT = 30


class SourceTooLarge(ValueError):
    pass


class HttpRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        if urlsplit(newurl).scheme.lower() not in ('http', 'https'):
            raise ValueError('Only HTTP(S) image redirects are supported')
        return super().redirect_request(request, response, code, message, headers, newurl)


def download(source, target, budget):
    if budget <= 0:
        raise ValueError('A positive source-byte budget is required')
    if urlsplit(source).scheme.lower() not in ('http', 'https'):
        raise ValueError('Only HTTP(S) downloads are supported')
    created = False
    try:
        with build_opener(HttpRedirects()).open(Request(source, headers={'User-Agent': 'Atmosphera image source'}), timeout=10) as response:
            if urlsplit(response.geturl()).scheme.lower() not in ('http', 'https') or not 200 <= response.status < 300:
                raise ValueError('Image download failed')
            declared = response.headers.get('Content-Length')
            declared = int(declared) if declared is not None else None
            if declared is not None and declared > budget:
                raise SourceTooLarge('Image source is too large')
            with target.open('xb', buffering=0) as output:
                created = True
                count = 0
                # read1 returns available bytes instead of waiting to fill a
                # chunk. The owner can observe progress even on a slow link.
                while block := response.read1(min(128 * 1024, budget - count + 1)):
                    count += len(block)
                    if count > budget:
                        raise SourceTooLarge('Image source is too large')
                    output.write(block)
                if declared is not None and count != declared:
                    raise OSError('Image download ended before the complete response')
    except BaseException:
        if created:
            target.unlink(missing_ok=True)
        raise


def serve(parent, *, shell_pid):
    """Own all partial and leased files until release or shell EOF."""
    from .limits import source_byte_budget

    def terminated(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminated)
    fd = sys.stdin.fileno()
    pipe = select.poll()
    pipe.register(fd, select.POLLIN | select.POLLHUP)
    queued, running, ready = {}, {}, {}
    budget = source_byte_budget()

    def reply(ticket, **result):
        print(json.dumps(dict(id=ticket, **result)), flush=True)

    def release(ticket):
        queued.pop(ticket, None)
        request = running.pop(ticket, None)
        if request:
            transfer, path, _, _ = request
            if transfer.poll() is None:
                transfer.kill()
            transfer.wait()
            path.unlink(missing_ok=True)
        path = ready.pop(ticket, None)
        if path:
            path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory(prefix='image-source-', dir=parent) as work:
        buffer = bytearray()
        try:
            while True:
                readable = pipe.poll(50 if running else -1)
                if readable:
                    # EOF is also our cancellation transport when QProcess's
                    # supervisor is destroyed. Never start another transfer.
                    if readable[0][1] & select.POLLHUP:
                        return
                    block = os.read(fd, 65536)
                    if not block:
                        return
                    buffer.extend(block)
                    while (newline := buffer.find(b'\n')) >= 0:
                        packet = json.loads(buffer[:newline])
                        del buffer[:newline + 1]
                        ticket = packet['id']
                        if type(ticket) is not int or ticket <= 0:
                            continue
                        if packet['action'] == 'release':
                            release(ticket)
                        elif packet['action'] == 'get' and ticket not in queued and ticket not in running and ticket not in ready:
                            if len(queued) + len(running) >= QUEUE_SIZE + TRANSFER_SLOTS:
                                reply(ticket, code='download-busy', reason='The image download queue is full')
                            else:
                                queued[ticket] = packet['url']
                now = time.monotonic()
                for ticket, (transfer, path, size, last_progress) in list(running.items()):
                    code = transfer.poll()
                    if code is None:
                        try:
                            current_size = path.stat().st_size
                        except FileNotFoundError:
                            current_size = 0
                        if current_size > size:
                            running[ticket] = transfer, path, current_size, now
                        if current_size > size or now - last_progress < TRANSFER_IDLE_LIMIT:
                            continue
                    if code == 0:
                        del running[ticket]
                        ready[ticket] = path
                        reply(ticket, source=path.as_uri())
                    else:
                        release(ticket)
                        if code == SOURCE_TOO_LARGE_EXIT:
                            reply(ticket, code='source-too-large', reason='The image download exceeded the byte limit')
                        else:
                            reply(ticket, code='download-failed', reason='Could not download the image')
                while queued and len(running) < TRANSFER_SLOTS:
                    ticket = next(iter(queued))
                    source = queued.pop(ticket)
                    path = Path(work) / str(ticket)
                    try:
                        transfer = subprocess.Popen([sys.executable, '-B', '-m', 'images.download', source,
                                                     str(path), str(budget)], stdin=subprocess.DEVNULL,
                                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except (OSError, ValueError):
                        reply(ticket, code='download-failed', reason='Could not start the image download')
                    else:
                        running[ticket] = transfer, path, 0, time.monotonic()
        finally:
            for ticket in list(running):
                release(ticket)


def main():
    if sys.argv[1] == '--serve':
        from .lease import run
        run(serve, *sys.argv[2:])
    else:
        source, target, budget = sys.argv[1:]
        download(source, Path(target), int(budget))


if __name__ == '__main__':
    try:
        main()
    except SourceTooLarge:
        raise SystemExit(SOURCE_TOO_LARGE_EXIT)
    except (OSError, ValueError):
        # URLs can contain credentials or query tokens; never log them.
        raise SystemExit(1)
