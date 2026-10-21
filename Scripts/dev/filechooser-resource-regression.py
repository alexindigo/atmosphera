#!/usr/bin/env python3
"""Attest actual systemd limits, admission refusal and a whole gate's children."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from filechooser_isolation import ROOT, SAFETY_MARGIN, admit, cgroup, enter, memory_info


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    output = ROOT / "evidence" / args.label
    output.mkdir()
    outer = ROOT / "evidence" / (args.label + "-isolation")
    props = json.loads((outer / "systemd-properties.json").read_text())
    cases = []
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    check("systemd-readback-oom-and-caps", props["OOMScoreAdjust"] == "1000"
          and int(props["MemoryMax"]) > 0 and int(props["MemoryHigh"]) > 0
          and props["TasksMax"] == "256" and props["MemorySwapMax"] == "0"
          and props["CPUQuotaPerSecUSec"] not in ("0", "infinity"), props)
    for name, budget, available in (("real-oversized", memory_info()["MemTotal"] * 2, None),
                                    ("margin-boundary", 256 * 1024 * 1024, 256 * 1024 * 1024 + SAFETY_MARGIN - 1)):
        refused = ""
        try:
            admit(budget, available)
        except RuntimeError as error:
            refused = str(error)
        check("admission-" + name, "admission refused" in refused and "MemAvailable" in refused, refused)
    check("admission-exact-fit", admit(1, SAFETY_MARGIN + 1)["budget"] == 1)
    result = subprocess.run(["timeout", "420", "python3", "-B", str(ROOT / "tools/shell-gate.py"),
                             "--source", str(args.source.resolve()), "--label", args.label + "-gate", "--audit"],
                            capture_output=True, text=True, timeout=430)
    (output / "gate.log").write_text(result.stdout + result.stderr)
    gate = json.loads((ROOT / "evidence" / (args.label + "-gate/result.json")).read_text())
    check("whole-gate", result.returncode == 0 and all(gate["results"].values()), gate)
    check("gate-shares-checked-unit", gate["isolation"] == os.environ["FILECHOOSER_ISOLATION"])
    check("current-cgroup-capped", (cgroup() / "memory.max").read_text().strip() == props["MemoryMax"])
    (output / "result.json").write_text(json.dumps({"passed": all(c["pass"] for c in cases), "cases": cases,
        "process_audit": str(outer / "process-cgroups.json"), "systemd_properties": props}, indent=2))


if __name__ == "__main__":
    main()
