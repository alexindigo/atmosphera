#!/usr/bin/env python3
"""Guest-only NM runner canaries, including real interrupted-shell restoration."""
import argparse
import json
from pathlib import Path
import runpy
import signal
import sys
import threading
from types import SimpleNamespace
from unittest.mock import patch

import nm_live_support as live
from nm_live_support import finish_run
from nm_test_support import GuestRun, NmInterruptedError, SOURCE, analysis_canaries, wait_for


def review_canaries(owner, profile):
    failed = SimpleNamespace(receipt={"passed": False}, close=lambda: False, write=lambda: None,
                             profile=SimpleNamespace(session_environment=lambda: {}))
    rejected = False
    with patch.object(live, "run"):
        try:
            finish_run(failed)
        except RuntimeError:
            rejected = True
    owner.check("failed-owned-cleanup-rejects-command-success", rejected)

    # Interrupt after the actual signal worker is ready, before construction
    # returns. Always reap the negative control ourselves if the owner fails.
    original_wait = threading.Event.wait
    captured = []
    def interrupted_wait(event, timeout=None):
        caller = sys._getframe(1).f_locals.get("self")
        ready = original_wait(event, timeout)
        if isinstance(caller, live.SignalLog) and event is caller.ready:
            captured.append(caller)
            raise NmInterruptedError("signal constructor interruption canary")
        return ready
    interrupted = joined = False
    try:
        with patch.object(threading.Event, "wait", interrupted_wait):
            try:
                live.SignalLog(owner)
            except NmInterruptedError:
                interrupted = True
        joined = bool(captured and not captured[0].thread.is_alive() and captured[0].file.closed)
    finally:
        for logger in captured:
            if logger.thread.is_alive() or not logger.file.closed:
                logger.close()
    owner.check("interrupted-signal-construction-joins-worker", interrupted and joined)

    authorization = Path("/etc/polkit-1/rules.d/49-atmosphera-nm-events.rules")
    assert not authorization.exists(), "foreign authorization fixture exists"
    real_run = live.run
    for stage in ("after-install", "ledger"):
        def fail_install(argv, **kwargs):
            result = real_run(argv, **kwargs)
            if list(map(str, argv))[:3] == ["sudo", "-n", "install"]:
                raise NmInterruptedError("authorization install interruption canary")
            return result
        def fail_save(self):
            raise OSError("authorization ledger failure canary")
        refused = removed = False
        try:
            with patch.object(live, "run", fail_install if stage == "after-install" else real_run), \
                    patch.object(live.LiveProfiles, "save", fail_save if stage == "ledger" else live.LiveProfiles.save):
                try:
                    live.LiveProfiles(owner)
                except (NmInterruptedError, OSError):
                    refused = True
            removed = not authorization.exists()
        finally:
            if authorization.exists():
                real_run(["sudo", "-n", "rm", "--", authorization])
        owner.check("failed-profile-construction-cleans-authorization-" + stage, refused and removed)

    child_owner = GuestRun(profile, owner.work / "cleanup-exit")
    child = child_owner.launch([sys.executable, "-c", "import time; time.sleep(60)"], "owned-child")
    real_guard = child_owner.children[0][1]
    class RefusingGuard:
        def terminate(self):
            raise RuntimeError("owned cleanup failure canary")
    child_owner.children[0] = (child, RefusingGuard())
    try:
        child_owner.check("child-body-passed", True)
        refused = False
        try:
            child_owner.complete()
        except RuntimeError:
            refused = True
        owner.check("basic-runner-rejects-failed-teardown", refused and not child_owner.receipt["passed"]
                    and not child_owner.receipt["cleanupComplete"], childResult=dict(child_owner.receipt))
        primary = False
        try:
            try:
                raise ValueError("primary body failure canary")
            finally:
                child_owner.complete()
        except ValueError as error:
            primary = str(error) == "primary body failure canary"
        owner.check("teardown-preserves-primary-body-failure", primary)
    finally:
        if child.poll() is None:
            real_guard.terminate()
            child.wait(timeout=10)
        child_owner.children = []
        child_owner.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    owner = GuestRun(args.guest_profile, args.work)
    try:
        wire = runpy.run_path(str(SOURCE / "Scripts/dev/nm-idle-wire.py"))
        owner.check("wire-classifier-positive-negative-malformed-canaries", wire["parser_canaries"]())
        widget = runpy.run_path(str(SOURCE / "Scripts/dev/nm-widget-e2e.py"))
        owner.check("rendered-ssid-row-state-and-label-canaries", widget["ssid_row_canaries"]())
        analysis = analysis_canaries()
        owner.check("memory-full-scale-analysis-canaries", analysis["sampleCount"] == 121 and not analysis["historicalPlusMinus20MiB"], analysis=analysis)
        review_canaries(owner, args.guest_profile)
        child_work = owner.work / "interrupted"
        child = owner.launch([sys.executable, "-B", SOURCE / "Scripts/dev/nm-widget-e2e.py",
                              "--guest-profile", args.guest_profile, "--work", child_work, "--case", "lifecycle"], "interrupted-runner")
        result = child_work / "result.json"
        # Capture inside constructor readiness, after real resources exist but
        # before normal actions can finish. This exercises the hard failure path.
        wait_for(lambda: result.exists() and "shellIdentity" in json.loads(result.read_text()), "child owns a real shell", seconds=30)
        child.send_signal(signal.SIGTERM)
        rc = child.wait(timeout=30)
        receipt = json.loads(result.read_text())
        owner.check("interruption-preserves-failure-and-joins-children", rc != 0 and "InterruptedError" in receipt.get("error", "")
                    and receipt.get("cleanupComplete") and not receipt.get("cleanupErrors") and not receipt.get("restorationErrors"),
                    exitCode=rc, childResult=receipt)
        owner.check("interruption-restores-guest-polkit", not Path("/etc/polkit-1/rules.d/49-atmosphera-nm-events.rules").exists())
    except BaseException as error:
        owner.receipt["error"] = repr(error)
        raise
    finally:
        finish_run(owner)


if __name__ == "__main__":
    main()
