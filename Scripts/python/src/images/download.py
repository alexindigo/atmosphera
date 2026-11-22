"""Download HTTP(S) source bytes inside an owned cancellable process."""
from pathlib import Path
import sys
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def main():
    source, target = sys.argv[1:]
    if urlsplit(source).scheme.lower() not in ('http', 'https'):
        raise ValueError('Only HTTP(S) downloads are supported')
    with urlopen(Request(source, headers={'User-Agent': 'Atmosphera image source'}), timeout=10) as response:
        if urlsplit(response.geturl()).scheme.lower() not in ('http', 'https') or not 200 <= response.status < 300:
            raise ValueError('Image download failed')
        with Path(target).open('xb') as output:
            while block := response.read(128 * 1024):
                output.write(block)


if __name__ == '__main__':
    main()
