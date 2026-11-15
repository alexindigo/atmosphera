#!/usr/bin/env python3
"""Guest-only imports and admission checks for every chooser service launcher."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys

from filechooser_profile import current_profile, profile_argument


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    profile_argument(parser)
    args = parser.parse_args()
    profile = current_profile()
    profile.prepare_roots()
    cases = []
    scripts = Path(__file__).resolve().parent
    seconds = runpy.run_path(str(scripts / "filechooser-ui-regression.py"), run_name="import_probe")["suite_seconds"]
    cases.append({"case": "ui-complete-suite-budget", "pass": seconds() == seconds(False, False) == 1200})
    cases.append({"case": "ui-short-partition-budget", "pass": all(seconds(*(i == j for i in range(6))) == 840 for j in range(6))})
    child_seconds = runpy.run_path(str(scripts / "filechooser-harness.py"), run_name="import_probe")["workload_seconds"]
    previous_seconds = os.environ.get("FILECHOOSER_SESSION_SECONDS")
    try:
        for value in (840, 1200):
            os.environ["FILECHOOSER_SESSION_SECONDS"] = str(value)
            cases.append({"case": "harness-inherits-budget-" + str(value), "pass": child_seconds() == value})
    finally:
        if previous_seconds is None:
            os.environ.pop("FILECHOOSER_SESSION_SECONDS", None)
        else:
            os.environ["FILECHOOSER_SESSION_SECONDS"] = previous_seconds
    for name in ("theming-load-units.py", "theming-shell-units.py", "owned-process-regression.py"):
        try:
            runpy.run_path(str(scripts / name), run_name="import_probe")
            cases.append({"case": name + "-imports", "pass": True})
        except ImportError as error:
            cases.append({"case": name + "-imports", "pass": False, "error": str(error)})
    for kind in ("isolation", "gate", "service"):
        label = args.label + "-" + kind
        with (profile.runtime / (".filechooser-" + kind + ".lock")).open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = subprocess.run(["timeout", "30", sys.executable, "-B",
                                     str(scripts / "filechooser-volumes-regression.py"),
                                     "--source", str(profile.source), "--label", label,
                                     "--guest-profile", str(profile.path)],
                                    capture_output=True, text=True, timeout=40)
        (profile.evidence / (label + ".log")).write_text(result.stdout + result.stderr)
        refused = result.returncode != 0 and ("BlockingIOError" in result.stderr or "admission refused" in result.stderr)
        cases.append({"case": "volumes-respects-" + kind + "-lock", "pass": refused,
                      "service_started": "Running as unit:" in result.stderr})
    from filechooser_isolation import admit
    try:
        admit(768 * 1024 * 1024, available=0)
    except RuntimeError:
        cases.append({"case": "insufficient-memory-refused", "pass": True})
    else:
        cases.append({"case": "insufficient-memory-refused", "pass": False})
    print(json.dumps({"passed": all(row["pass"] for row in cases), "cases": cases}, indent=2))
    return 0 if all(row["pass"] for row in cases) else 1


if __name__ == "__main__":
    sys.exit(main())
