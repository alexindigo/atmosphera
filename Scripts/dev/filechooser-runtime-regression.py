#!/usr/bin/env python3
"""Observe a real workload past the former startup-subtracted deadline."""
import argparse
import json
import os
from pathlib import Path
import time

from filechooser_isolation import ROOT, checked, enter


def main():
    # The old runner terminates this workload after 20 seconds. The corrected
    # runner allows the requested minute, with a separate bounded startup.
    enter(runtime_seconds=60)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    base = checked()
    output = ROOT / "evidence" / args.label
    output.mkdir()
    receipt = {"requested_seconds": 60, "session_seconds": os.environ["FILECHOOSER_SESSION_SECONDS"],
               "private_session": str(base), "samples": []}
    started = time.monotonic()
    # Finish below the 60s deadline but beyond the old 20s deadline. The
    # remaining second is teardown headroom, not a shortened advertised budget.
    for target in (0, 25, 59):
        time.sleep(max(0, started + target - time.monotonic()))
        receipt["samples"].append(time.monotonic() - started)
        (output / "result.json").write_text(json.dumps(receipt, indent=2))
    props = json.loads((ROOT / "evidence" / (args.label + "-isolation/systemd-properties.json")).read_text())
    receipt["systemd_properties"] = props
    receipt["passed"] = (receipt["session_seconds"] == "60" and receipt["samples"][-1] >= 59
                         and props["RuntimeMaxUSec"] == "1min 40s")
    (output / "result.json").write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt, indent=2), flush=True)
    assert receipt["passed"], receipt


if __name__ == "__main__":
    main()
