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
