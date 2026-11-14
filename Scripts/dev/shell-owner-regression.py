#!/usr/bin/env python3
"""Guest-only pidfd/start-time and election-race regression."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("shell_owner", Path(__file__).resolve().parents[1] / "bash/shell-owner.py")
owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner)


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.child = subprocess.Popen(["sleep", "30"])

    def tearDown(self):
        if self.child.poll() is None:
            self.child.terminate()
        self.child.wait(timeout=5)

    def test_start_time_mismatch_never_signals(self):
        with patch.object(owner.signal, "pidfd_send_signal") as send:
            with self.assertRaises(ProcessLookupError):
                owner.Process(self.child.pid, "not-the-start-time")
            send.assert_not_called()
        self.assertIsNone(self.child.poll())

    def test_connection_change_never_pins_replacement(self):
        with patch.object(owner, "owner", return_value=(":1.99", self.child.pid)):
            with self.assertRaises(ProcessLookupError):
                owner.pin_owner((":1.42", self.child.pid))
        self.assertIsNone(self.child.poll())

    def test_exited_pidfd_does_not_signal_later_process(self):
        process = owner.Process(self.child.pid)
        try:
            self.child.terminate()
            self.child.wait(timeout=5)
            with subprocess.Popen(["sleep", "30"]) as replacement:
                try:
                    with patch.object(owner.signal, "pidfd_send_signal") as send:
                        process.stop("exit raced with stop")
                        send.assert_not_called()
                    self.assertIsNone(replacement.poll())
                finally:
                    replacement.terminate()
        finally:
            process.close()

    def test_responsive_queued_process_is_not_retired(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / str(self.child.pid)).write_text(json.dumps(dict(
                pid=self.child.pid, start=owner.start_time(self.child.pid),
                phase="queued", bus="test-bus", unique="")))
            with patch.object(owner, "records", return_value=root), \
                 patch.object(owner, "call", return_value="test-bus"), \
                 patch.object(owner, "owner", return_value=None), \
                 patch.object(owner, "queued_connection", return_value=":1.42"), \
                 patch.object(owner, "ping", return_value=True), \
                 patch.object(owner.Process, "stop") as stop:
                owner.retire_departed()
                stop.assert_not_called()
        self.assertIsNone(self.child.poll())

    def test_successful_ping_resets_failed_window(self):
        clock = [0]
        process = Mock(pid=self.child.pid)
        process.exited.return_value = False
        def advance(_seconds):
            clock[0] += 1
        identity = (":1.42", self.child.pid)
        with patch.object(owner, "owner", return_value=identity), \
             patch.object(owner, "ping", side_effect=[False] * 5 + [True] + [False] * 11), \
             patch.object(owner.time, "monotonic", side_effect=lambda: clock[0]), \
             patch.object(owner.time, "sleep", side_effect=advance):
            self.assertFalse(owner.wait_owner(identity, process, duplicate=True))
        self.assertEqual(clock[0], 16)
        process.stop.assert_called_once_with("owner ping failed for 10 seconds")


if __name__ == "__main__":
    assert Path("/sys/class/dmi/id/sys_vendor").read_text().strip() == "QEMU", "VM only"
    unittest.main()
