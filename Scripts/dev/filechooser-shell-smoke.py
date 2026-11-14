#!/usr/bin/env python3
"""Cold-load the actual shell tree in the checked private guest session."""
import argparse
import json
from pathlib import Path
import re

from filechooser_profile import profile_argument
from filechooser_regression import Run
from qml_probe import inject_probe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    profile_argument(parser)
    args = parser.parse_args()
    run = Run(args.source, args.label)
    entry = run.shell / "shell.qml"
    entry.write_text(inject_probe(entry.read_text(),
        'Timer { interval: 8000; running: true; onTriggered: Qt.quit() }'))
    process = run.launch(["timeout", "90", "qs", "-p", entry], "cold-load.log")
    try:
        process.wait(timeout=100)
    finally:
        for log in run.logs:
            log.close()
    log = (run.output / "cold-load.log").read_text()
    errors = [line for line in log.splitlines() if re.search(
        r"TypeError|ReferenceError|Cannot assign|Failed to load configuration|is not installed", line)]
    warnings = [line for line in log.splitlines() if re.search(r"Binding loop|Unable to assign", line)]
    services = [line for line in log.splitlines() if "ERROR" in line]
    result = {"exit": process.returncode, "errors": errors,
              "startupWarnings": warnings,
              "serviceDiagnostics": services,
              "loaded": "Configuration Loaded" in log,
              "passed": process.returncode == 0 and "Configuration Loaded" in log and not errors}
    (run.output / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
