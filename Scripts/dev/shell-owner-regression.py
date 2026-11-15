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


class OwnershipLookupTests(unittest.TestCase):
    def setUp(self):
        pause = patch.object(owner.time, "sleep", return_value=None)
        pause.start()
        self.addCleanup(pause.stop)

    def test_only_explicit_absence_returns_none(self):
        with patch.object(owner, "call", return_value="b false"):
            self.assertIsNone(owner.owner())

    def test_failed_presence_lookup_is_not_absence(self):
        with patch.object(owner, "call", return_value=""):
            with self.assertRaises(RuntimeError):
                owner.owner()

    def test_failed_unique_lookup_is_not_absence(self):
        with patch.object(owner, "call", side_effect=lambda method, *args: "b true" if method == "NameHasOwner" else ""):
            with self.assertRaises(RuntimeError):
                owner.owner()

    def test_failed_pid_lookup_is_not_absence(self):
        replies = {"NameHasOwner": "b true", "GetNameOwner": 's ":1.42"'}
        with patch.object(owner, "call", side_effect=lambda method, *args: replies.get(method, "")):
            with self.assertRaises(RuntimeError):
                owner.owner()

    def test_confirmed_owner_has_unique_name_and_pid(self):
        with patch.object(owner, "call", side_effect=["b true", 's ":1.42"', "u 42"]):
            self.assertEqual(owner.owner(), (":1.42", 42))

    def test_prepare_lookup_failure_never_retires(self):
        with patch.object(owner.sys, "argv", ["shell-owner.py", "prepare"]), \
             patch.object(owner, "call", return_value=""), \
             patch.object(owner, "retire_departed") as retire:
            with self.assertRaises(RuntimeError):
                owner.main()
            retire.assert_not_called()

    def test_departure_lookup_failure_never_stops(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "42").write_text(json.dumps(dict(pid=42, start="test-start",
                phase="elected", bus="test-bus", unique=":1.42")))
            process = Mock(pid=42)
            with patch.object(owner, "records", return_value=root), \
                 patch.object(owner, "Process", return_value=process), \
                 patch.object(owner, "call", side_effect=lambda method, *args: "test-bus" if method == "GetId" else ""), \
                 patch.object(owner, "ping", return_value=False):
                with self.assertRaises(RuntimeError):
                    owner.retire_departed()
                process.stop.assert_not_called()
                process.close.assert_called_once()

    def test_pin_lookup_failure_closes_pidfd(self):
        process = Mock()
        with patch.object(owner, "Process", return_value=process), \
             patch.object(owner, "owner", side_effect=RuntimeError("lookup unavailable")):
            with self.assertRaises(RuntimeError):
                owner.pin_owner((":1.42", 42))
            process.close.assert_called_once()

    def test_queue_lookup_failure_is_not_departure(self):
        with patch.object(owner, "call", return_value=""):
            with self.assertRaises(RuntimeError):
                owner.queued_connection(42)

    def test_confirmed_absence_has_no_queued_connection(self):
        with patch.object(owner, "call", return_value="b false"):
            self.assertEqual(owner.queued_connection(42), "")

    def test_departing_owner_discovery_restarts_from_presence(self):
        with patch.object(owner, "call", side_effect=["b true", 's ":1.41"', "",
                "b true", 's ":1.42"', "u 42"]) as call:
            self.assertEqual(owner.owner(), (":1.42", 42))
            self.assertEqual([entry.args[0] for entry in call.call_args_list],
                ["NameHasOwner", "GetNameOwner", "GetConnectionUnixProcessID"] * 2)

    def test_discovery_race_can_end_in_confirmed_absence(self):
        with patch.object(owner, "call", side_effect=["b true", 's ":1.41"', "", "b false"]):
            self.assertIsNone(owner.owner())

    def test_persistent_unknown_discovery_has_bounded_retries(self):
        with patch.object(owner, "call", return_value="") as call, \
             patch.object(owner.time, "sleep") as pause, \
             patch.object(owner.Process, "stop") as stop:
            with self.assertRaises(RuntimeError):
                owner.owner()
            self.assertEqual(call.call_count, 3)
            self.assertEqual(pause.call_count, 2)
            stop.assert_not_called()

    def test_watch_survives_owner_departure_during_discovery(self):
        pids = iter(["", "u 42"])
        def call(method, *args):
            if method == "NameHasOwner":
                return "b false" if args[-1] == "org.freedesktop.Notifications" else "b true"
            if method == "GetNameOwner":
                return 's ":1.42"'
            return next(pids)
        with patch.object(owner.sys, "argv", ["shell-owner.py", "watch", "--pid", "42"]), \
             patch.object(owner, "call", side_effect=call), \
             patch.object(owner, "record") as record, \
             patch.object(owner, "retire_departed") as retire:
            self.assertEqual(owner.main(), 0)
            self.assertEqual(record.call_args.args, (42, "", ":1.42"))
            retire.assert_called_once_with(42)

    def test_queue_discovery_retries_after_a_connection_disappears(self):
        with patch.object(owner, "call", side_effect=["b true", 'as 1 ":1.41"', "",
                "b true", 'as 1 ":1.42"', "u 42"]):
            self.assertEqual(owner.queued_connection(42), ":1.42")


if __name__ == "__main__":
    assert Path("/sys/class/dmi/id/sys_vendor").read_text().strip() == "QEMU", "VM only"
    unittest.main()
