#!/usr/bin/env python3
"""Run only in the assigned guest with a disk-backed TMPDIR."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from gui_timing_capture import ConsoleCapture
from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


class CaptureTests(unittest.TestCase):
    def setUp(self):
        root = os.environ.get('TMPDIR')
        assert root, 'explicit guest disk TMPDIR required'
        require_disk_backed_paths(root)
        self.temp = tempfile.TemporaryDirectory(dir=root)
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_console_exact_bytes_and_eof(self):
        payload = bytes(range(256)) * 10000
        script = 'import sys;sys.stdout.buffer.write(bytes(range(256))*10000)'
        process = subprocess.Popen([sys.executable, '-B', '-c', script], stdout=subprocess.PIPE)
        capture = ConsoleCapture(process.stdout, self.root/'console.log')
        self.assertEqual(process.wait(timeout=15), 0)
        receipt = capture.finish()
        self.assertEqual((self.root/'console.log').read_bytes(), payload)
        self.assertEqual(receipt['bytes'], len(payload))
        self.assertEqual(receipt['sha256'], hashlib.sha256(payload).hexdigest())

    def test_console_sink_failure_is_not_success(self):
        path = self.root/'existing.log'
        path.write_bytes(b'preserved')
        capture = ConsoleCapture(io.BufferedReader(io.BytesIO(b'new')), path)
        with self.assertRaisesRegex(RuntimeError, 'collector failed'):
            capture.finish()
        self.assertEqual(path.read_bytes(), b'preserved')

    def test_native_drain_conservation_and_error(self):
        fixture = self.root/'control.cpp'
        fixture.write_text('#include "settings-gui-log.hpp"\n#include <cstdio>\n'
                           'int main(){char line[80];for(int i=0;i<20000;i++){'
                           'int n=snprintf(line,sizeof line,"record %d\\n",i);'
                           'settingsGuiLogAppend(0,line,n);}return 0;}\n')
        binary = self.root/'qs'
        subprocess.run(['g++', '-O2', '-pthread', '-I'+str(HERE/'fixtures'), str(fixture),
                        str(HERE/'fixtures/settings-gui-log.cpp'), '-o', str(binary)], check=True, timeout=45)
        trace = self.root/'native.trace'
        env = dict(os.environ, ATMOSPHERA_GUI_TRACE=str(trace))
        process = subprocess.Popen([str(binary)], env=env)
        self.assertEqual(process.wait(timeout=20), 0)
        expected = ''.join('record '+str(i)+'\n' for i in range(20000)).encode()
        self.assertEqual(trace.read_bytes(), expected)
        receipt = json.loads(Path(str(trace)+'.async-'+str(process.pid)+'.json').read_text())
        self.assertEqual(receipt['published'], 20000)
        self.assertEqual(receipt['drained'], 20000)
        self.assertEqual(receipt['traceBytes'], len(expected))
        self.assertEqual(receipt['dropped'], 0)
        failed = subprocess.run([str(binary)], env=dict(env, ATMOSPHERA_GUI_TRACE='/dev/full'), timeout=20)
        self.assertEqual(failed.returncode, 113)


if __name__ == '__main__':
    unittest.main()
