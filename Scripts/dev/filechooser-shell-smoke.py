#!/usr/bin/env python3
"""Cold-load the actual shell tree in the checked private guest session."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from filechooser_profile import profile_argument
from filechooser_isolation import enter
from filechooser_regression import Run
from qml_probe import inject_probe, probe_owner_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    profile_argument(parser)
    parser.add_argument("--lint", nargs=argparse.REMAINDER, metavar="QML_FILE",
                        help="lint using the cold shell's generated imports before retiring the runtime")
    args = parser.parse_args()
    # Match the existing full-UI allocator profile under the same MemoryHigh;
    # retained/huge pages must not turn the quit timer into reclaim thrashing.
    enter(resource_subject=True)
    with Run.session(args.source, args.label, collect=False) as run:
        return cold_load(run, args.lint)


def cold_load(run, lint):
    entry = run.shell / "shell.qml"
    metadata = run.shell / ".qmlls.ini"
    if lint is not None:
        metadata.touch()
    owner = probe_owner_path(run.shell)
    owner.write_text(inject_probe(owner.read_text(),
        'Timer { interval: 8000; running: true; onTriggered: Qt.quit() }'))
    process = run.launch(["timeout", "--kill-after=5", "90", "qs", "-p", entry], "cold-load.log")
    process.wait()
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
    if lint is not None and result["passed"]:
        vfs = metadata.resolve().parent
        with (run.output / "lint.log").open("w") as lint_log:
            if (vfs / "qs/Commons/qmldir").is_file():
                result["lintExit"] = subprocess.run(
                    ["timeout", "--kill-after=5", "120", "Scripts/dev/qmllint.sh", *lint],
                    cwd=run.source, env=dict(os.environ, QS_VFS=str(vfs)),
                    stdout=lint_log, stderr=subprocess.STDOUT).returncode
            else:
                lint_log.write("Cold shell did not generate the QML tooling imports\n")
                result["lintExit"] = 1
        result["passed"] = result["lintExit"] == 0
    (run.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
