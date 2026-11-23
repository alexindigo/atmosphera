"""Download HTTP(S) source bytes inside an owned cancellable process."""
from pathlib import Path
import sys
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


def main():
    source, target, budget = sys.argv[1:]
    budget = int(budget)
    if budget <= 0:
        raise ValueError('A positive source-byte budget is required')
    if urlsplit(source).scheme.lower() not in ('http', 'https'):
        raise ValueError('Only HTTP(S) downloads are supported')
    target = Path(target)
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


if __name__ == '__main__':
    try:
        main()
    except SourceTooLarge:
        raise SystemExit(SOURCE_TOO_LARGE_EXIT)
