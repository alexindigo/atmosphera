#!/usr/bin/env python3
"""Stable live escape must fail; identity/exit races and quick children must not."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from unittest.mock import patch

from filechooser_isolation import ROOT, cgroup, enter, process_stat, sample_process, sample_violation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--mode", choices=("stress", "escape"), required=True)
    a = parser.parse_args()
    enter(audit_probe=a.mode == "escape")
    output = ROOT / "evidence" / a.label
    output.mkdir()
    base = Path(os.environ["FILECHOOSER_ISOLATION"])
    outer = ROOT / "evidence" / (a.label + "-isolation")
    expected = str(cgroup())
    cases = []
    def check(name, condition, detail=None):
        cases.append({"case": name, "pass": bool(condition), "detail": detail})
        print(name, "PASS" if condition else "FAIL", flush=True)
        assert condition, name
    def wait(fn, seconds=12):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            value = fn()
            if value: return value
            time.sleep(.01)
        raise AssertionError("audit test readiness timeout")
    me = Path("/proc/self")
    current = sample_process(me)
    check("stable-self", current["disposition"] == "live" and not sample_violation(current, expected), current)
    identities = [dict(current["stat_before"]), dict(current["stat_before"], start_time=current["start_time"] + 1)]
    with patch("filechooser_isolation.process_stat", side_effect=identities):
        changed = sample_process(me)
    check("changed-identity-discarded", changed["disposition"] == "identity_changed", changed)
    with patch("filechooser_isolation.process_stat", side_effect=[current["stat_before"], FileNotFoundError()]):
        vanished = sample_process(me)
    check("vanished-during-read-discarded", vanished["disposition"] == "vanished", vanished)
    empty = dict(current, command="", cgroup="/sys/fs/cgroup")
    check("live-empty-command-still-fails", sample_violation(empty, expected))
    # Keep an actual exited child unreaped: a zombie's metadata is retained as
    # exited evidence, not called a live escape or silently dropped.
    child = subprocess.Popen(["/usr/bin/true"])
    proc = Path("/proc") / str(child.pid)
    try:
        wait(lambda: process_stat(proc)["state"] == "Z")
        zombie = sample_process(proc)
        check("exited-child-retained", zombie["disposition"] == "exited" and not sample_violation(zombie, expected), zombie)
    finally:
        child.wait(timeout=5)
    reaped = sample_process(proc)
    check("reaped-child-vanished", reaped["disposition"] == "vanished", reaped)
    if a.mode == "stress":
        completed = 0
        # 4,000 quick processes (2,000 timeout wrappers plus their true children),
        # with a bounded fan-out well below the unit's TasksMax.
        for _ in range(125):
            children = [subprocess.Popen(["timeout", "2", "/usr/bin/true"]) for _ in range(16)]
            for process in children:
                assert process.wait(timeout=5) == 0
                completed += 1
        check("quick-child-stress", completed == 2000, {"wrappers": completed, "total_processes": completed * 2})
        (output / "result.json").write_text(json.dumps({"passed": True, "expected_unit_exit": 0, "cases": cases,
            "audit_receipt": str(outer / "process-cgroups.json")}, indent=2))
    else:
        request = base / "audit-probe.request"
        request.write_text("live-sibling\n")
        info = wait(lambda: json.loads((base / "audit-probe-live.json").read_text())
                    if (base / "audit-probe-live.json").exists() and (base / "audit-probe-attested").exists() else None)
        check("outside-process-shares-private-pid-namespace", info["namespace"] == os.environ["FILECHOOSER_PID_NAMESPACE"], info)
        target = Path("/proc") / str(info["pid"])
        first = sample_process(target)
        time.sleep(.05)
        second = sample_process(target)
        check("actual-live-outside-process-rejected", first["disposition"] == second["disposition"] == "live"
              and first["start_time"] == second["start_time"] and sample_violation(first, expected)
              and sample_violation(second, expected) and first["oom_score_adj"] == second["oom_score_adj"] == "1000", [first, second])
        detected = wait(lambda: json.loads((outer / "first-violation.json").read_text())
                        if (outer / "first-violation.json").exists() else None)
        check("background-audit-detects-live-outside-unit", detected["pid"] == info["pid"]
              and detected["start_time"] == first["start_time"] and sample_violation(detected, expected), detected)
        (base / "audit-probe-release").touch()
        probe = wait(lambda: json.loads((outer / "audit-probe.json").read_text()) if (outer / "audit-probe.json").exists() else None)
        check("outside-probe-reaped", probe["passed"], probe)
        # The automatic supervisor must now reject this entire run at its own
        # audit assertion. The test controller proves expected exit 1 separately.
        (output / "result.json").write_text(json.dumps({"detected": True, "expected_unit_exit": 1,
            "cases": cases, "outside_pid": info["pid"], "outside_start_time": first["start_time"]}, indent=2))


if __name__ == "__main__":
    main()
