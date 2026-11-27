#!/usr/bin/env python3
"""Inject short writes without relying on a full filesystem or a network."""
import errno
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python/src'))
from images import download, storage


class InjectedWrite:
    def __init__(self, stream, fault_at, fault):
        self.stream, self.fault_at, self.fault = stream, fault_at, fault
        self.calls = 0

    def __enter__(self):
        self.stream.__enter__()
        return self

    def __exit__(self, *args):
        return self.stream.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self.stream, name)

    def write(self, data):
        self.calls += 1
        if self.calls != self.fault_at:
            return self.stream.write(data)
        if self.fault == 'failed':
            raise OSError(errno.ENOSPC, 'injected write failure')
        if self.fault == 'none':
            return None
        return self.stream.write(data[:-1])


class DownloadWrites(unittest.TestCase):
    def test_first_and_last_chunk_faults_remove_partial_download(self):
        source = 'https://example.invalid/image'
        for fault_at in (1, 3):
            for fault in ('short', 'none', 'failed'):
                with self.subTest(fault_at=fault_at, fault=fault), TemporaryDirectory() as work:
                    target = Path(work) / 'download'
                    chunks = iter((b'abc', b'def', b'ghi', b''))
                    response = MagicMock(status=200, headers={'Content-Length': '9'})
                    response.__enter__.return_value = response
                    response.geturl.return_value = source
                    response.read1.side_effect = lambda size: next(chunks)
                    opener = SimpleNamespace(open=lambda *args, **kwargs: response)
                    original = Path.open

                    def open_file(path, *args, **kwargs):
                        self.assertEqual(path, target)
                        self.assertEqual(kwargs['buffering'], 0)
                        return InjectedWrite(original(path, *args, **kwargs), fault_at, fault)

                    with patch.object(download, 'build_opener', return_value=opener), patch.object(Path, 'open', open_file):
                        with self.assertRaises(OSError):
                            download.download(source, target, 9)
                    self.assertFalse(target.exists())
                    self.assertEqual(response.read1.call_count, fault_at)

    def test_atomic_cache_does_not_replace_existing_file_on_short_write(self):
        with TemporaryDirectory() as work:
            root = Path(work)
            target = root / 'frame'
            target.write_bytes(b'previous')
            fdopen = os.fdopen
            with patch.object(storage.os, 'fdopen', side_effect=lambda *args: InjectedWrite(fdopen(*args), 1, 'short')):
                with self.assertRaises(OSError):
                    storage.atomic_write(target, b'new frame', root)
            self.assertEqual(target.read_bytes(), b'previous')
            self.assertEqual(list(root.iterdir()), [target])


if __name__ == '__main__':
    unittest.main()
