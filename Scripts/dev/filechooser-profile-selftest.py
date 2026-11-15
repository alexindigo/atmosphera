#!/usr/bin/env python3
"""Profile refusal and propagation checks; run only in the assigned guest."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from filechooser_profile import GuestProfile, ProfileBlocked, current_profile, profile_argument


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.parse_args()
    profile = current_profile()
    profile.verify()
    data = json.loads(profile.path.read_text())
    cases = []
    with tempfile.TemporaryDirectory(prefix="profile-selftest-", dir=os.environ["TMPDIR"]) as directory:
        directory = Path(directory)
        for field, value in (("uuid", "00000000-0000-4000-8000-000000000000"),
                             ("mac", "02:00:00:00:00:00"), ("uid", profile.uid + 1),
                             ("home", "/nonexistent"), ("source", "/outside/source"),
                             ("evidence", str(profile.source)), ("runtime", str(profile.workspace)),
                             ("sshHostKey", "ssh-ed25519 AAAA")):
            candidate = directory / (field + ".json")
            candidate.write_text(json.dumps(dict(data, **{field: value})))
            try:
                GuestProfile(candidate).verify()
            except ProfileBlocked:
                cases.append(field)
            else:
                raise AssertionError("foreign/invalid " + field + " accepted")
        symlink = directory / "profile-link.json"
        symlink.symlink_to(profile.path)
        try:
            GuestProfile(symlink)
        except ProfileBlocked:
            cases.append("symlink")
        else:
            raise AssertionError("symlink profile accepted")
        changed = directory / "changed.json"
        changed.write_text(json.dumps(data))
        captured = GuestProfile(changed)
        changed.write_text(json.dumps(data) + "\n")
        try:
            captured.verify()
        except ProfileBlocked:
            cases.append("changed-after-capture")
        else:
            raise AssertionError("changed profile accepted")
        env = dict(os.environ)
        env.pop("FILECHOOSER_GUEST_PROFILE", None)
        missing = subprocess.run(["timeout", "10", sys.executable, "-B", "-c",
                                  "from filechooser_profile import current_profile; current_profile()"],
                                 env=env, cwd=Path(__file__).parent, capture_output=True, text=True, timeout=15)
        assert missing.returncode != 0 and "--guest-profile" in missing.stderr
        cases.append("missing-explicit-profile")
    print(json.dumps({"passed": True, "cases": cases, "profileSha256": profile.sha256}))


if __name__ == "__main__":
    main()
