"""Video-only client of the freedesktop Thumbnail Managing Standard.

One JSON-lines worker per picker. Each input replaces its visible interests;
removed interests cancel queued and running decoders. Only two decoders run at
once. Cache IO and decoding never run in the QML process.
"""

import asyncio
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import stat
import struct
import sys
import tempfile
import zlib

PNG = b"\x89PNG\r\n\x1a\n"
BUCKETS = ((128, "normal"), (256, "large"), (512, "x-large"), (1024, "xx-large"))
LIMIT = 16 * 1024 * 1024


def bucket(pixels):
    return next((pair for pair in BUCKETS if pair[0] >= pixels), BUCKETS[-1])


def canonical_uri(path):
    # Normalize the absolute path, not the symlink target: other applications
    # key the cache by the URI the user opened, too.
    return Path(os.path.abspath(path)).as_uri()


def cache_name(uri):
    return hashlib.md5(uri.encode("utf-8"), usedforsecurity=False).hexdigest() + ".png"


def chunk(kind, data):
    return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))


def png_chunks(data):
    if not data.startswith(PNG) or len(data) > LIMIT:
        raise ValueError("Invalid PNG")
    offset = 8
    kinds = []
    while offset + 12 <= len(data):
        length = struct.unpack_from("!I", data, offset)[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("Truncated PNG")
        kind, content = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        if struct.unpack_from("!I", data, end - 4)[0] != zlib.crc32(kind + content):
            raise ValueError("Invalid PNG CRC")
        kinds.append(kind)
        yield kind, content
        offset = end
        if kind == b"IEND":
            if kinds[0] != b"IHDR" or b"IDAT" not in kinds or offset != len(data):
                raise ValueError("Invalid PNG structure")
            return
    raise ValueError("Missing PNG end")


def metadata(data):
    return {content.split(b"\0", 1)[0].decode("latin-1"): content.split(b"\0", 1)[1].decode("latin-1")
            for kind, content in png_chunks(data) if kind == b"tEXt" and b"\0" in content}


def with_metadata(data, attributes):
    parts = list(png_chunks(data))
    return PNG + b"".join(chunk(kind, content) for kind, content in parts[:-1]) + b"".join(
        chunk(b"tEXt", key.encode("latin-1") + b"\0" + value.encode("latin-1"))
        for key, value in attributes.items()) + chunk(b"IEND", b"")


def empty_png():
    return PNG + chunk(b"IHDR", struct.pack("!IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\0\0\0\0\0")) + chunk(b"IEND", b"")


def atomic_write(path, data, root):
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder = root
    folder.chmod(0o700)
    for part in path.parent.relative_to(root).parts:
        folder = folder / part
        folder.mkdir(mode=0o700, exist_ok=True)
        folder.chmod(0o700)
    fd, temporary = tempfile.mkstemp(prefix=".atmosphera-", suffix=".png", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


class Cache:
    def __init__(self, root=None, version=None, timeout=8, emit=lambda event: None):
        self.root = Path(root or (Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "thumbnails"))
        if version is None:
            version = (Path(__file__).resolve().parents[4] / "VERSION").read_text().strip()
        self.failure_dir = self.root / "fail" / ("atmosphera-" + version.replace("/", "_"))
        self.timeout, self.emit = timeout, emit

    def valid(self, path, uri, info):
        try:
            with path.open("rb") as stream:
                values = metadata(stream.read(LIMIT + 1))
            return (values.get("Thumb::URI") == uri and values.get("Thumb::MTime") == str(int(info.st_mtime))
                    and ("Thumb::Size" not in values or values["Thumb::Size"] == str(info.st_size)))
        except (OSError, ValueError, UnicodeError):
            return False

    async def command(self, argv):
        process = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            output, _ = await process.communicate()
            if process.returncode or len(output) > LIMIT:
                raise ValueError("Decoder failed")
            return output
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()

    async def frame(self, path, size):
        duration = json.loads(await self.command(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)]))
        seconds = float(duration.get("format", {}).get("duration", 0))
        seek = seconds * .1 if math.isfinite(seconds) and seconds >= 1 else 0
        self.emit({"event": "ffmpeg", "path": str(path)})
        return await self.command(["ffmpeg", "-nostdin", "-v", "error", "-threads", "1", "-ss", str(seek), "-i", str(path),
                                   "-frames:v", "1", "-vf", f"scale={size}:{size}:force_original_aspect_ratio=decrease",
                                   "-threads", "1", "-pix_fmt", "rgba", "-f", "image2pipe", "-c:v", "png", "pipe:1"])

    async def get(self, name, pixels):
        path = Path(os.path.abspath(name))
        # Resolve only for the containment check, so symlinks cannot recurse
        # into the cache. Reject FIFOs/devices before opening anything.
        if path.resolve().is_relative_to(self.root.resolve()):
            return {"url": "", "status": "excluded"}
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or not os.access(path, os.R_OK):
            return {"url": "", "status": "unreadable"}
        uri = canonical_uri(path)
        size, directory = bucket(pixels)
        target = self.root / directory / cache_name(uri)
        failure = self.failure_dir / target.name
        if self.valid(target, uri, info):
            return {"url": target.as_uri(), "status": "hit"}
        if self.valid(failure, uri, info):
            return {"url": "", "status": "failure-hit"}
        attributes = {"Thumb::URI": uri, "Thumb::MTime": str(int(info.st_mtime)), "Thumb::Size": str(info.st_size), "Software": "Atmosphera"}
        try:
            data = with_metadata(await asyncio.wait_for(self.frame(path, size), self.timeout), attributes)
            success = True
        except (ValueError, OSError, asyncio.TimeoutError):
            data, success = with_metadata(empty_png(), attributes), False
        # Do not publish a frame from a file replaced during decoding.
        after = path.stat()
        if (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            return {"url": "", "status": "changed"}
        atomic_write(target if success else failure, data, self.root)
        return {"url": target.as_uri() if success else "", "status": "generated" if success else "failed"}


class Worker:
    def __init__(self, cache, emit):
        self.cache, self.emit = cache, emit
        self.tasks, self.wanted = {}, {}
        self.retired = set()
        self.slots = asyncio.Semaphore(2)

    async def request(self, item):
        path = item["path"]
        try:
            async with self.slots:
                result = await self.cache.get(path, item["pixels"])
            self.emit({"path": path, "stamp": item.get("stamp"), "pixels": item["pixels"], **result})
        except asyncio.CancelledError:
            self.emit({"event": "cancelled", "path": path})
            raise
        except (OSError, ValueError):
            self.emit({"path": path, "stamp": item.get("stamp"), "url": "", "status": "unavailable"})

    def replace(self, items):
        wanted = {item["path"]: item for item in items}
        for path, task in self.tasks.items():
            if wanted.get(path) != self.wanted.get(path):
                task.cancel()
                self.retired.add(task)
                task.add_done_callback(self.retired.discard)
        self.tasks = {path: task for path, task in self.tasks.items() if wanted.get(path) == self.wanted.get(path)}
        for path, item in wanted.items():
            if path not in self.tasks:
                self.tasks[path] = asyncio.create_task(self.request(item))
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
    # StreamReader handles partial lines without blocking the event loop while
    # decoders run; EOF is the picker lifetime boundary.
    reader = asyncio.StreamReader(limit=1024 * 1024)
    transport, _ = await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, reader.feed_eof)
    emit({"event": "ready"})
    try:
        while line := await reader.readline():
            worker.replace(json.loads(line))
    finally:
        await worker.close()
        transport.close()


if __name__ == "__main__":
    asyncio.run(serve())
