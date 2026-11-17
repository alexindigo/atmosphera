#!/usr/bin/env python3
"""Guest-only NM runner canaries, including real interrupted-shell restoration."""
import argparse
import json
from pathlib import Path
import runpy
import signal
import sys

from nm_live_support import finish_run
from nm_test_support import GuestRun, SOURCE, analysis_canaries, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guest-profile", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    owner = GuestRun(args.guest_profile, args.work)
    try:
        wire = runpy.run_path(str(SOURCE / "Scripts/dev/nm-idle-wire.py"))
        owner.check("wire-classifier-positive-negative-malformed-canaries", wire["parser_canaries"]())
        analysis = analysis_canaries()
        owner.check("memory-full-scale-analysis-canaries", analysis["sampleCount"] == 121 and not analysis["historicalPlusMinus20MiB"], analysis=analysis)
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
