#!/usr/bin/env python3
"""VM-only end-to-end profile/console refusals; never a product suite PASS."""
import argparse
from dataclasses import replace
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

from guest_profile import (ConsoleGuard, GuestProfile, ProfileBlocked, activate_profile,
                           current_profile, profile_argument, protect_owned_process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile, require_console=True)
    if args.output.exists() or args.output != args.output.resolve() or not args.output.is_relative_to(profile.journal_base):
        raise ProfileBlocked("fresh canonical profile-journal output required")
    args.output.mkdir(parents=True, mode=0o700)
    data = json.loads(args.guest_profile.read_text())
    results = []

    def refused(call):
        try:
            call()
        except ProfileBlocked:
            return
        raise AssertionError("required refusal did not occur")

    model = Path(__file__).with_name("settings-model-regression.py")
    source = model.parent.parent.parent
    for field, wrong in (("uuid", "00000000-0000-0000-0000-000000000001"),
                         ("mac", "00:00:00:00:00:01"), ("sshHostKey", "ssh-ed25519 AAAA")):
        bad = args.output / ("wrong-" + field + ".json")
        bad.write_text(json.dumps(dict(data, **{field: wrong})))
        destination = profile.journal_base / "settings-model-ownership" / ("refuse-" + field)
        assert not destination.exists()
        proc = subprocess.run(["timeout", "20", sys.executable, "-B", str(model), "--guest-profile", str(bad),
                               "--source", str(source), "--output", str(destination), "--case", "all"],
                              capture_output=True, text=True, timeout=25)
        text = proc.stdout + proc.stderr
        (args.output / ("wrong-" + field + ".log")).write_text(text)
        assert proc.returncode == 2 and "BLOCKED" in text and not destination.exists(), text
        refused(lambda: activate_profile(bad))
        assert current_profile() is profile
        results.append({"id": "reject-" + field + "-before-output", "status": "PASS"})

    changed = args.output / "changed.json"
    changed.write_text(json.dumps(data))
    captured = GuestProfile(changed)
    captured.verify()
    changed.write_text(json.dumps(data) + "\n")
    refused(captured.verify)
    results.append({"id": "profile-content-fence", "status": "PASS"})

    original = profile.console.records[0]
    refused(lambda: protect_owned_process(SimpleNamespace(pid=original.pid)))
    refused(lambda: ConsoleGuard([replace(original, start="wrong-start")]).verify(required=True))
    copied = profile.record()
    copied["console"][0]["argv"].append("detached-metadata-only")
    profile.console.verify(required=True)
    results.append({"id": "captured-console-not-owned-and-start-fenced", "status": "PASS"})

    missing = subprocess.run(["timeout", "15", sys.executable, "-B", str(model), "--source", str(source),
                              "--output", str(args.output / "missing-profile-output"), "--case", "all"],
                             capture_output=True, text=True, timeout=20)
    assert missing.returncode == 2 and "--guest-profile" in missing.stderr
    assert not (args.output / "missing-profile-output").exists()
    results.append({"id": "no-implicit-guest-default", "status": "PASS"})
    query = ["timeout", "10", "systemctl", "--user", "show", "-p", "Version", "--value"]
    original_manager = subprocess.run(query, capture_output=True, text=True, check=True, timeout=15)
    child = profile.child_environment("gp-")
    child_manager = subprocess.run(query, env=dict(os.environ, **child), capture_output=True, text=True, timeout=15)
    assert child_manager.returncode == 0 and child_manager.stdout == original_manager.stdout and child_manager.stdout.strip()
    assert Path(child["XDG_RUNTIME_DIR"]) != profile.session_runtime
    assert (Path(child["XDG_RUNTIME_DIR"]) / "systemd").resolve() == (profile.session_runtime / "systemd").resolve()
    results.append({"id": "disk-runtime-reaches-real-session-manager", "status": "PASS"})
    profile.verify(require_console=True)
    summary = {"status": "PASS", "cases": results, "profile": profile.record(),
               "scope": "actual-guest identity/CLI/console protection only; no product behavior claim"}
    (args.output / "result.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
