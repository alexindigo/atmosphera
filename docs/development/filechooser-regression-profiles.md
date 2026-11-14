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
timeout 900 python3 -B Scripts/dev/filechooser-units.py --guest-profile "$profile" --source "$PWD" --output "$PWD/../evidence/units-LABEL"
timeout 900 python3 -B Scripts/dev/filechooser-portal-regression.py --guest-profile "$profile" --source "$PWD" --label portal-LABEL
timeout 900 python3 -B Scripts/dev/filechooser-ui-regression.py --guest-profile "$profile" --source "$PWD" --label ui-LABEL
```

Each label must be fresh. `filechooser_regression.py` is their shared library,
not a CLI. These commands preserve complete extracted working trees and evidence;
they create no workspace capsules. The profile must be explicitly updated when
the authorized guest changes. Do not spoof a MAC or weaken a failing check.

The UI runner also accepts `--path-only` for a short path-entry partition during
iteration. It retains its runtime-error and isolation gates. Omit that flag for
the full pre-commit proof; it does not replace the complete UI walk. Unit output
paths must be absolute because the private supervisor changes working directory.

The private supervisor also owns a PipeWire server and policy-only WirePlumber
with one null sink. It loads no hardware monitors and cannot connect to a login
or host audio endpoint. The initial graph is recorded as `audio-graph.json`;
all audio processes retain the same namespace, cgroup and process audit as the
compositor and keyboard. Install `pipewire` and `wireplumber` inside the assigned
guest alongside the existing Sway, media/image/PDF and compiler prerequisites.

The unit suite's real EROFS case uses an explicitly provisioned read-only bind
mount inside the assigned guest workspace. It changes no host or shared mount.
Before units, run inside `atmosphera-mov-filter` on `ark.home`:

```sh
export TMPDIR=/home/tester/Projects/filechooser-usability/tmp
timeout 10 mkdir -p /home/tester/Projects/filechooser-usability/fixtures/read-only-source /home/tester/Projects/filechooser-usability/fixtures/read-only
timeout 10 sudo mount --bind /home/tester/Projects/filechooser-usability/fixtures/read-only-source /home/tester/Projects/filechooser-usability/fixtures/read-only
timeout 10 sudo mount -o remount,bind,ro /home/tester/Projects/filechooser-usability/fixtures/read-only
```

The private unprivileged test namespace inherits this mount read-only. The suite
checks ST_RDONLY, rather than substituting chmod for a filesystem error. Guest
shutdown removes the temporary mount; provision it again after a reboot.

Real-browser runs additionally seal the exact waiting private supervisor's OOM
minimum at 1000 before admitting any workload children. The outer controller
uses a fixed, short-lived guest-root helper, validating DMI UUID, UID, process
start time, command, namespace and cgroup through a pinned proc directory. The
helper only writes 1000 and launches no child workload. A fresh unprivileged
child must observe 1000 and a denied attempt to lower it; receipts are retained.
No capability is granted to the browser. Caps, sandboxing and all original audit
checks are unchanged; there is no score-repair loop or browser exception.
Only browser walks set LP_NUM_THREADS=1 and RAYON_NUM_THREADS=1 for their private
session's renderer pools, matching the existing one-CPU quota and task cap.
Other runners, especially the matched-idle scroll measurement, retain their
original environment. Firefox's disposable profile disables unused new-tab
preloading to avoid an extra privileged-content process within that same cap.
Browser and full-UI subjects reuse `filechooser-no-thp.py` and the existing media
resource-test allocator profile (`dirty_decay_ms:0,muzzy_decay_ms:0`), avoiding
huge-page/free-page retention under MemoryHigh. Both are process-only; no kernel
policy or accounting limit changes. Browser profile receipts record these inputs;
the UI uses the same profile to avoid retained software-renderer pages across
its many dialog/media cycles. Scroll benchmarks keep their original profile.

```sh
timeout 900 python3 -B Scripts/dev/filechooser-browser-regression.py --guest-profile "$profile" --source "$PWD" --label browser-LABEL --browser chromium
timeout 900 python3 -B Scripts/dev/filechooser-browser-regression.py --guest-profile "$profile" --source "$PWD" --label browser-LABEL2 --browser firefox
```
