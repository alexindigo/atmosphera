#!/usr/bin/env python3
"""Worker protocol contract: thumbnail generation delegates only the cache miss."""
import json
import os
from pathlib import Path
from queue import Empty, Queue
import subprocess
import sys
import tempfile
from threading import Thread
import unittest
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]


class VideoBridgeTest(unittest.TestCase):
    def test_cache_miss_and_late_cancelled_result(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            video = directory / 'test video #1.mp4'
            video.write_bytes(b'The worker must not decode this video.')
            worker = subprocess.Popen([sys.executable, '-B', '-u', ROOT / 'Scripts/python/image-worker.py'],
                                      env=dict(os.environ, XDG_CACHE_HOME=str(directory / 'cache')),
                                      text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            lines = Queue()

            def read_lines():
                try:
                    for line in worker.stdout:
                        lines.put(line)
                finally:
                    lines.put(None)

            reader = Thread(target=read_lines, daemon=True)
            reader.start()
            try:
                def send(message):
                    worker.stdin.write(json.dumps(message) + '\n')
                    worker.stdin.flush()

                def receive():
                    try:
                        line = lines.get(timeout=10)
                    except Empty:
                        self.fail('Timed out waiting for an image worker event')
                    self.assertIsNotNone(line, 'Image worker closed stdout before the expected event')
                    return json.loads(line)

                self.assertEqual(receive()['event'], 'ready')
                request = dict(source=str(video), operation='video-thumbnail', animationIntent='still',
                               width=128, height=128, generation=1, id='one')
                send([request])
                frame = receive()
                self.assertEqual(frame.get('event'), 'video-frame-request', frame)
                self.assertEqual(frame['source'], video.as_uri())
                self.assertEqual((frame['width'], frame['height']), (128, 128))
                send([])
                cancelled = [receive(), receive()]
                self.assertIn({'event': 'video-frame-cancel', 'job': frame['job']}, cancelled)
                self.assertIn({'event': 'cancelled', 'id': 'one'}, cancelled)
                send(dict(command='video-frame-result', job=frame['job'], code=''))
                send([dict(request, generation=2, id='two')])
                next_frame = receive()
                self.assertEqual(next_frame['event'], 'video-frame-request')
                self.assertNotEqual(next_frame['job'], frame['job'])
                output = Path(unquote(urlsplit(next_frame['destination']).path))
                sys.path.insert(0, str(ROOT / 'Scripts/python/src'))
                from images.png import empty_png
                output.write_bytes(empty_png())
                send(dict(command='video-frame-result', job=next_frame['job'], code=''))
                self.assertEqual(receive()['status'], 'generated')
                send([dict(request, generation=3, id='three')])
                self.assertEqual(receive()['status'], 'hit')
                self.assertFalse(output.exists(), 'owner leaked the staged frame')
                other = directory / 'slow.mp4'
                other.write_bytes(b'Fixture video identity')
                for generation in (4, 5):
                    send([dict(request, source=str(other), generation=generation, id=str(generation))])
                    slow = receive()
                    self.assertEqual(slow.get('event'), 'video-frame-request', slow)
                    send(dict(command='video-frame-result', job=slow['job'], code='timeout'))
                    self.assertEqual(receive()['status'], 'unavailable')
            finally:
                try:
                    worker.stdin.close()
                    worker.wait(timeout=5)
                finally:
                    if worker.poll() is None:
                        worker.kill()
                        worker.wait(timeout=5)
                    reader.join(timeout=5)
                    worker.stdout.close()


if __name__ == '__main__':
    unittest.main()
