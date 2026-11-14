# File chooser regression profiles

File chooser runners follow the settings runners' explicit guest-profile design
(commit `4b6a1c1`). No guest identity or workspace defaults to a historical VM.
Pass `--guest-profile FILE` to every top-level invocation. Owned private children
inherit that exact profile path and captured SHA256 through their scrubbed
environment. A profile identifies a separately authorized target, not permission.

The public JSON profile specifies version 1, name, UUID, MAC, Ed25519 host public
key, UID, real account home, disk-backed workspace, and disjoint canonical source,
evidence and runtime paths beneath that workspace. The outer controller verifies
DMI UUID, MAC, account/home, host key, ownership and disk TMPDIR before creating
roots or starting a workload. Private PID-namespace children retain the existing
account/MAC checks, additionally validate the captured profile digest and roots,
and retain all private bus/compositor/keyboard, cgroup, resource, serialization,
process-audit and namespace checks. Privileged DMI inspection stays outside the
unprivileged user namespace, before workload launch.

For the assigned `atmosphera-mov-filter` VM on `ark.home`, run only inside the
guest, from `/home/tester/Projects/filechooser-usability/source`:

```sh
export TMPDIR=/home/tester/Projects/filechooser-usability/tmp
profile=$PWD/Scripts/dev/fixtures/guest-profiles/atmosphera-mov-filter.json
timeout 900 python3 -B Scripts/dev/filechooser-units.py --guest-profile "$profile" --source "$PWD" --output ../evidence/units-LABEL
timeout 900 python3 -B Scripts/dev/filechooser-portal-regression.py --guest-profile "$profile" --source "$PWD" --label portal-LABEL
timeout 900 python3 -B Scripts/dev/filechooser-ui-regression.py --guest-profile "$profile" --source "$PWD" --label ui-LABEL
```

Each label must be fresh. `filechooser_regression.py` is their shared library,
not a CLI. These commands preserve complete extracted working trees and evidence;
they create no workspace capsules. The profile must be explicitly updated when
the authorized guest changes. Do not spoof a MAC or weaken a failing check.

The private supervisor also owns a PipeWire server and policy-only WirePlumber
with one null sink. It loads no hardware monitors and cannot connect to a login
or host audio endpoint. The initial graph is recorded as `audio-graph.json`;
all audio processes retain the same namespace, cgroup and process audit as the
compositor and keyboard. Install `pipewire` and `wireplumber` inside the assigned
guest alongside the existing Sway, media/image/PDF and compiler prerequisites.
