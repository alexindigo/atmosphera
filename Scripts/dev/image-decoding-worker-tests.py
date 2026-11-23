#!/usr/bin/env python3
"""Independent source/cache/decoder lifetime tests; execute in an owned VM."""
import argparse
import asyncio
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import time
import unittest
from unittest.mock import patch
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading

from guest_profile import activate_profile, profile_argument
from image_decoding_fixtures import COLORS, DELAYS_MS, create_fixtures, pixel, read_png
from image_decoding_evidence import source_manifest
from image_decoding_cache_fixtures import target as foreign_target, thumbnail as foreign_thumbnail, uri as foreign_uri


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path.exists():
            raise ValueError('Fresh canonical guest work/output required')
    if args.source != args.source.resolve() or not args.source.is_relative_to(profile.workspace):
        raise ValueError('Source must be inside the named guest workspace')
    args.work_root.mkdir(mode=0o700)
    args.output.mkdir(mode=0o700)
    inputs = source_manifest(args.source)
    (args.output / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    sys.path.insert(0, str(args.source / 'Scripts/python/src'))
    from images.cache import Cache, iterations
    from images.content import gif
    from images.png import validate, empty_png, PNG, chunk
    from images.process import command, CommandError
    from images.sources import prepare, SourceError
    from images.worker import Worker
    commands = []
    fixtures = args.work_root / 'fixtures'
    create_fixtures(fixtures, commands)
    events = []

    @contextmanager
    def environment(**values):
        previous = os.environ.copy()
        os.environ.update(values)
        try:
            yield
        finally:
            os.environ.clear()
            os.environ.update(previous)

    class Tests(unittest.IsolatedAsyncioTestCase):
        async def asyncSetUp(self):
            self.folder = args.work_root / self._testMethodName
            self.folder.mkdir()
            self.events = []
            self.cache = Cache(self.folder / 'cache', 'tests', emit=self.events.append)

        async def asyncTearDown(self):
            events.append(dict(case=self._testMethodName, events=self.events))

        def request(self, source='Still.webp', **kwargs):
            return dict(source=str(fixtures / source), width=128, height=128, animationIntent='still', fit='contain', **kwargs)

        async def test_malformed_containers_emit_terminal_unavailable(self):
            malformed = {
                'empty-header.png': PNG + chunk(b'IHDR', b'') + chunk(b'IDAT', zlib.compress(b'')) + chunk(b'IEND', b''),
                'short-header.png': PNG + chunk(b'IHDR', b'\0' * 8) + chunk(b'IDAT', zlib.compress(b'')) + chunk(b'IEND', b''),
                'extension.gif': b'GIF89a' + struct.pack('<HH', 1, 1) + b'\0\0\0\x21',
            }
            for name, data in malformed.items():
                path = self.folder / name
                path.write_bytes(data)
                replies = []
                worker = Worker(self.cache, replies.append)
                try:
                    await worker.request(dict(self.request(), source=str(path), id=name))
                    self.assertEqual(len(replies), 1, (name, replies))
                    self.assertEqual(replies[0]['status'], 'unavailable', name)
                    self.assertEqual(replies[0]['url'], '', name)
                finally:
                    await worker.close()

        async def test_png_validation_errors_share_the_value_error_boundary(self):
            header = struct.pack('!IIBBBBB', 1, 1, 8, 6, 0, 0, 0)
            for parts in ((chunk(b'IHDR', b''), chunk(b'IDAT', zlib.compress(b''))),
                          (chunk(b'IHDR', header), chunk(b'IDAT', b'not zlib'))):
                with self.subTest(parts=parts), self.assertRaises(ValueError):
                    validate(PNG + b''.join(parts) + chunk(b'IEND', b''))
            data = zlib.compress(b'\0\x01\x02\x03\xff')
            consecutive = PNG + chunk(b'IHDR', header) + chunk(b'IDAT', data[:3]) + chunk(b'IDAT', data[3:]) + chunk(b'IEND', b'')
            self.assertEqual(validate(consecutive)['width'], 1)
            broken = PNG + chunk(b'IHDR', header) + chunk(b'IDAT', data[:3]) + chunk(b'tEXt', b'k\0v') + chunk(b'IDAT', data[3:]) + chunk(b'IEND', b'')
            with self.assertRaises(ValueError):
                validate(broken)

        async def test_png_inflation_is_bounded_by_declared_pixels(self):
            header = struct.pack('!IIBBBBB', 1, 1, 8, 6, 0, 0, 0)
            bomb = PNG + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(b'\0' * 1048576)) + chunk(b'IEND', b'')
            original = zlib.decompressobj
            calls = []
            class Observed:
                def __init__(self):
                    self.decoder = original()
                def decompress(self, data, max_length=0):
                    calls.append(max_length)
                    return self.decoder.decompress(data, max_length)
                def __getattr__(self, key):
                    return getattr(self.decoder, key)
            with patch('images.png.zlib.decompressobj', Observed), self.assertRaises(ValueError):
                validate(bomb)
            self.assertTrue(calls)
            self.assertTrue(all(0 < limit <= 6 for limit in calls), calls)

        async def test_transient_decoder_failure_is_not_persisted(self):
            calls = []
            async def transient(prepared, request, info):
                calls.append(request)
                error = SourceError('decode-unavailable', 'Temporary decoder failure')
                error.attempts = [dict(decoder='magick', code='timeout'), dict(decoder='ffmpeg', code='decoder-failed')]
                raise error
            with patch.object(self.cache, 'decode', transient):
                for _ in range(2):
                    with self.assertRaises(SourceError):
                        await self.cache.render(self.request())
            self.assertEqual(len(calls), 2)
            self.assertEqual(list((self.cache.private / 'fail').glob('*.json')), [])

        async def test_restarted_worker_restores_held_lease_before_same_read_clear(self):
            result = await self.cache.render(self.request())
            target = Path(result['url'].removeprefix('file://'))
            replies = []
            worker = Worker(self.cache, replies.append)
            try:
                worker.replace([dict(id='held', generation=1, lease=result['url'])])
                reply = worker.clear(dict(id='clear'))
                self.assertEqual(reply['event'], 'cleared')
                self.assertTrue(target.is_file(), reply)
                await asyncio.gather(*worker.tasks.values())
                self.assertIn('held', worker.leases)
            finally:
                await worker.close()
            worker.clear(dict(id='released'))
            self.assertFalse(target.exists())

        async def test_literal_sources_data_and_file_urls(self):
            for name in ('Still.webp', 'Misleading.png', 'bracket[0]: image.webp', '-leading.webp', 'image:literal.webp', 'Space \u6d77\u5cb8.webp'):
                result = await self.cache.render(self.request(name))
                self.assertEqual(result['status'], 'generated')
                self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
            result = await self.cache.render(dict(self.request(), source=(fixtures / 'bracket[0]: image.webp').as_uri()))
            self.assertEqual(result['status'], 'hit')
            encoded = 'data:image/jpeg;base64,' + base64.b64encode((fixtures / 'Still.webp').read_bytes()).decode()
            result = await self.cache.render(dict(self.request(), source=encoded))
            self.assertEqual(result['format'], 'png')

        async def test_formats_and_frame_zero(self):
            for name in ('Still.webp', 'Motion.webp', 'Motion.gif', 'Still.jpg', 'Still.bmp', 'Still.svg', 'Still.tiff', 'Multipage.tiff', 'Still.avif', 'Still.heic'):
                with self.subTest(name=name):
                    result = await self.cache.render(self.request(name))
                    target = Path(result['url'].removeprefix('file://'))
                    self.assertTrue(target.is_file())
                    self.assertEqual(result['frames'], 1)
                    self.assertEqual(result['format'], 'png')
                    self.assertLessEqual(max(abs(a - b) for a, b in zip(pixel(target), COLORS[0])), 8)
                    self.assertEqual(list(target.parent.glob(target.stem + '-*.png')), [])

        async def test_svg_inspection_reads_declaration_without_decoder(self):
            # Icons inspect every resolved SVG; the declared still size must
            # not cost an ImageMagick render per icon.
            variants = {
                'declared.svg': ('<svg xmlns="http://www.w3.org/2000/svg" width="96px" height="64">'
                                 '<rect width="96" height="64" fill="#e62337"/></svg>', (96, 64)),
                'viewbox.svg': ('﻿<?xml version="1.0"?>\n<!-- icon -->\n<svg xmlns="http://www.w3.org/2000/svg" '
                                'width="100%" viewBox="0 0 24 16.5"><rect width="24" height="16" fill="#e62337"/></svg>', (24, 17)),
            }
            for name, (text, size) in variants.items():
                (self.folder / name).write_text(text)
                result = await self.cache.render(dict(self.request(), source=str(self.folder / name), operation='inspect'))
                self.assertEqual((result['status'], result['format'], result['width'], result['height'], result['frames'],
                                  result['animated']), ('inspected', 'svg', *size, 1, False))
            self.assertFalse([event for event in self.events if event.get('event') == 'command'])
            # Unreadable declarations, other roots and compressed SVG still
            # reach the independent decoder's inspection; never a guessed size.
            (self.folder / 'relative.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2em" height="1em">'
                                                     '<rect width="20" height="10" fill="#e62337"/></svg>')
            (self.folder / 'page.svg').write_text('<html><body>not svg</body></html>')
            for name in ('relative.svg', 'page.svg'):
                self.events.clear()
                try:
                    await self.cache.render(dict(self.request(), source=str(self.folder / name), operation='inspect'))
                except (SourceError, CommandError, ValueError):
                    pass
                self.assertTrue([event for event in self.events if event.get('event') == 'command'], name)
            result = await self.cache.render(dict(self.request(), source=str(self.folder / 'declared.svg')))
            self.assertEqual(result['format'], 'png')
            self.assertLessEqual(max(abs(a - b) for a, b in zip(pixel(Path(result['url'].removeprefix('file://'))), COLORS[0])), 8)

        async def test_retained_original_is_exact_and_distinct_from_representation(self):
            directory = self.folder / "wallpapers ' [0] : \u6d77\u5cb8"
            directory.mkdir(mode=0o755)
            result = await self.cache.render(self.request('Motion.webp', operation='retain', destinationDirectory=str(directory)))
            original = Path(result['originalPath'])
            self.assertEqual(original.parent, directory)
            self.assertEqual(original.suffix, '.webp')
            self.assertEqual(original.read_bytes(), (fixtures / 'Motion.webp').read_bytes())
            self.assertNotEqual(original.as_uri(), result['url'])
            self.assertEqual(result['sourceInfo']['frames'], 3)
            self.assertEqual(result['frames'], 1)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o755)
            original.write_bytes(b'bad retained entry')
            again = await self.cache.render(self.request('Motion.webp', operation='retain', destinationDirectory=str(directory)))
            self.assertEqual(again['originalPath'], str(original))
            self.assertEqual(original.read_bytes(), (fixtures / 'Motion.webp').read_bytes())
            self.assertEqual(list(directory.glob('.atmosphera-*')), [])

        async def test_failed_retention_does_not_publish_original(self):
            directory = self.folder / 'wallpapers'
            with self.assertRaises((SourceError, CommandError, ValueError)):
                await self.cache.render(self.request('Corrupt.webp', operation='retain', destinationDirectory=str(directory)))
            self.assertFalse(directory.exists())

        async def test_retention_destination_failure_does_not_poison_decoder_cache(self):
            with self.assertRaises(SourceError):
                await self.cache.render(self.request(operation='retain', destinationDirectory='relative'))
            self.assertEqual(list((self.cache.private / 'fail').glob('*.json')), [])
            result = await self.cache.render(self.request())
            self.assertIn(result['status'], ('generated', 'hit'))

        async def test_animation_preserves_frames_delays_loop_and_alpha(self):
            result = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            target = Path(result['url'].removeprefix('file://'))
            self.assertEqual(result['format'], 'gif')
            self.assertEqual(result['frames'], 3)
            self.assertEqual(result['delaysMs'], DELAYS_MS)
            self.assertEqual(iterations(result), 0)
            self.assertEqual(gif(target.read_bytes())['frames'], 3)
            # Independent FFmpeg decoding reconstructs full GIF frames. Compare
            # disposal-sensitive transparent margins, not just colored centers.
            decoded = self.folder / 'frame-%d.png'
            proc = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', str(target), '-fps_mode', 'passthrough',
                                   '-threads', '1', '-pix_fmt', 'rgba', str(decoded)], capture_output=True, timeout=30)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            images = sorted(self.folder.glob('frame-*.png'))
            self.assertEqual(len(images), 3)
            for index, path in enumerate(images):
                self.assertEqual(pixel(path), list(COLORS[index]))
                for x, y in ((4, 4), (124, 4), (4, 80)):
                    # Output aspect-preserving geometry is 128x85 from 96x64;
                    # derive source coordinates, not repeated magic offsets.
                    width, height, _ = read_png(path)
                    sx, sy = round(x / width * 96), round(y / height * 64)
                    actual = pixel(path, x, y)
                    expected = pixel(fixtures / f'frame-{index}.png', sx, sy)
                    self.assertEqual(actual[3], expected[3], (index, x, y, actual, expected))
            repeated = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            self.assertEqual(repeated['status'], 'hit')

        async def test_still_and_motion_do_not_alias(self):
            still = await self.cache.render(self.request('Motion.webp'))
            moving = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            self.assertNotEqual(still['url'], moving['url'])
            self.assertTrue(still['url'].endswith('.png') and moving['url'].endswith('.gif'))
            still_source = await self.cache.render(self.request('Still.webp'))
            preserve_source = await self.cache.render(dict(self.request('Still.webp'), animationIntent='preserve'))
            self.assertNotEqual(still_source['url'], preserve_source['url'])

        async def test_sixteen_bit_png_source_is_not_restricted_to_output_encoding(self):
            source = self.folder / 'sixteen-bit.png'
            rgba = struct.pack('!HHHH', *[channel * 257 for channel in COLORS[0]])
            source.write_bytes(PNG + chunk(b'IHDR', struct.pack('!IIBBBBB', 1, 1, 16, 6, 0, 0, 0))
                               + chunk(b'IDAT', zlib.compress(b'\0' + rgba)) + chunk(b'IEND', b''))
            result = await self.cache.render(dict(self.request(), source=str(source)))
            self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))

        def thumbnail_request(self, **kwargs):
            return dict(self.request(**kwargs), operation='image-thumbnail')

        async def test_foreign_thumbnail_encodings_are_inputs_not_normalized_outputs(self):
            source = self.folder / "foreign +!() [0] : 海岸.webp"
            source.write_bytes((fixtures / 'Still.webp').read_bytes())
            target = foreign_target(self.cache.root, source)
            target.parent.mkdir(parents=True)
            for depth, interlace, text in ((8, 0, 'tEXt'), (16, 0, 'zTXt'), (8, 1, 'iTXt')):
                with self.subTest(depth=depth, interlace=interlace, text=text):
                    data = foreign_thumbnail(source, depth=depth, interlace=interlace, text=text, size=False)
                    target.write_bytes(data)
                    result = await self.cache.render(dict(self.thumbnail_request(), source=str(source)))
                    self.assertEqual(result['thumbnailOrigin'], 'foreign')
                    self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[1]))
                    self.assertEqual(target.read_bytes(), data)
                    self.assertEqual(result['thumbnailUri'], foreign_uri(source))
            normal = await self.cache.render(dict(self.request(), source=str(source)))
            self.assertEqual(pixel(Path(normal['url'].removeprefix('file://'))), list(COLORS[0]))

        async def test_thumbnail_buckets_hits_corruption_and_metadata_repair(self):
            from images.png import metadata, png_chunks
            source = self.folder / 'source.webp'
            source.write_bytes((fixtures / 'Motion.webp').read_bytes())
            for size, directory in ((64, 'normal'), (144, 'large'), (300, 'x-large'), (700, 'xx-large')):
                result = await self.cache.render(dict(self.thumbnail_request(), source=str(source), width=size, height=size))
                target = foreign_target(self.cache.root, source, directory)
                self.assertTrue(target.is_file())
                self.assertEqual(metadata(target.read_bytes())['Thumb::URI'], foreign_uri(source))
                self.assertEqual(next(data for kind, data in png_chunks(target.read_bytes()) if kind == b'IHDR')[8:], bytes([8, 6, 0, 0, 0]))
                self.assertEqual(result['frames'], 1)
                self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
                again = await self.cache.render(dict(self.thumbnail_request(), source=str(source), width=size, height=size))
                self.assertEqual(again['thumbnailOrigin'], 'foreign')
            target = foreign_target(self.cache.root, source)
            for data in (b'broken PNG', foreign_thumbnail(source, changes={'Thumb::URI': 'file:///wrong'}),
                         foreign_thumbnail(source, changes={'Thumb::Size': '1'})):
                target.write_bytes(data)
                result = await self.cache.render(dict(self.thumbnail_request(), source=str(source)))
                self.assertEqual(result['thumbnailOrigin'], 'generated')
                self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
            moving = await self.cache.render(dict(self.request(), source=str(source), animationIntent='preserve'))
            self.assertEqual(moving['frames'], 3)
            self.assertTrue(moving['url'].endswith('.gif'))

        async def test_thumbnail_source_ns_ctime_backdated_and_open_identity(self):
            source = self.folder / 'replaced.webp'
            source.write_bytes((fixtures / 'frame-0.png').read_bytes())
            request = dict(self.thumbnail_request(), source=str(source))
            await self.cache.render(request)
            original_time = source.stat().st_mtime_ns
            for delta, frame in ((1, 1), (-100000000000, 2), (0, 0)):
                source.write_bytes((fixtures / f'frame-{frame}.png').read_bytes())
                os.utime(source, ns=(original_time + delta, original_time + delta))
                result = await self.cache.render(request)
                self.assertEqual(result['thumbnailOrigin'], 'generated')
                self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[frame]))
            target = foreign_target(self.cache.root, source)
            target.write_bytes(foreign_thumbnail(source))
            decode = self.cache.decode
            async def changing(prepared, spec, info):
                source.write_bytes((fixtures / 'frame-1.png').read_bytes())
                return await decode(prepared, spec, info)
            with patch.object(self.cache, 'decode', changing), self.assertRaises(SourceError) as raised:
                await self.cache.render(dict(request, width=65, height=65))
            self.assertEqual(raised.exception.code, 'source-changed')

        async def test_thumbnail_full_pixel_validation_repairs_foreign_hit(self):
            source = self.folder / 'source.webp'
            source.write_bytes((fixtures / 'Still.webp').read_bytes())
            target = foreign_target(self.cache.root, source)
            target.parent.mkdir(parents=True)
            data = foreign_thumbnail(source)
            # Correct PNG chunks/CRCs and metadata, invalid compressed pixels.
            from images.png import png_chunks
            target.write_bytes(PNG + b''.join(chunk(kind, b'invalid deflate' if kind == b'IDAT' else value)
                                             for kind, value in png_chunks(data)))
            result = await self.cache.render(dict(self.thumbnail_request(), source=str(source)))
            self.assertEqual(result['thumbnailOrigin'], 'generated')
            self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
            self.assertEqual(validate(target.read_bytes())['format'], 'png')

        async def test_thumbnail_cancellation_and_unknown_operations_do_not_publish(self):
            async def held(*_args):
                await asyncio.sleep(30)
            with patch.object(self.cache, 'decode', held):
                task = asyncio.create_task(self.cache.render(self.thumbnail_request()))
                await asyncio.sleep(.1)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            self.assertEqual(list(self.cache.root.glob('normal/*.png')), [])
            self.assertEqual(list((self.cache.private / 'fail').glob('*.json')), [])
            with self.assertRaises(ValueError):
                await self.cache.render(self.request(operation='accidental-new-operation'))

        async def test_thumbnail_negative_capability_and_explicit_retry(self):
            request = self.thumbnail_request()
            async def fail(*_args):
                raise SourceError('decode-unavailable', 'Controlled unavailable delegate')
            with patch.object(self.cache, 'decode', fail):
                with self.assertRaises(SourceError):
                    await self.cache.render(request)
            with patch.object(self.cache, 'decode', fail):
                result = await self.cache.render(request)
                self.assertEqual(result['status'], 'unavailable')
            retried = await self.cache.render(dict(request, retry=True))
            self.assertEqual(retried['thumbnailOrigin'], 'generated')
            fresh_cache = Cache(self.cache.root, 'tests')
            restarted = await fresh_cache.render(request)
            self.assertEqual(restarted['thumbnailOrigin'], 'foreign')

        async def test_thumbnail_unreadable_original_never_uses_or_writes_cache(self):
            source = self.folder / 'unreadable.webp'
            source.write_bytes((fixtures / 'Still.webp').read_bytes())
            target = foreign_target(self.cache.root, source)
            target.parent.mkdir(parents=True)
            data = foreign_thumbnail(source)
            target.write_bytes(data)
            source.chmod(0)
            try:
                with self.assertRaises(SourceError) as raised:
                    await self.cache.render(dict(self.thumbnail_request(), source=str(source)))
                self.assertEqual(raised.exception.code, 'unreadable')
                self.assertEqual(target.read_bytes(), data)
                self.assertEqual(list((self.cache.private / 'fail').glob('*.json')), [])
            finally:
                source.chmod(0o600)

        async def test_thumbnail_foreign_symlink_is_replaced_not_followed(self):
            source = self.folder / 'source.webp'
            source.write_bytes((fixtures / 'Still.webp').read_bytes())
            outside = self.folder / 'untouched.png'
            data = foreign_thumbnail(source)
            outside.write_bytes(data)
            target = foreign_target(self.cache.root, source)
            target.parent.mkdir(parents=True)
            target.symlink_to(outside)
            result = await self.cache.render(dict(self.thumbnail_request(), source=str(source)))
            self.assertEqual(result['thumbnailOrigin'], 'generated')
            self.assertEqual(outside.read_bytes(), data)
            self.assertFalse(target.is_symlink())

        async def test_cache_output_parent_symlink_never_writes_or_chmods_source_directory(self):
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            sentinel = outside / 'original.png'
            sentinel.write_bytes((fixtures / 'frame-1.png').read_bytes())
            self.cache.private.mkdir(parents=True)
            (self.cache.private / 'still').symlink_to(outside, target_is_directory=True)
            try:
                with self.assertRaises(OSError):
                    await self.cache.render(self.request())
                self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
                self.assertEqual(list(outside.iterdir()), [sentinel])
                self.assertEqual(sentinel.read_bytes(), (fixtures / 'frame-1.png').read_bytes())
            finally:
                self.events.append(dict(outsideMode=outside.stat().st_mode & 0o777,
                                        outsideNames=sorted(path.name for path in outside.iterdir())))

        async def test_cache_staging_symlink_never_admits_decoder_work(self):
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            self.cache.private.mkdir(parents=True)
            self.cache.staging.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(OSError):
                await self.cache.render(self.request())
            self.assertFalse(any(row.get('event') == 'command' for row in self.events))
            self.assertEqual(list(outside.iterdir()), [])
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)

        async def test_atomic_cache_parent_swap_keeps_write_bound_and_refuses_publication(self):
            from images.storage import atomic_write
            outside, parent, held = (self.folder / name for name in ('originals', 'cache/normal', 'held-cache'))
            outside.mkdir(mode=0o755)
            parent.mkdir(parents=True)
            sentinel = outside / 'source.png'
            sentinel.write_bytes(b'original source bytes')
            replace = os.replace
            def swap(source, target, **directories):
                parent.rename(held)
                parent.symlink_to(outside, target_is_directory=True)
                return replace(source, target, **directories)
            with patch.object(os, 'replace', swap), self.assertRaises(OSError):
                atomic_write(parent / 'result.png', empty_png(), self.folder / 'cache')
            self.assertEqual(list(outside.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_bytes(), b'original source bytes')
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
            self.assertEqual((held / 'result.png').read_bytes(), empty_png())
            self.assertEqual(list(held.glob('.atmosphera-*')), [])

        async def test_atomic_cache_collision_never_unlinks_another_writer_staging(self):
            from images.storage import atomic_write
            parent = self.folder / 'cache/normal'
            parent.mkdir(parents=True)
            foreign = parent / '.atmosphera-controlled-collision'
            foreign.write_bytes(b'another writer owns these bytes')
            with patch('images.storage.secrets.token_hex', return_value='controlled-collision'), self.assertRaises(FileExistsError):
                atomic_write(parent / 'result.png', empty_png(), self.folder / 'cache')
            self.assertEqual(foreign.read_bytes(), b'another writer owns these bytes')
            self.assertFalse((parent / 'result.png').exists())

        async def test_cache_positive_leaf_symlink_is_replaced_not_borrowed(self):
            result = await self.cache.render(self.request())
            target = Path(result['url'].removeprefix('file://'))
            outside = self.folder / 'user-image.png'
            green = await self.cache.render(self.request('frame-1.png'))
            outside.write_bytes(Path(green['url'].removeprefix('file://')).read_bytes())
            before = outside.read_bytes()
            target.unlink()
            target.symlink_to(outside)
            again = await self.cache.render(self.request())
            self.assertEqual(again['status'], 'generated')
            self.assertFalse(target.is_symlink())
            self.assertEqual(pixel(target), list(COLORS[0]))
            self.assertEqual(outside.read_bytes(), before)

        async def test_cache_positive_parent_symlink_never_borrows_pixels(self):
            result = await self.cache.render(self.request())
            target = Path(result['url'].removeprefix('file://'))
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            green = await self.cache.render(self.request('frame-1.png'))
            sentinel = outside / target.name
            sentinel.write_bytes(Path(green['url'].removeprefix('file://')).read_bytes())
            before = sentinel.read_bytes()
            target.parent.rename(self.folder / 'held-cache')
            target.parent.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(OSError):
                await self.cache.render(self.request())
            self.assertEqual(sentinel.read_bytes(), before)
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
            self.assertEqual(list(outside.iterdir()), [sentinel])

        async def test_cache_negative_leaf_symlink_never_borrows_reason(self):
            async def fail(*_args):
                raise SourceError('decode-unavailable', 'Owned decoder failure')
            with patch.object(self.cache, 'decode', fail), self.assertRaises(SourceError):
                await self.cache.render(self.request())
            target, = (self.cache.private / 'fail').glob('*.json')
            outside = self.folder / 'user-negative.json'
            negative = json.loads(target.read_text())
            negative['reason'] = 'Unrelated private source reason'
            outside.write_text(json.dumps(negative))
            target.unlink()
            target.symlink_to(outside)
            again = await self.cache.render(self.request())
            self.assertEqual(again['status'], 'generated')
            self.assertEqual(pixel(Path(again['url'].removeprefix('file://'))), list(COLORS[0]))
            self.assertEqual(json.loads(outside.read_text()), negative)

        async def test_cache_negative_parent_symlink_never_borrows_reason(self):
            async def fail(*_args):
                raise SourceError('decode-unavailable', 'Owned decoder failure')
            with patch.object(self.cache, 'decode', fail), self.assertRaises(SourceError):
                await self.cache.render(self.request())
            target, = (self.cache.private / 'fail').glob('*.json')
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            sentinel = outside / target.name
            negative = json.loads(target.read_text())
            negative['reason'] = 'Unrelated directory reason'
            sentinel.write_text(json.dumps(negative))
            target.parent.rename(self.folder / 'held-failures')
            target.parent.symlink_to(outside, target_is_directory=True)
            result = await self.cache.render(self.request())
            self.assertEqual(result['status'], 'generated')
            self.assertEqual(json.loads(sentinel.read_text()), negative)
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)

        async def test_foreign_cache_parent_symlink_never_borrows_thumbnail(self):
            source = fixtures / 'Still.webp'
            target = foreign_target(self.cache.root, source)
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            sentinel = outside / target.name
            data = foreign_thumbnail(source)
            sentinel.write_bytes(data)
            self.cache.root.mkdir()
            target.parent.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(OSError):
                await self.cache.render(self.thumbnail_request())
            self.assertEqual(sentinel.read_bytes(), data)
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
            self.assertEqual(list(outside.iterdir()), [sentinel])

        async def test_video_cache_parent_symlink_never_publishes_hit(self):
            source = fixtures / 'Still.webp'
            target = foreign_target(self.cache.root, source)
            outside = self.folder / 'user-originals'
            outside.mkdir(mode=0o755)
            sentinel = outside / target.name
            sentinel.write_bytes(foreign_thumbnail(source))
            self.cache.root.mkdir()
            target.parent.symlink_to(outside, target_is_directory=True)
            # A controlled valid video frame avoids coupling this cache-boundary
            # assertion to ffmpeg's ability to treat a still as a video input.
            async def frame(*_args):
                return empty_png()
            with patch.object(self.cache, 'frame', frame), self.assertRaises(OSError):
                await self.cache.get(str(source), 64)
            self.assertEqual(sentinel.read_bytes(), foreign_thumbnail(source))
            self.assertEqual(outside.stat().st_mode & 0o777, 0o755)

        async def test_cache_async_validation_parent_swap_refuses_old_hit(self):
            result = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            target = Path(result['url'].removeprefix('file://'))
            validate_output = self.cache.validate_output
            replaced = False
            async def swap(path, directory, moving, request):
                nonlocal replaced
                output = await validate_output(path, directory, moving, request)
                if not replaced:
                    replaced = True
                    target.parent.rename(self.folder / 'held-cache')
                    target.parent.mkdir()
                    target.write_bytes(b'replacement must not become a hit')
                return output
            with patch.object(self.cache, 'validate_output', swap):
                again = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            self.assertEqual(again['status'], 'generated')
            self.assertEqual(gif(target.read_bytes())['frames'], 3)
            self.assertTrue(replaced)

        async def test_cache_gif_validation_reads_bound_snapshot_not_replaced_path(self):
            request = dict(self.request('Motion.webp'), animationIntent='preserve')
            result = await self.cache.render(request)
            target = Path(result['url'].removeprefix('file://'))
            original = target.read_bytes()
            validate_output = self.cache.validate_output
            observed = []
            async def replace_leaf(path, directory, moving, spec):
                if not observed:
                    replacement = target.with_suffix('.replacement')
                    replacement.write_bytes(b'not an animation')
                    os.replace(replacement, target)
                    observed.append(dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
                    self.assertEqual(path.read_bytes(), original)
                    self.assertNotEqual(path, target)
                return await validate_output(path, directory, moving, spec)
            with patch.object(self.cache, 'validate_output', replace_leaf):
                again = await self.cache.render(request)
            self.assertEqual(again['status'], 'generated')
            self.assertEqual(gif(target.read_bytes())['frames'], 3)
            self.assertEqual(len(observed), 1)
            self.events.append(dict(cacheValidation=observed))

        async def test_cache_reader_rejects_fifo_without_blocking_or_chmod(self):
            from images.storage import open_file
            parent = self.folder / 'cache-reader'
            parent.mkdir(mode=0o755)
            target = parent / 'fifo.png'
            os.mkfifo(target, 0o600)
            with self.assertRaises(ValueError):
                with open_file(target):
                    self.fail('A FIFO is not a cache image')
            self.assertEqual(parent.stat().st_mode & 0o777, 0o755)
            self.assertTrue(target.stat().st_mode & 0o170000 == 0o010000)

        async def test_user_source_symlink_remains_a_supported_source(self):
            source = self.folder / 'ordinary-user-symlink.webp'
            source.symlink_to(fixtures / 'Still.webp')
            result = await self.cache.render(dict(self.request(), source=str(source)))
            self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
            self.assertTrue(source.is_symlink())

        async def test_thumbnail_independent_processes_publish_complete_freedesktop_png(self):
            workers, identities, replies = [], [], []
            cache = self.folder / 'shared/thumbnails'
            source = fixtures / 'Motion.webp'
            target = foreign_target(cache, source)
            async def receive(process):
                while True:
                    row = json.loads(await asyncio.wait_for(process.stdout.readline(), 8))
                    replies.append(row)
                    if row.get('event') == 'command-result':
                        identities.append({key: row['child'][key] for key in ('pid', 'start', 'uid')})
                    if row.get('status'):
                        return row
            try:
                for number in range(2):
                    process = await asyncio.create_subprocess_exec(sys.executable, '-B', str(args.source / 'Scripts/python/image-worker.py'),
                        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                        env=dict(os.environ, XDG_CACHE_HOME=str(cache.parent)))
                    workers.append(process)
                    identities.append(self.process_identity(process.pid))
                    self.assertEqual(json.loads(await asyncio.wait_for(process.stdout.readline(), 3))['event'], 'ready')
                    process.stdin.write((json.dumps([dict(self.thumbnail_request(), source=str(source),
                                                          id=str(number), generation=number)]) + '\n').encode())
                    await process.stdin.drain()
                pending = [asyncio.create_task(receive(process)) for process in workers]
                observations = []
                while not all(task.done() for task in pending):
                    if target.exists():
                        data = target.read_bytes()
                        validate(data)
                        observations.append(hashlib.sha256(data).hexdigest())
                    await asyncio.sleep(.001)
                results = await asyncio.gather(*pending)
                for result in results:
                    self.assertIn(result['status'], ('generated', 'hit'))
                    self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
                self.assertEqual(pixel(target), list(COLORS[0]))
                observations.append(hashlib.sha256(target.read_bytes()).hexdigest())
                self.assertEqual(set(observations), {hashlib.sha256(target.read_bytes()).hexdigest()})
                for process in workers:
                    process.stdin.close()
                    await asyncio.wait_for(process.wait(), 5)
                    self.assertEqual(process.returncode, 0, (await process.stderr.read()).decode())
                self.assert_processes_retired(identities)
                self.assertEqual(list(cache.rglob('.atmosphera-*')), [])
                self.assertEqual(list((cache / 'atmosphera-representations-v1/staging').iterdir()), [])
                self.events.append(dict(replies=replies, completeObservations=len(observations)))
            finally:
                for process in workers:
                    if process.returncode is None:
                        process.kill()
                        await process.wait()

        async def test_finite_animation_loop_semantics(self):
            for extension in ('webp', 'gif'):
                source = self.folder / ('finite.' + extension)
                made = subprocess.run(['magick', '-delay', '12', str(fixtures / 'frame-0.png'), '-delay', '23',
                                       str(fixtures / 'frame-1.png'), '-delay', '35', str(fixtures / 'frame-2.png'),
                                       '-loop', '3', str(source)], capture_output=True, timeout=30)
                self.assertEqual(made.returncode, 0, made.stderr)
                result = await self.cache.render(dict(self.request(), source=str(source), animationIntent='preserve'))
                self.assertEqual(iterations(result['sourceInfo']), 3)
                self.assertEqual(iterations(result), 3)
                self.assertEqual(result['delaysMs'], DELAYS_MS)

        async def test_http_without_suffix_and_redirect_uses_actual_bytes(self):
            data = (fixtures / 'Still.webp').read_bytes()
            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/redirect':
                        self.send_response(302)
                        self.send_header('Location', '/misleading.jpg')
                        self.end_headers()
                    elif self.path == '/missing':
                        self.send_error(404)
                    else:
                        self.send_response(200)
                        self.send_header('Content-Type', 'image/jpeg')
                        self.send_header('Content-Length', str(len(data)))
                        self.end_headers()
                        self.wfile.write(data)
                def log_message(self, *_args):
                    pass
            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                for endpoint in ('/no-suffix', '/redirect'):
                    result = await self.cache.render(dict(self.request(), source=f'http://127.0.0.1:{server.server_port}' + endpoint))
                    self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
                with self.assertRaises(SourceError) as caught:
                    await self.cache.render(dict(self.request(), source=f'http://127.0.0.1:{server.server_port}/missing'))
                self.assertEqual(caught.exception.code, 'download-failed')
                self.assertFalse(any('http://' in str(row.get('argv', '')) for row in self.events))
            finally:
                server.shutdown()
                server.server_close()
                thread.join()

        async def test_source_replacement_cannot_publish_old_pixels(self):
            source = self.folder / 'replace.webp'
            source.write_bytes((fixtures / 'Still.webp').read_bytes())
            decode = self.cache.decode
            async def replace_then_decode(prepared, request, info):
                source.write_bytes((fixtures / 'frame-1.png').read_bytes())
                return await decode(prepared, request, info)
            with patch.object(self.cache, 'decode', replace_then_decode):
                with self.assertRaises(SourceError) as caught:
                    await self.cache.render(dict(self.request(), source=str(source)))
                self.assertEqual(caught.exception.code, 'source-changed')
            self.assertEqual(list(self.cache.private.glob('still/*')), [])
            self.assertEqual(list(self.cache.private.glob('fail/*')), [])

        async def test_cancelled_render_leaves_no_positive_or_failure_entry(self):
            gate = asyncio.Event()
            entered = asyncio.Event()
            async def held(*_args):
                entered.set()
                await gate.wait()
            with patch.object(self.cache, 'decode', held):
                task = asyncio.create_task(self.cache.render(self.request()))
                await asyncio.wait_for(entered.wait(), 3)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            self.assertEqual(list(self.cache.private.glob('still/*')), [])
            self.assertEqual(list(self.cache.private.glob('fail/*')), [])
            self.assertEqual(list(self.cache.staging.iterdir()), [])

        async def test_positive_cache_revalidates_pixels(self):
            request = self.request()
            first = await self.cache.render(request)
            target = Path(first['url'].removeprefix('file://'))
            self.assertEqual((await self.cache.render(request))['status'], 'hit')
            target.write_bytes(target.read_bytes()[:50])
            self.assertEqual((await self.cache.render(request))['status'], 'generated')
            self.assertEqual(pixel(target), list(COLORS[0]))

        async def test_changed_source_and_revision_separate_cache(self):
            source = self.folder / 'same-name.webp'
            source.write_bytes((fixtures / 'frame-0.png').read_bytes())
            request = dict(self.request(), source=str(source))
            first = await self.cache.render(request)
            before = source.stat()
            source.write_bytes((fixtures / 'frame-1.png').read_bytes())
            os.utime(source, ns=(before.st_atime_ns, before.st_mtime_ns))
            second = await self.cache.render(request)
            self.assertNotEqual(first['url'], second['url'])
            self.assertEqual(pixel(Path(second['url'].removeprefix('file://'))), list(COLORS[1]))
            third = await self.cache.render(dict(request, revision='producer-2'))
            self.assertNotEqual(second['url'], third['url'])

        async def test_orientation_and_cover(self):
            result = await self.cache.render(dict(self.request('Oriented.jpg'), width=96, height=96))
            self.assertEqual((result['width'], result['height']), (64, 96))
            result = await self.cache.render(dict(self.request(), width=100, height=100, fit='cover'))
            self.assertEqual((result['width'], result['height']), (100, 100))

        async def test_cover_and_circle_preserve_source_alpha(self):
            for source in ('frame-0.png', 'Still.webp'):
                for fit in ('cover', 'circle'):
                    with self.subTest(source=source, fit=fit):
                        result = await self.cache.render(dict(self.request(source), width=96, height=64, fit=fit))
                        target = Path(result['url'].removeprefix('file://'))
                        self.assertEqual(pixel(target, 48, 6)[3], 0)
                        self.assertEqual(pixel(target), list(COLORS[0]))

        async def test_representation_schema_does_not_reuse_previous_outputs(self):
            with patch('images.cache.SCHEMA', 1):
                previous = await self.cache.render(self.request())
            current = await self.cache.render(self.request())
            self.assertNotEqual(previous['url'], current['url'])
            self.assertEqual(current['status'], 'generated')
            self.assertTrue(Path(previous['url'].removeprefix('file://')).is_file())

        async def test_zero_exit_without_output_tries_independent_decoder(self):
            shim = self.folder / 'bin'
            shim.mkdir()
            executable = shim / 'magick'
            executable.write_text('#!/bin/sh\nexit 0\n')
            executable.chmod(0o755)
            with environment(PATH=str(shim) + ':' + os.environ['PATH']):
                result = await self.cache.render(self.request())
            self.assertEqual(result['decoder'], 'ffmpeg')
            self.assertEqual(pixel(Path(result['url'].removeprefix('file://'))), list(COLORS[0]))
            self.assertFalse(any('-ss' in row.get('argv', []) for row in self.events))

        async def test_valid_png_with_wrong_dimensions_is_not_success(self):
            shim = self.folder / 'bin'
            shim.mkdir()
            wrong = self.folder / 'wrong.png'
            wrong.write_bytes(empty_png())
            executable = shim / 'magick'
            executable.write_text('#!/usr/bin/python3\nfrom pathlib import Path\nimport sys\n'
                                  f'Path(sys.argv[-1].removeprefix("PNG32:")).write_bytes(Path({str(wrong)!r}).read_bytes())\n')
            executable.chmod(0o755)
            with environment(PATH=str(shim) + ':' + os.environ['PATH']):
                result = await self.cache.render(self.request())
            self.assertEqual(result['decoder'], 'ffmpeg')
            self.assertEqual(result['width'], 128)

        async def test_failure_cache_changes_with_decoder_capability(self):
            shim = self.folder / 'bin'
            shim.mkdir()
            for name in ('magick', 'ffmpeg'):
                path = shim / name
                path.write_text('#!/bin/sh\nexit 0\n')
                path.chmod(0o755)
            with environment(PATH=str(shim) + ':' + os.environ['PATH']):
                with self.assertRaises(SourceError):
                    await self.cache.render(self.request())
                negative = await self.cache.render(self.request())
                self.assertEqual(negative['status'], 'unavailable')
                self.assertEqual(negative['url'], '')
            # The exact same source, representation and cache retries as soon
            # as the executable capability changes. No release bump or wipe.
            result = await self.cache.render(self.request())
            self.assertEqual(result['status'], 'generated')

        async def test_unreadable_missing_and_provider_never_become_cli_sources(self):
            for source, expected in ((str(fixtures / 'Unreadable.webp'), 'unreadable'),
                                     (str(fixtures / 'Missing.webp'), 'missing'), ('image://qsimage/123', 'provider-required')):
                with self.subTest(source=source):
                    with self.assertRaises(SourceError) as caught:
                        await self.cache.render(dict(self.request(), source=source))
                    self.assertEqual(caught.exception.code, expected)
            self.assertFalse(any('image://' in str(row.get('argv', '')) for row in self.events))

        async def test_png_structure_without_pixels_is_rejected(self):
            data = PNG + chunk(b'IHDR', struct.pack('!IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'not pixels')) + chunk(b'IEND', b'')
            with self.assertRaises(ValueError):
                validate(data)
            self.assertEqual(validate(empty_png())['width'], 1)

        async def test_two_slots_and_replacement_cancellation(self):
            gate, entered, emitted = asyncio.Event(), [], []
            class Slow:
                async def render(_self, request):
                    entered.append(request['id'])
                    await gate.wait()
                    return dict(status='generated', url='file:///fixture.png')
                def lease(_self, result):
                    return None
            worker = Worker(Slow(), emitted.append)
            requests = [dict(id=str(i), source='fixture', generation=i) for i in range(3)]
            worker.replace(requests)
            for _ in range(100):
                if len(entered) == 2:
                    break
                await asyncio.sleep(.01)
            self.assertEqual(entered, ['0', '1'])
            worker.replace(requests[:2])
            gate.set()
            await asyncio.gather(*worker.tasks.values())
            await worker.close()
            self.assertNotIn('2', entered)
            self.assertEqual([r['generation'] for r in emitted if r.get('status')], [0, 1])

        async def test_known_metadata_is_not_starved_by_two_decoders(self):
            gate, entered, emitted = asyncio.Event(), [], []
            async def held_frame(path, size):
                entered.append(str(path))
                await gate.wait()
                return empty_png()
            files = [self.folder / ('Held' + str(i) + '.mp4') for i in range(2)]
            for path in files:
                path.write_bytes((fixtures / 'frame-0.png').read_bytes())
            requests = [dict(path=str(path), pixels=128, stamp='held') for path in files]
            inspect = dict(id='inspect', generation=9, source=str(fixtures / 'frame-0.png'),
                           width=128, height=128, animationIntent='still', operation='inspect')
            worker = Worker(self.cache, emitted.append)
            with patch.object(self.cache, 'frame', held_frame):
                try:
                    worker.replace(requests)
                    for _ in range(100):
                        if len(entered) == 2:
                            break
                        await asyncio.sleep(.01)
                    self.assertEqual(len(entered), 2)
                    worker.replace(requests + [inspect])
                    await asyncio.wait_for(asyncio.shield(worker.tasks['inspect']), 1)
                    self.assertFalse(gate.is_set())
                    self.assertTrue(any(row.get('id') == 'inspect' and row.get('status') == 'inspected' for row in emitted))
                finally:
                    await worker.close()

        async def test_video_adapter_shares_implementation_and_cache(self):
            spec = importlib.util.spec_from_file_location('video_adapter', args.source / 'Scripts/python/src/filechooser/thumbnails.py')
            adapter = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(adapter)
            self.assertIs(adapter.Cache, Cache)
            self.assertIs(adapter.Worker, Worker)
            video = self.folder / 'Video.mp4'
            made = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i',
                                   'testsrc2=size=160x90:rate=8:duration=2', '-c:v', 'libx264', '-threads', '1', str(video)],
                                  capture_output=True, timeout=30)
            self.assertEqual(made.returncode, 0, made.stderr)
            first = await self.cache.get(str(video), 128)
            self.assertEqual(first['status'], 'generated')
            self.assertEqual(len(self.events), 1)
            self.assertEqual(self.events[0]['event'], 'ffmpeg')
            argv = self.events[0]['argv']
            self.assertAlmostEqual(float(argv[argv.index('-ss') + 1]), .2)
            second = await self.cache.get(str(video), 128)
            self.assertEqual(second['status'], 'hit')
            self.assertEqual(second['url'], first['url'])
            self.assertEqual(len(self.events), 1)

        async def test_video_thumbnail_failure_honors_explicit_retry(self):
            video = self.folder / 'Broken.mp4'
            video.write_bytes(b'not a video')
            request = dict(source=str(video), width=256, height=256, fit='contain', animationIntent='still', operation='video-thumbnail')
            decodes = []
            original = self.cache.frame
            async def frame(*arguments):
                decodes.append(arguments)
                return await original(*arguments)
            with patch.object(self.cache, 'frame', frame):
                failed = await self.cache.render(request)
                self.assertEqual((failed['status'], failed['url']), ('unavailable', ''))
                self.assertEqual(len(decodes), 1)
                # A stored failure answers later ordinary requests without decoding.
                again = await self.cache.render(request)
                self.assertEqual(again['status'], 'unavailable')
                self.assertEqual(len(decodes), 1)
                # An explicit retry decodes again, and still reports the failure.
                retried = await self.cache.render(dict(request, retry=True))
                self.assertEqual(retried['status'], 'unavailable')
                self.assertEqual(len(decodes), 2)

        def process_identity(self, pid):
            proc = Path('/proc') / str(pid)
            fields = (proc/'stat').read_text().rsplit(') ', 1)[1].split()
            return dict(pid=pid, start=fields[19], uid=proc.stat().st_uid)

        def process_descendants(self, pid):
            rows = [self.process_identity(pid)]
            for child in (Path(f'/proc/{pid}/task/{pid}/children').read_text().split()):
                rows.extend(self.process_descendants(int(child)))
            return rows

        def assert_processes_retired(self, identities):
            remaining = []
            for row in identities:
                try:
                    if self.process_identity(row['pid']) == row:
                        remaining.append(row)
                except FileNotFoundError:
                    pass
            self.assertEqual(remaining, [])
            self.events.append(dict(retired=identities))

        async def held_http_retirement(self, malformed):
            entered, release, returned = threading.Event(), threading.Event(), threading.Event()
            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header('Content-Length', '131072')
                    self.end_headers()
                    entered.set()
                    try:
                        release.wait(10)
                        self.wfile.write(b'incomplete image bytes')
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    finally:
                        returned.set()
                def log_message(self, *_args):
                    pass
            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            process = await asyncio.create_subprocess_exec(sys.executable, '-B', str(args.source/'Scripts/python/image-worker.py'),
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                env=dict(os.environ, XDG_CACHE_HOME=str(self.folder/'cache')))
            identities, replies = [], []
            try:
                self.assertEqual(json.loads(await asyncio.wait_for(process.stdout.readline(), 3))['event'], 'ready')
                request = dict(self.request(), id='held-http', generation=1, source=f'http://127.0.0.1:{server.server_port}/held')
                process.stdin.write((json.dumps([request])+'\n').encode())
                await process.stdin.drain()
                for _ in range(300):
                    if entered.is_set():
                        break
                    await asyncio.sleep(.01)
                self.assertTrue(entered.is_set())
                identities = self.process_descendants(process.pid)
                self.assertGreaterEqual(len(identities), 3)  # worker, supervisor, real HTTP downloader
                if malformed:
                    process.stdin.write(b'[false]\n')
                    await process.stdin.drain()
                    while True:
                        row = json.loads(await asyncio.wait_for(process.stdout.readline(), 5))
                        replies.append(row)
                        if row.get('event') == 'protocol-error':
                            break
                process.stdin.close()
                await asyncio.wait_for(process.wait(), 5)
                replies += [json.loads(line) for line in (await process.stdout.read()).splitlines()]
                self.assertEqual(process.returncode, 0, (await process.stderr.read()).decode())
                self.assertFalse(any(row.get('status') for row in replies), replies)
                self.assertEqual(sum(row.get('event') == 'protocol-error' for row in replies), int(malformed))
                self.assert_processes_retired(identities)
                cache = self.folder/'cache/thumbnails/atmosphera-representations-v1'
                self.assertEqual(list((cache/'staging').iterdir()), [])
                self.assertEqual(list((cache/'fail').glob('*')), [])
                self.assertEqual(list((cache/'still').glob('*')), [])
                self.events.append(dict(replies=replies, malformed=malformed, heldHttp=True))
            finally:
                if process.returncode is None:
                    process.kill()
                    await process.wait()
                release.set()
                server.shutdown()
                server.server_close()
                thread.join()
                if entered.is_set():
                    self.assertTrue(returned.wait(3))

        async def test_eof_retires_held_http_and_every_owned_process(self):
            await self.held_http_retirement(False)

        async def test_malformed_batch_retires_held_http_without_stale_success(self):
            await self.held_http_retirement(True)

        def private_entries(self):
            return sorted(str(path.relative_to(self.cache.private)) for name in ('still', 'animated', 'fail')
                          for path in (self.cache.private / name).glob('*') if not path.name.startswith('.'))

        async def test_owner_clear_keeps_held_and_everything_outside_the_owner(self):
            emitted = []
            worker = Worker(self.cache, emitted.append)
            worker.replace([dict(self.request('Still.webp'), id='held', generation=1)])
            await asyncio.gather(*worker.tasks.values())
            held = Path(emitted[-1]['url'].removeprefix('file://'))
            self.assertEqual(emitted[-1]['status'], 'generated')
            moving = await self.cache.render(dict(self.request('Motion.webp'), animationIntent='preserve'))
            self.assertTrue(moving['url'].endswith('.gif'))
            async def fail(*_args):
                raise SourceError('decode-unavailable', 'Owned decoder failure')
            with patch.object(self.cache, 'decode', fail), self.assertRaises(SourceError):
                await self.cache.render(self.request('Still.jpg'))
            foreign_source = self.folder / 'foreign.webp'
            foreign_source.write_bytes((fixtures / 'Still.webp').read_bytes())
            thumbnail = await self.cache.render(dict(self.thumbnail_request(), source=str(foreign_source)))
            freedesktop = foreign_target(self.cache.root, foreign_source)
            retained_dir = self.folder / 'retained'
            retained = Path((await self.cache.render(self.request('Motion.webp', operation='retain',
                                                                  destinationDirectory=str(retained_dir))))['originalPath'])
            writer = self.cache.private / 'still' / '.atmosphera-another-writer'
            writer.write_bytes(b'partial')
            (self.cache.staging / 'other-process').mkdir(parents=True)
            outside = self.folder / 'outside.png'
            outside.write_bytes(held.read_bytes())
            planted = self.cache.private / 'animated' / 'planted.gif'
            planted.symlink_to(outside)
            legacy = self.folder / 'legacy'
            (legacy / 'mpvpaper').mkdir(parents=True)
            (legacy / 'old-key.png').write_bytes(b'legacy')
            (legacy / 'mpvpaper' / 'plugin.bmp').write_bytes(b'plugin')
            (legacy / 'notes.txt').write_text('not a shell output')
            preserved = {path: path.read_bytes() for path in (held, freedesktop, retained, writer, outside,
                         fixtures / 'Still.webp', foreign_source, legacy / 'mpvpaper' / 'plugin.bmp', legacy / 'notes.txt')}
            before = self.private_entries()
            self.assertGreaterEqual(len(before), 4)
            counts = self.cache.clear([str(legacy)])
            self.assertEqual(self.private_entries(), sorted(['still/' + held.name, 'animated/planted.gif']))
            self.assertEqual(counts['removed'], len(before) - 2 + 1)
            self.assertFalse((legacy / 'old-key.png').exists())
            self.assertTrue(planted.is_symlink())
            self.assertTrue((self.cache.staging / 'other-process').is_dir())
            self.assertEqual({path: path.read_bytes() for path in preserved}, preserved)
            self.assertEqual(thumbnail['thumbnailOrigin'], 'generated')
            # Releasing the last interest releases the lease; the next sweep
            # removes it and the same request regenerates rather than failing.
            worker.replace([])
            await worker.close()
            self.assertEqual(self.cache.clear()['removed'], 1)
            self.assertFalse(held.exists())
            self.assertEqual((await self.cache.render(self.request('Still.webp')))['status'], 'generated')
            self.assertEqual(pixel(held), list(COLORS[0]))

        async def test_owner_clear_refuses_redirected_namespace(self):
            await self.cache.render(self.request('Still.webp'))
            outside = self.folder / 'user-directory'
            (self.cache.private / 'still').rename(outside)
            (self.cache.private / 'still').symlink_to(outside, target_is_directory=True)
            names = sorted(path.name for path in outside.iterdir())
            counts = self.cache.clear()
            self.assertEqual(counts['refused'], 1)
            self.assertEqual(sorted(path.name for path in outside.iterdir()), names)
            self.assertEqual(self.cache.clear([str(outside / names[0]), str(self.cache.private / 'still')])['refused'], 3)
            self.assertEqual(sorted(path.name for path in outside.iterdir()), names)

        async def test_lease_lost_to_concurrent_clear_regenerates_before_publication(self):
            render, removed = self.cache.render, []
            async def cleared_after_publication(request, **kwargs):
                result = await render(request, **kwargs)
                if not removed:
                    removed.append(self.cache.clear())
                return result
            emitted = []
            worker = Worker(self.cache, emitted.append)
            with patch.object(self.cache, 'render', cleared_after_publication):
                worker.replace([dict(self.request('Still.webp'), id='raced', generation=1)])
                await asyncio.gather(*worker.tasks.values())
            self.assertEqual(removed[0]['removed'], 1)
            path = Path(emitted[-1]['url'].removeprefix('file://'))
            self.assertEqual(emitted[-1]['status'], 'generated')
            self.assertEqual(pixel(path), list(COLORS[0]))
            self.assertEqual(self.cache.clear()['kept'], 1)
            self.assertTrue(path.exists())
            # The settled lease form of the same interest keeps the lease.
            worker.replace([dict(id='raced', generation=1, lease=emitted[-1]['url'])])
            self.assertEqual(self.cache.clear()['kept'], 1)
            await worker.close()
            self.assertEqual(self.cache.clear()['removed'], 1)

        async def test_clear_respects_another_process_lease_and_lease_only_restart(self):
            processes = []
            async def start():
                process = await asyncio.create_subprocess_exec(sys.executable, '-B', str(args.source/'Scripts/python/image-worker.py'),
                    stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                    env=dict(os.environ, XDG_CACHE_HOME=str(self.folder/'shared')))
                processes.append(process)
                self.assertEqual(json.loads(await asyncio.wait_for(process.stdout.readline(), 3))['event'], 'ready')
                return process
            async def send(process, message):
                process.stdin.write((json.dumps(message) + '\n').encode())
                await process.stdin.drain()
                while True:
                    row = json.loads(await asyncio.wait_for(process.stdout.readline(), 30))
                    if row.get('status') or row.get('event') in ('cleared', 'clear-failed', 'protocol-error'):
                        return row
            async def finish(process):
                process.stdin.close()
                await asyncio.wait_for(process.wait(), 10)
                self.assertEqual(process.returncode, 0, (await process.stderr.read()).decode())
            try:
                holder, sweeper = await start(), await start()
                result = await send(holder, [dict(self.request('Still.webp'), id='1', generation=1)])
                path = Path(result['url'].removeprefix('file://'))
                cleared = await send(sweeper, dict(command='clear', id='c1'))
                self.assertEqual((cleared['event'], cleared['removed'], cleared['kept']), ('cleared', 0, 1))
                self.assertEqual(pixel(path), list(COLORS[0]))
                await finish(holder)
                # A restarted owner re-leases a settled interest without work.
                restarted = await start()
                restarted.stdin.write((json.dumps([dict(id='1', generation=1, lease=result['url'])]) + '\n').encode())
                await restarted.stdin.drain()
                lease_file = self.folder/'shared/thumbnails/atmosphera-representations-v1/leases'/('still-' + path.name + '.lease')
                for _ in range(500):
                    with lease_file.open('rb') as probe:
                        try:
                            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        except BlockingIOError:
                            break
                    await asyncio.sleep(.01)
                else:
                    self.fail('Restarted worker never leased its settled interest')
                cleared = await send(sweeper, dict(command='clear', id='c2'))
                self.assertEqual((cleared['removed'], cleared['kept']), (0, 1))
                self.assertTrue(path.exists())
                await finish(restarted)
                cleared = await send(sweeper, dict(command='clear', id='c3'))
                self.assertEqual((cleared['removed'], cleared['kept']), (1, 0))
                self.assertFalse(path.exists())
                rejected = await send(sweeper, dict(command='clear', id='c4', legacy=['relative']))
                self.assertEqual(rejected['event'], 'protocol-error')
                await finish(sweeper)
            finally:
                for process in processes:
                    if process.returncode is None:
                        process.kill()
                        await process.wait()

        async def test_independent_workers_publish_same_representation_atomically(self):
            workers, identities, replies = [], [], []
            async def receive(process):
                while True:
                    row = json.loads(await asyncio.wait_for(process.stdout.readline(), 8))
                    replies.append(row)
                    if row.get('event') == 'command':
                        try:
                            identities.extend(self.process_descendants(row['watcher']))
                        except FileNotFoundError:
                            pass  # Already retired before this observation.
                    if row.get('event') == 'command-result':
                        identities.append({key: row['child'][key] for key in ('pid', 'start', 'uid')})
                    if row.get('status'):
                        return row
            try:
                for number in range(2):
                    process = await asyncio.create_subprocess_exec(sys.executable, '-B', str(args.source/'Scripts/python/image-worker.py'),
                        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                        env=dict(os.environ, XDG_CACHE_HOME=str(self.folder/'shared')))
                    workers.append(process)
                    identities.append(self.process_identity(process.pid))
                    self.assertEqual(json.loads(await asyncio.wait_for(process.stdout.readline(), 3))['event'], 'ready')
                for number, process in enumerate(workers):
                    process.stdin.write((json.dumps([dict(self.request('Motion.webp'), id=str(number), generation=number)])+'\n').encode())
                    await process.stdin.drain()
                pending = [asyncio.create_task(receive(process)) for process in workers]
                observed = []
                directory = self.folder/'shared/thumbnails/atmosphera-representations-v1/still'
                while not all(task.done() for task in pending):
                    for path in directory.glob('*.png'):
                        data = path.read_bytes()
                        validate(data)
                        observed.append(hashlib.sha256(data).hexdigest())
                    await asyncio.sleep(.001)
                first, second = await asyncio.gather(*pending)
                self.assertEqual(first['url'], second['url'])
                self.assertIn(first['status'], ('generated', 'hit'))
                self.assertIn(second['status'], ('generated', 'hit'))
                target = Path(first['url'].removeprefix('file://'))
                self.assertEqual(pixel(target), list(COLORS[0]))
                validate(target.read_bytes())
                observed.append(hashlib.sha256(target.read_bytes()).hexdigest())
                self.assertEqual(set(observed), {hashlib.sha256(target.read_bytes()).hexdigest()})
                for process in workers:
                    process.stdin.close()
                    await asyncio.wait_for(process.wait(), 5)
                    self.assertEqual(process.returncode, 0, (await process.stderr.read()).decode())
                    replies += [json.loads(line) for line in (await process.stdout.read()).splitlines()]
                self.assert_processes_retired(identities)
                root = self.folder/'shared/thumbnails/atmosphera-representations-v1'
                self.assertEqual(list((root/'staging').iterdir()), [])
                self.assertEqual(list(root.rglob('.atmosphera-*')), [])
                self.events.append(dict(replies=replies, completeObservations=len(observed)))
            finally:
                for process in workers:
                    if process.returncode is None:
                        process.kill()
                        await process.wait()

        async def test_timeout_reaps_session_creating_delegate(self):
            marker = self.folder / 'delegate.json'
            body = ('import subprocess,sys,json,os,time; from pathlib import Path; '
                    'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"],start_new_session=True); '
                    'pids=[os.getpid(),p.pid]; '
                    'Path(sys.argv[1]).write_text(json.dumps([{ "pid":pid,"start":Path(f"/proc/{pid}/stat").read_text().rsplit(")",1)[1].split()[19]} for pid in pids])); time.sleep(30)')
            with self.assertRaises(CommandError) as caught:
                await command([sys.executable, '-c', body, str(marker)], self.folder, .5, emit=self.events.append)
            self.assertEqual(caught.exception.code, 'timeout')
            identities = json.loads(marker.read_text())
            self.assertTrue(all(not Path(f'/proc/{row["pid"]}').exists() for row in identities), identities)
            self.events.append(dict(retired=identities))

        async def test_worker_death_reaps_decoder_and_delegate(self):
            shim = self.folder / 'bin'
            shim.mkdir()
            marker = self.folder / 'delegate.json'
            executable = shim / 'magick'
            executable.write_text('#!/usr/bin/python3\nimport os,subprocess,sys,time,json\nfrom pathlib import Path\n'
                                  'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"],start_new_session=True)\n'
                                  f'Path({str(marker)!r}).write_text(json.dumps([os.getpid(),p.pid]))\ntime.sleep(30)\n')
            executable.chmod(0o755)
            process = await asyncio.create_subprocess_exec(sys.executable, '-B', str(args.source / 'Scripts/python/image-worker.py'),
                            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                            env=dict(os.environ, PATH=str(shim) + ':' + os.environ['PATH'], XDG_CACHE_HOME=str(self.folder / 'cache')))
            try:
                self.assertEqual(json.loads(await asyncio.wait_for(process.stdout.readline(), 5))['event'], 'ready')
                process.stdin.write((json.dumps([dict(self.request(), id='death', generation=1)]) + '\n').encode())
                await process.stdin.drain()
                for _ in range(300):
                    if marker.exists():
                        break
                    await asyncio.sleep(.01)
                self.assertTrue(marker.exists())
                pids = json.loads(marker.read_text())
                identities = {pid: Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19] for pid in pids}
                process.kill()
                await process.wait()
                for _ in range(300):
                    if all(not Path(f'/proc/{pid}').exists() for pid in pids):
                        break
                    await asyncio.sleep(.01)
                self.assertTrue(all(not Path(f'/proc/{pid}').exists() for pid in pids), identities)
                self.events.append(dict(workerExit=process.returncode, retired=identities))
            finally:
                if process.returncode is None:
                    process.kill()
                    await process.wait()

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Tests)
    with (args.output / 'tests.log').open('w') as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    unchanged = source_manifest(args.source) == inputs
    receipt = dict(passed=result.wasSuccessful() and unchanged, cases=result.testsRun, inputsSha256=inputs['sha256'],
                   sourceUnchanged=unchanged,
                   failures=[(str(test), reason) for test, reason in result.failures + result.errors], guest=profile.record())
    (args.output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (args.output / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    (args.output / 'decoder-events.json').write_text(json.dumps(events, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
