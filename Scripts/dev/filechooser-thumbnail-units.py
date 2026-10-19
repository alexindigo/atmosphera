#!/usr/bin/env python3
"""Cache and cancellation contracts; execute only in the assigned guest."""
import argparse
import asyncio
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

from filechooser_regression import ROOT, guest

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--source", type=Path, required=True)
p.add_argument("--label", required=True)
a = p.parse_args()
guest()
source = a.source.resolve()
assert source.is_relative_to(ROOT / "sources")
output = ROOT / "evidence" / a.label
assert not output.exists()
output.mkdir()
spec = importlib.util.spec_from_file_location("thumbnails", source / "Scripts/python/src/filechooser/thumbnails.py")
thumb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(thumb)
video = output / "A space résumé.mp4"
subprocess.run(["timeout", "15", "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=160x90:rate=8:duration=1", "-c:v", "libx264", "-threads", "1", str(video)], check=True, timeout=20)


class CacheTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder = output / self._testMethodName
        self.folder.mkdir()
        self.file = self.folder / video.name
        self.file.write_bytes(video.read_bytes())
        self.events = []
        self.cache = thumb.Cache(self.folder / "cache/thumbnails", "test", emit=self.events.append)
        self.uri = thumb.canonical_uri(self.file)
        self.target = self.cache.root / "normal" / thumb.cache_name(self.uri)

    async def test_uri_and_md5(self):
        self.assertEqual(thumb.canonical_uri("/home/jens/photos/me.png"), "file:///home/jens/photos/me.png")
        self.assertEqual(thumb.cache_name("file:///home/jens/photos/me.png"), "c6ee772d9e49320e97ec29a7eb5b1697.png")
        self.assertTrue(self.uri.endswith("A%20space%20r%C3%A9sum%C3%A9.mp4"))
        self.assertEqual(thumb.cache_name(self.uri), hashlib.md5(self.uri.encode()).hexdigest() + ".png")
        self.assertEqual(thumb.canonical_uri(self.folder / "x/../" / video.name), self.uri)
        link = self.folder / "alias.mp4"
        link.symlink_to(self.file)
        self.assertNotEqual(thumb.canonical_uri(link), self.uri)

    async def test_bucket_and_dpr(self):
        self.assertEqual([thumb.bucket(n)[1] for n in (1, 128, 129, 256, 257, 512, 513, 1024, 2048)],
                         ["normal", "normal", "large", "large", "x-large", "x-large", "xx-large", "xx-large", "xx-large"])
        result = await self.cache.get(str(self.file), 144 * 2)
        self.assertIn("/x-large/", result["url"])

    async def test_generated_then_cache_hit(self):
        result = await self.cache.get(str(self.file), 128)
        self.assertEqual(result["status"], "generated")
        data = self.target.read_bytes()
        self.assertEqual(thumb.metadata(data)["Thumb::URI"], self.uri)
        header = next(content for kind, content in thumb.png_chunks(data) if kind == b"IHDR")
        self.assertEqual(header[8:], bytes([8, 6, 0, 0, 0]))
        self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "hit")
        self.assertEqual(len(self.events), 1)

    async def test_other_app_fixture_used_as_is(self):
        self.target.parent.mkdir(parents=True)
        # Independently authored, minimal standard fixture: no optional keys.
        foreign = thumb.PNG + thumb.chunk(b"IHDR", thumb.struct.pack("!IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
        foreign += thumb.chunk(b"tEXt", b"Thumb::URI\0" + self.uri.encode("ascii"))
        foreign += thumb.chunk(b"tEXt", b"Thumb::MTime\0" + str(int(self.file.stat().st_mtime)).encode())
        foreign += thumb.chunk(b"tEXt", b"Software\0Another app")
        foreign += thumb.chunk(b"IDAT", thumb.zlib.compress(b"\0\0\0\0\0")) + thumb.chunk(b"IEND", b"")
        self.target.write_bytes(foreign)
        self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "hit")
        self.assertEqual(self.target.read_bytes(), foreign)
        self.assertEqual(self.events, [])

    async def test_stale_mtime_in_both_directions(self):
        await self.cache.get(str(self.file), 128)
        for delta in (-100, 200):
            stamp = int(self.file.stat().st_mtime) + delta
            os.utime(self.file, (stamp, stamp))
            self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "generated")
        self.assertEqual(len(self.events), 3)

    async def test_uri_and_optional_size_must_match(self):
        await self.cache.get(str(self.file), 128)
        for changes in ({"Thumb::URI": "file:///wrong"}, {"Thumb::Size": "1"}):
            attributes = {**thumb.metadata(self.target.read_bytes()), **changes}
            self.target.write_bytes(thumb.with_metadata(thumb.empty_png(), attributes))
            self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "generated")

    async def test_failure_until_mtime_changes(self):
        self.file.write_bytes(b"corrupt video")
        self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "failed")
        failure = self.cache.failure_dir / self.target.name
        self.assertTrue(failure.is_file())
        self.assertEqual(thumb.metadata(failure.read_bytes())["Thumb::MTime"], str(int(self.file.stat().st_mtime)))
        async def unexpected(*args):
            self.fail("unchanged failure retried")
        with patch.object(self.cache, "frame", unexpected):
            self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "failure-hit")
        stamp = int(self.file.stat().st_mtime) + 2
        self.file.write_bytes(video.read_bytes())
        os.utime(self.file, (stamp, stamp))
        self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "generated")

    async def test_atomic_write_and_permissions(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"previous complete file")
        replace = os.replace
        calls = []
        def observe(src, dst):
            calls.append((str(src), str(dst)))
            self.assertEqual(Path(src).parent, self.target.parent)
            self.assertEqual(self.target.read_bytes(), b"previous complete file")
            self.assertEqual(Path(src).stat().st_mode & 0o777, 0o600)
            self.assertEqual(thumb.metadata(Path(src).read_bytes())["Thumb::URI"], self.uri)
            replace(src, dst)
        with patch.object(thumb.os, "replace", observe):
            await self.cache.get(str(self.file), 128)
        self.assertEqual(len(calls), 1)
        for folder in (self.cache.root, self.target.parent):
            self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.target.parent.glob(".atmosphera-*")), [])

    async def test_timeout_reaps_decoder_and_records_failure(self):
        marker = self.folder / "pid"
        async def hanging(*args):
            return await self.cache.command([sys.executable, "-c", "import os,time,pathlib,sys; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)", str(marker)])
        self.cache.timeout = .3
        with patch.object(self.cache, "frame", hanging):
            self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "failed")
        self.assertFalse(Path("/proc" + "/" + marker.read_text()).exists())

    async def test_dropped_request_cancels_and_never_records_failure(self):
        marker = self.folder / "pid"
        async def hanging(*args):
            return await self.cache.command([sys.executable, "-c", "import os,time,pathlib,sys; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)", str(marker)])
        worker = thumb.Worker(self.cache, self.events.append)
        with patch.object(self.cache, "frame", hanging):
            worker.replace([{"path": str(self.file), "pixels": 128, "stamp": "one"}])
            for _ in range(100):
                if marker.exists():
                    break
                await asyncio.sleep(.01)
            self.assertTrue(marker.exists())
            task = worker.tasks[str(self.file)]
            worker.replace([])
            await asyncio.gather(task, return_exceptions=True)
            await worker.close()
        self.assertFalse(Path("/proc" + "/" + marker.read_text()).exists())
        self.assertFalse(self.target.exists())
        self.assertFalse((self.cache.failure_dir / self.target.name).exists())
        self.assertTrue(any(e.get("event") == "cancelled" for e in self.events))

    async def test_cache_and_symlink_never_thumbnailed(self):
        self.cache.root.mkdir(parents=True)
        inside = self.cache.root / "nested.mp4"
        inside.write_bytes(video.read_bytes())
        link = self.folder / "link.mp4"
        link.symlink_to(inside)
        for path in (inside, link):
            self.assertEqual((await self.cache.get(str(path), 128))["status"], "excluded")
        self.assertEqual(self.events, [])

    async def test_two_slots_and_queued_cancellation(self):
        entered = []
        gate = asyncio.Event()
        async def slow_frame(path, size):
            entered.append(path.name)
            await gate.wait()
            return thumb.empty_png()
        files = [self.folder / f"video{i}.mp4" for i in range(3)]
        for path in files:
            path.write_bytes(video.read_bytes())
        items = [{"path": str(path), "pixels": 128, "stamp": "one"} for path in files]
        worker = thumb.Worker(self.cache, self.events.append)
        with patch.object(self.cache, "frame", slow_frame):
            worker.replace(items)
            for _ in range(100):
                if len(entered) == 2:
                    break
                await asyncio.sleep(.01)
            self.assertEqual(len(entered), 2)
            worker.replace(items[:2])
            gate.set()
            await asyncio.gather(*worker.tasks.values())
            await worker.close()
        self.assertNotIn(files[2].name, entered)
        self.assertFalse((self.cache.root / "normal" / thumb.cache_name(thumb.canonical_uri(files[2]))).exists())

    async def test_unreadable_and_fifo_leave_no_failure(self):
        self.file.chmod(0)
        self.assertEqual((await self.cache.get(str(self.file), 128))["status"], "unreadable")
        fifo = self.folder / "fifo.mp4"
        os.mkfifo(fifo)
        self.assertEqual((await self.cache.get(str(fifo), 128))["status"], "unreadable")
        self.assertFalse(self.cache.failure_dir.exists())


suite = unittest.defaultTestLoader.loadTestsFromTestCase(CacheTests)
with (output / "run.log").open("w") as log:
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
receipt = {"passed": result.wasSuccessful(), "cases": result.testsRun, "failures": [(str(t), e) for t, e in result.failures + result.errors]}
runtime = ROOT / "runtime" / a.label
assert not runtime.exists()
runtime.mkdir()
shell = runtime / "shell"
shutil.copytree(source, shell, symlinks=True)
probe = shell / "thumbnail-units.qml"
probe.write_text((source / "Scripts/dev/fixtures/filechooser-thumbnail-units.qml").read_text())
fixtures = runtime / "fixtures"
fixtures.mkdir()
(fixtures / video.name).write_bytes(video.read_bytes())
(fixtures / "Corrupt.mp4").write_bytes(b"corrupt video")
(fixtures / "Hanging.mp4").write_bytes(video.read_bytes())
shim = runtime / "bin"
shim.mkdir()
marker = runtime / "hanging-pid"
(shim / "ffprobe").write_text('#!/usr/bin/python3\nimport os,sys,time\nfrom pathlib import Path\n'
                             f'if sys.argv[-1].endswith("Hanging.mp4"):\n Path({str(marker)!r}).write_text(str(os.getpid()))\n time.sleep(30)\n'
                             'else:\n os.execv("/usr/bin/ffprobe", ["ffprobe", *sys.argv[1:]])\n')
(shim / "ffprobe").chmod(0o755)
profile = runtime / "profile"
for directory in ("config", "cache", "state", "tmp"):
    (profile / directory).mkdir(parents=True)
env = dict(os.environ, TMPDIR=str(profile / "tmp"), XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1",
           XDG_CACHE_HOME=str(profile / "cache"), ATMOSPHERA_CACHE_DIR=str(profile / "cache") + "/",
           ATMOSPHERA_CONFIG_DIR=str(profile / "config") + "/", ATMOSPHERA_STATE_DIR=str(profile / "state") + "/",
           ATMOSPHERA_SETTINGS_FILE=str(profile / "config/settings.json"), FILECHOOSER_THUMBNAIL_ROOT=str(fixtures),
           PATH=str(shim) + ":" + os.environ["PATH"])
process = subprocess.run(["timeout", "35", "dbus-run-session", "--", "qs", "-p", str(probe)],
                         cwd=shell, env=env, capture_output=True, text=True, timeout=40)
log = process.stdout + process.stderr
(output / "qml.log").write_text(log)
rows = [json.loads(line.split("THUMBNAIL_QML|", 1)[1]) for line in log.splitlines() if "THUMBNAIL_QML|" in line]
receipt["qml"] = {"exit": process.returncode, "rows": rows, "errors": [line for line in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load|Unable to assign", line)]}
receipt["qml"]["cancelled_child_reaped"] = marker.exists() and not Path("/proc" + "/" + marker.read_text()).exists()
receipt["passed"] = (receipt["passed"] and process.returncode == 0 and any(row.get("complete") for row in rows)
                     and all(row.get("pass", True) and row.get("failures", 0) == 0 for row in rows)
                     and not receipt["qml"]["errors"] and receipt["qml"]["cancelled_child_reaped"])
(output / "result.json").write_text(json.dumps(receipt, indent=2))
print(json.dumps(receipt, indent=2))
sys.exit(not receipt["passed"])
