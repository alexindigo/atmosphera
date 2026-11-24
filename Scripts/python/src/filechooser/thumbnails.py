"""Compatible video-thumbnail entry point backed by the shared image worker.

Video retains ffprobe duration/10-percent seeking and freedesktop cache names.
Source, cache validation, bounded concurrency and decoder lifetime have one
implementation in images; image requests never inherit this video seek policy.
"""
import asyncio
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from images.cache import Cache
from images.png import (PNG, BUCKETS, LIMIT, bucket, canonical_uri, cache_name,
                        chunk, png_chunks, metadata, with_metadata, empty_png,
                        atomic_write)
from images.worker import Worker, serve


if __name__ == '__main__':
    asyncio.run(serve())
