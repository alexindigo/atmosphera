"""Download HTTP(S) source bytes inside an owned cancellable process."""
import json
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
            if declared is not None and int(declared) > budget:
                raise SourceTooLarge('Image source is too large')
            with target.open('xb') as output:
                created = True
                count = 0
                while block := response.read(min(128 * 1024, budget - count + 1)):
                    count += len(block)
                    if count > budget:
                        raise SourceTooLarge('Image source is too large')
                    output.write(block)
    except BaseException:
        if created:
            target.unlink(missing_ok=True)
        raise


def hold(source, parent, *, shell_pid):
    """Keep a private download available only while the caller holds stdin."""
    from .limits import source_byte_budget

    def terminated(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminated)
    stdin = select.poll()
    stdin.register(sys.stdin, select.POLLHUP)
    with tempfile.TemporaryDirectory(prefix='image-source-', dir=parent) as work:
        input_file = Path(work) / 'source'
        # The lease, not the network reader, owns the directory. A blocked
        # response or lookup cannot prevent it from observing the caller's EOF.
        with subprocess.Popen([sys.executable, '-B', '-m', 'images.download', source,
                               str(input_file), str(source_byte_budget())], stdin=subprocess.DEVNULL) as transfer:
            try:
                deadline = time.monotonic() + 30
                while (code := transfer.poll()) is None:
                    if stdin.poll(50):
                        return
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Image download deadline exceeded')
            finally:
                if transfer.poll() is None:
                    transfer.kill()
            if code:
                raise SystemExit(code if code > 0 else 1)
        print(json.dumps({'source': input_file.as_uri()}), flush=True)
        # No request data accepted here: closing the captured pipe retires
        # the snapshot even if the QML item or application has shut down.
        sys.stdin.buffer.read(1)


def main():
    if sys.argv[1] == '--hold':
        from .lease import run
        run(hold, *sys.argv[2:])
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
